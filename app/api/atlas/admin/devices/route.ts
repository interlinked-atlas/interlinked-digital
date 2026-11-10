import { NextRequest, NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
)

const ADMIN_EMAIL = 'titantinstaller@gmail.com'

async function requireAdmin(req: NextRequest) {
  const token = req.headers.get('authorization')?.replace('Bearer ', '').trim()
  if (!token) return null
  const { data: { user }, error } = await supabase.auth.getUser(token)
  if (error || !user) return null
  if (user.email?.toLowerCase() !== ADMIN_EMAIL.toLowerCase()) return null
  return user
}

// DELETE /api/atlas/admin/devices
//
// Admin-only forced device removal — "kick a device off the account" for
// cases where the client can't or won't remove it themselves. Unlike
// /api/atlas/devices (self-service, scoped to the caller's own user_id),
// this can delete any device by id regardless of owner.
//
// Also inserts a device_blocks row for the hardware_uuid being removed.
// This matters because register_device()'s self-service "same device may
// rejoin instantly" allowance (device_removals has an entry for that exact
// hardware_uuid already) would otherwise let the just-kicked device
// silently re-register itself the next time the app launches — which is
// exactly what happened in testing: a plain delete alone let the client
// quietly rejoin on relaunch instead of actually being kicked. The block
// takes priority over every other registration path.
//
// The client already polls its own device list every 5s (and, as of a
// later fix, a second redundant poll) and force-signs-out if its hardware
// UUID is no longer present — so removal here takes effect on an actively
// running client within seconds, no app update or rebuild required. A
// blocked device also can never silently rejoin on relaunch.
export async function DELETE(req: NextRequest) {
  const admin = await requireAdmin(req)
  if (!admin) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })

  let body: { device_id?: string } = {}
  try { body = await req.json() } catch { /* no body sent */ }
  const deviceID = body.device_id?.trim()
  if (!deviceID) return NextResponse.json({ error: 'missing_device_id' }, { status: 400 })

  const { data: device } = await supabase
    .from('devices')
    .select('id, hardware_uuid, user_id')
    .eq('id', deviceID)
    .maybeSingle()

  if (!device) return NextResponse.json({ error: 'device_not_found' }, { status: 404 })

  const { error } = await supabase.from('devices').delete().eq('id', deviceID)
  if (error) return NextResponse.json({ error: error.message }, { status: 500 })

  await supabase.from('device_blocks').upsert({
    user_id: device.user_id,
    hardware_uuid: device.hardware_uuid,
  })

  return NextResponse.json({ ok: true, removed_uuid: device.hardware_uuid, user_id: device.user_id })
}

// PATCH /api/atlas/admin/devices — unblock a previously kicked device so it
// can register again (e.g. the client got a legitimate new reason to use it).
export async function PATCH(req: NextRequest) {
  const admin = await requireAdmin(req)
  if (!admin) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })

  let body: { user_id?: string; hardware_uuid?: string } = {}
  try { body = await req.json() } catch { /* no body sent */ }
  const userID = body.user_id?.trim()
  const hardwareUUID = body.hardware_uuid?.trim()
  if (!userID || !hardwareUUID) return NextResponse.json({ error: 'missing_user_id_or_hardware_uuid' }, { status: 400 })

  const { error } = await supabase.from('device_blocks')
    .delete()
    .eq('user_id', userID)
    .eq('hardware_uuid', hardwareUUID)
  if (error) return NextResponse.json({ error: error.message }, { status: 500 })

  return NextResponse.json({ ok: true })
}
