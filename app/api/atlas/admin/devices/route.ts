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
// The client already polls its own device list every 5s (AuthManager's
// planSyncTimer) and force-signs-out if its hardware UUID is no longer
// present — so removal here takes effect on the client within ~5 seconds,
// no app update or rebuild required.
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

  return NextResponse.json({ ok: true, removed_uuid: device.hardware_uuid, user_id: device.user_id })
}
