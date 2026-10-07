import { NextRequest, NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
)

const ATLAS_MONTHLY_LIMIT = 25

// POST /api/atlas/install-count
// Confirms or releases a reservation created by /api/atlas/check-install
// (reserve_install_slot). This is the ONLY place installs_this_month is
// incremented, and only on action: "confirm" — a reservation transitioning
// reserved -> confirmed. action: "release" frees a reservation on
// failure/cancellation/skip without incrementing anything. Both are idempotent
// against retries/duplicate requests — see confirm_install_reservation and
// release_install_reservation for the exact state-machine guarantees.
//
// Period is always a calendar month, regardless of billing_interval/billing_anchor_day
// — the install-limit period is intentionally independent of billing cadence.
//
// monthly_install_counts is no longer written here. It is left in place, unused by
// this route, pending a separate approved cleanup once all its other callers are
// confirmed clear.
export async function POST(req: NextRequest) {
  const token = req.headers.get('authorization')?.replace('Bearer ', '').trim()
  if (!token) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

  const { data: { user }, error } = await supabase.auth.getUser(token)
  if (error || !user) return NextResponse.json({ error: 'Invalid token' }, { status: 401 })

  let body: { reservation_id?: string; action?: string } = {}
  try { body = await req.json() } catch { /* no body sent */ }
  const reservationID = body.reservation_id?.trim()
  const action = body.action?.trim()
  if (!reservationID) {
    return NextResponse.json({ error: 'missing_reservation_id' }, { status: 400 })
  }
  if (action !== 'confirm' && action !== 'release') {
    return NextResponse.json({ error: 'invalid_action' }, { status: 400 })
  }

  if (action === 'release') {
    const { data, error: rpcError } = await supabase.rpc('release_install_reservation', {
      p_reservation_id: reservationID,
    })
    if (rpcError) {
      console.error('[install-count] release RPC error:', rpcError)
      return NextResponse.json({ released: false, error: rpcError.message }, { status: 500 })
    }
    return NextResponse.json(data)
  }

  const { data, error: rpcError } = await supabase.rpc('confirm_install_reservation', {
    p_reservation_id: reservationID,
  })

  if (rpcError) {
    console.error('[install-count] confirm RPC error:', rpcError)
    return NextResponse.json({ confirmed: false, error: rpcError.message }, { status: 500 })
  }

  if (data?.confirmed === false) {
    return NextResponse.json(data, { status: 403 })
  }

  return NextResponse.json({
    allowed:    true,
    used:       data.used,
    limit:      ATLAS_MONTHLY_LIMIT,
    remaining:  data.remaining,
  })
}
