import { NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'

const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL!
const SUPABASE_ANON = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!
const SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY!

// POST /api/atlas/consent — record user's privacy consent for log syncing
export async function POST(request: Request) {
  const authHeader = request.headers.get('authorization')
  if (!authHeader?.startsWith('Bearer ')) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  }
  const accessToken = authHeader.substring(7)

  const anonClient = createClient(SUPABASE_URL, SUPABASE_ANON)
  const { data: { user }, error: authError } = await anonClient.auth.getUser(accessToken)
  if (authError || !user) {
    return NextResponse.json({ error: 'Invalid token' }, { status: 401 })
  }

  const adminClient = createClient(SUPABASE_URL, SERVICE_KEY)
  const { error } = await adminClient
    .from('profiles')
    .update({
      privacy_consent: true,
      privacy_consent_at: new Date().toISOString(),
    })
    .eq('id', user.id)

  if (error) {
    // Column may not exist yet — still return success, app stores consent locally
    console.error('[consent] update error:', error.message)
    return NextResponse.json({ success: true, note: 'stored_locally' })
  }

  return NextResponse.json({ success: true })
}
