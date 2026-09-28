import { NextRequest, NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'

const supabaseAdmin = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
)

// POST /api/atlas/devices/register
// The ONLY sanctioned way to register an ATLAS device (P0-4). Calls the
// register_device RPC, which is entitlement-gated and atomically enforces
// the 3-device cap server-side. The devices table's client-facing INSERT
// RLS policy has been removed, so direct REST inserts are no longer
// possible — this route (using the service-role key) is the sole path.
//
// SECURITY: p_user_id passed to the RPC is ALWAYS the server-verified
// identity from the caller's Supabase access token — never a client-supplied
// field. A caller cannot register a device for another account by passing a
// different user id; there is no such field accepted in the request body.
export async function POST(req: NextRequest) {
  const token = req.headers.get('authorization')?.replace('Bearer ', '').trim()
  if (!token) return NextResponse.json({ allowed: false, reason: 'unauthorized' }, { status: 401 })

  const { data: { user }, error: authErr } = await supabaseAdmin.auth.getUser(token)
  if (authErr || !user) return NextResponse.json({ allowed: false, reason: 'unauthorized' }, { status: 401 })

  let body: { hardware_uuid?: string; device_name?: string } = {}
  try { body = await req.json() } catch { /* no body sent */ }
  const hardwareUUID = body.hardware_uuid?.trim()
  const deviceName   = body.device_name?.trim() ?? 'ATLAS Device'
  if (!hardwareUUID) {
    return NextResponse.json({ allowed: false, reason: 'missing_device_id' }, { status: 400 })
  }

  const { data, error } = await supabaseAdmin.rpc('register_device', {
    p_user_id: user.id, // server-verified identity — never client-supplied
    p_hardware_uuid: hardwareUUID,
    p_device_name: deviceName,
  })

  if (error) {
    console.error('[devices/register] RPC error:', error)
    // Fail closed — an unverifiable registration is never a granted one.
    return NextResponse.json({ allowed: false, reason: 'server_error' }, { status: 503 })
  }

  const status = data?.allowed ? 200 : 403
  return NextResponse.json(data, { status })
}
