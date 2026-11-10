import { NextRequest, NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
)

// POST /api/atlas/install-status
//
// Read-only status check — used by the Mac app to refresh its locally
// cached usage/limit without attempting an actual install. This exists
// specifically so an admin resetting a client's usage (or raising their
// limit) mid-period can actually take visible effect: the app's lock
// screen is driven by a local cache that normally only updates via a real
// install attempt, but the lock screen itself blocks that attempt from
// ever reaching the server — a deadlock without a side-effect-free way to
// re-check. Calls atlas_current_usage (no reservation, no row mutation),
// never check-install's reserve_install_slot.
export async function POST(req: NextRequest) {
  const token = req.headers.get('authorization')?.replace('Bearer ', '').trim()
  if (!token) return NextResponse.json({ error: 'unauthorized' }, { status: 401 })

  const { data: { user }, error: authErr } = await supabase.auth.getUser(token)
  if (authErr || !user) return NextResponse.json({ error: 'unauthorized' }, { status: 401 })

  const { data: profile } = await supabase
    .from('profiles')
    .select('atlas_forced_update_version')
    .eq('id', user.id)
    .maybeSingle()
  const forcedUpdateVersion = profile?.atlas_forced_update_version ?? null

  if (user.email?.toLowerCase() === 'titantinstaller@gmail.com') {
    return NextResponse.json({ used: 0, limit: 999999, remaining: 999999, forced_update_version: forcedUpdateVersion })
  }

  let body: { hardware_uuid?: string } = {}
  try { body = await req.json() } catch { /* no body sent */ }
  const hardwareUUID = body.hardware_uuid?.trim()
  if (!hardwareUUID) return NextResponse.json({ error: 'missing_device_id' }, { status: 400 })

  const { data, error } = await supabase.rpc('atlas_current_usage', {
    p_user_id: user.id,
    p_hardware_uuid: hardwareUUID,
  })

  if (error) {
    console.error('[install-status] RPC error:', error)
    return NextResponse.json({ error: 'server_error' }, { status: 503 })
  }

  return NextResponse.json({ ...data, forced_update_version: forcedUpdateVersion })
}
