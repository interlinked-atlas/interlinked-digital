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

// PATCH /api/atlas/admin/suspend
//
// Full, indefinite account lockout — distinct from "Remove / Kick" on a
// single device (which only removes that one device; the client can still
// sign in from another device under their limit). Suspending blocks the
// account everywhere:
//   - register_device() refuses any device, new or already-registered.
//   - reserve_install_slot() refuses any install, even on an already-
//     registered device, as defense in depth.
//   - The client's periodic profile poll (every 5s) picks up
//     atlas_suspended and force-signs-out an already-active session within
//     seconds, same mechanism as a cancelled subscription.
// Does not touch billing/subscription status — this is purely an access
// lock an admin can lift at any time by clearing it again.
export async function PATCH(req: NextRequest) {
  const admin = await requireAdmin(req)
  if (!admin) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })

  let body: { user_id?: string; suspended?: boolean } = {}
  try { body = await req.json() } catch { /* no body sent */ }

  const userID = body.user_id?.trim()
  if (!userID) return NextResponse.json({ error: 'missing_user_id' }, { status: 400 })
  if (typeof body.suspended !== 'boolean') return NextResponse.json({ error: 'missing_suspended_boolean' }, { status: 400 })

  const { error } = await supabase.from('profiles').update({ atlas_suspended: body.suspended }).eq('id', userID)
  if (error) return NextResponse.json({ error: error.message }, { status: 500 })

  return NextResponse.json({ ok: true, user_id: userID, suspended: body.suspended })
}
