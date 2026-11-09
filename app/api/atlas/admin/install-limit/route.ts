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

// PATCH /api/atlas/admin/install-limit
//
// Two independent admin actions — monthly_install_limit and reset_usage,
// either alone or together in one request:
//   - monthly_install_limit: sets profiles.monthly_install_limit. null clears
//     the override back to the standard 25 (reserve_install_slot and
//     confirm_install_reservation both read this column directly, via
//     COALESCE(..., 25) — no redeploy needed for a limit change to apply,
//     and it takes effect on the client's very next install attempt).
//   - reset_usage: zeroes installs_this_month on every one of the target
//     user(s)' install_counts rows (one per registered device) for the
//     CURRENT period only — equivalent to "unlock now" without touching
//     their actual cap.
//
// Two scopes for who the action applies to:
//   - { user_id }: a single client.
//   - { scope: "all_active" }: every user with an active row in
//     `subscriptions` — computed server-side from that table rather than
//     trusting a client-supplied list, so it can't be tricked into a wider
//     blast radius than "currently active subscribers" by a stale page.
export async function PATCH(req: NextRequest) {
  const admin = await requireAdmin(req)
  if (!admin) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })

  let body: {
    user_id?: string
    scope?: 'all_active'
    monthly_install_limit?: number | null
    reset_usage?: boolean
  } = {}
  try { body = await req.json() } catch { /* no body sent */ }

  if ('monthly_install_limit' in body) {
    const limit = body.monthly_install_limit
    if (limit !== null && (typeof limit !== 'number' || !Number.isInteger(limit) || limit < 1)) {
      return NextResponse.json({ error: 'monthly_install_limit must be a positive integer or null' }, { status: 400 })
    }
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

  const results: Record<string, unknown> = { affected: userIDs.length }

  if ('monthly_install_limit' in body) {
    const limit = body.monthly_install_limit as number | null
    const { error } = await supabase.from('profiles').update({ monthly_install_limit: limit }).in('id', userIDs)
    if (error) return NextResponse.json({ error: error.message }, { status: 500 })
    results.monthly_install_limit = limit
  }

  if (body.reset_usage) {
    const { error } = await supabase.from('install_counts').update({ installs_this_month: 0 }).in('user_id', userIDs)
    if (error) return NextResponse.json({ error: error.message }, { status: 500 })
    results.reset_usage = true
  }

  return NextResponse.json({ ok: true, ...results })
}
