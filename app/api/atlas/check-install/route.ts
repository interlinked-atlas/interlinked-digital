import { NextRequest, NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
)

// Atomic reserve — the authoritative capacity decision. Locks the single
// account-wide install_counts row (keyed by user_id) and creates a
// reservation in the same transaction as the capacity check, closing the
// check-then-install-then-record race. Does NOT increment
// installs_this_month — see /api/atlas/install-count for confirm/release.
// Limit is a flat 25 per account per billing period, shared across every
// device on the account (not per device), regardless of billing cadence.
// hardware_uuid is still required and stored on the reservation as
// metadata/audit information, but does not affect which pool is checked.
// Idempotent: retrying with the same reservation_id returns the existing
// reservation's state rather than claiming a second slot.
export async function POST(req: NextRequest) {
  // Verify Bearer token
  const token = req.headers.get('authorization')?.replace('Bearer ', '').trim()
  if (!token) return NextResponse.json({ allowed: false, reason: 'unauthorized' }, { status: 401 })

  const { data: { user }, error: authErr } = await supabase.auth.getUser(token)
  if (authErr || !user) return NextResponse.json({ allowed: false, reason: 'unauthorized' }, { status: 401 })

  // Admin has unlimited installs — no cap, no reservation needed
  if (user.email?.toLowerCase() === 'titantinstaller@gmail.com') {
    return NextResponse.json({ allowed: true, reason: null, monthly_used: 0 })
  }

  let body: { hardware_uuid?: string; reservation_id?: string } = {}
  try { body = await req.json() } catch { /* no body sent */ }
  const hardwareUUID = body.hardware_uuid?.trim()
  const reservationID = body.reservation_id?.trim()
  if (!hardwareUUID) {
    return NextResponse.json({ allowed: false, reason: 'missing_device_id' }, { status: 400 })
  }
  if (!reservationID) {
    return NextResponse.json({ allowed: false, reason: 'missing_reservation_id' }, { status: 400 })
  }

  const { data, error } = await supabase.rpc('reserve_install_slot', {
    p_user_id: user.id,
    p_hardware_uuid: hardwareUUID,
    p_reservation_id: reservationID,
  })

  if (error) {
    console.error('[check-install] RPC error:', error)
    // P1-4: fail CLOSED. The server was reached but could not authoritatively
    // determine install permission — that is never the same as permission
    // granted. 'server_error' is a distinct reason from 'monthly_limit' /
    // 'not_entitled' / 'device_not_registered' so the desktop can present
    // "couldn't verify — please retry" rather than a false limit-reached
    // message.
    return NextResponse.json({ allowed: false, reason: 'server_error' }, { status: 503 })
  }

  return NextResponse.json(data)
}
