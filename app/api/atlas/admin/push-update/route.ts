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

// PATCH /api/atlas/admin/push-update
//
// Sets profiles.atlas_forced_update_version for one or all active subscribers.
// The Mac app picks this up on its existing ~18s install-status poll (and on
// launch/foreground) — if it's set and newer than the app's own running
// version, the app blocks with an update-required screen until the user
// updates. null clears the force (no pending required update).
export async function PATCH(req: NextRequest) {
  const admin = await requireAdmin(req)
  if (!admin) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })

  let body: {
    user_id?: string
    scope?: 'all_active'
    forced_update_version?: string | null
  } = {}
  try { body = await req.json() } catch { /* no body sent */ }

  if (!('forced_update_version' in body)) {
    return NextResponse.json({ error: 'missing_forced_update_version' }, { status: 400 })
  }
  const version = body.forced_update_version?.trim() || null
  if (version !== null && !/^\d+(\.\d+){1,2}$/.test(version)) {
    return NextResponse.json({ error: 'forced_update_version must look like 1.6 or 1.6.0, or null to clear' }, { status: 400 })
  }

  let userIDs: string[]
  if (body.scope === 'all_active') {
    const { data, error } = await supabase.from('subscriptions').select('user_id').eq('status', 'active')
    if (error) return NextResponse.json({ error: error.message }, { status: 500 })
    userIDs = Array.from(new Set((data ?? []).map(r => r.user_id)))
    if (userIDs.length === 0) return NextResponse.json({ ok: true, affected: 0 })
  } else {
    const userID = body.user_id?.trim()
    if (!userID) return NextResponse.json({ error: 'missing_user_id_or_scope' }, { status: 400 })
    userIDs = [userID]
  }

  const { error } = await supabase.from('profiles').update({ atlas_forced_update_version: version }).in('id', userIDs)
  if (error) return NextResponse.json({ error: error.message }, { status: 500 })

  return NextResponse.json({ ok: true, affected: userIDs.length, forced_update_version: version })
}
