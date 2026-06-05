import { NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'
import { createHmac } from 'crypto'

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
)

// POST /api/atlas/token
// Called by ATLAS app after successful authentication.
// Returns a signed offline token (30-day TTL) tied to the user's hardware UUID.
export async function POST(request: Request) {
  const authHeader = request.headers.get('authorization')
  if (!authHeader?.startsWith('Bearer ')) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  }

  const accessToken = authHeader.substring(7)

  let body: { hardware_uuid?: string }
  try {
    body = await request.json()
  } catch {
    return NextResponse.json({ error: 'Invalid JSON body' }, { status: 400 })
  }

  const hardwareUUID = body.hardware_uuid
  if (!hardwareUUID || typeof hardwareUUID !== 'string') {
    return NextResponse.json({ error: 'hardware_uuid required' }, { status: 400 })
  }

  // Verify Supabase session
  const { data: { user }, error: authError } = await supabase.auth.getUser(accessToken)
  if (authError || !user) {
    return NextResponse.json({ error: 'Invalid or expired session' }, { status: 401 })
  }

  // Fetch user's plan
  const { data: profileRow, error: profileError } = await supabase
    .from('profiles')
    .select('plan, subscription_status')
    .eq('id', user.id)
    .single()

  if (profileError || !profileRow) {
    return NextResponse.json({ error: 'Profile not found' }, { status: 404 })
  }

  if (profileRow.subscription_status !== 'active') {
    return NextResponse.json({ error: 'Subscription not active' }, { status: 403 })
  }

  const secret = process.env.ATLAS_TOKEN_SECRET
  if (!secret) {
    console.error('[ATLAS] ATLAS_TOKEN_SECRET not configured')
    return NextResponse.json({ error: 'Server configuration error' }, { status: 500 })
  }

  // Build claims: 30-day TTL
  const exp = Math.floor(Date.now() / 1000) + 30 * 24 * 60 * 60
  const claims = {
    u: user.id,
    h: hardwareUUID,
    p: profileRow.plan as string,
    e: exp,
  }

  // base64url-encode the JSON payload
  const payloadJson   = JSON.stringify(claims)
  const payloadB64url = Buffer.from(payloadJson).toString('base64url')

  // HMAC-SHA256 signature over the base64url payload bytes
  const sig       = createHmac('sha256', Buffer.from(secret, 'hex'))
                      .update(payloadB64url)
                      .digest()
  const sigB64url = sig.toString('base64url')

  const token = `${payloadB64url}.${sigB64url}`

  return NextResponse.json({ token })
}
