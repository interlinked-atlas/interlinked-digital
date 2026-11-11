// Admin-only: manually grant (or revoke) ATLAS access for an account with no
// active Stripe subscription — e.g. unblocking a cancelled test account for
// further testing, or any other case where an admin wants to let someone in
// without a real subscription behind it.
//
// Deliberately a PURE local entitlement override:
//   - Never calls Stripe, never creates/touches a real subscription there —
//     the account's real Stripe state (if any) stays exactly as it was.
//   - Never touches profiles.grace_period_used_at — an account's real
//     once-per-lifetime grace-period history stays accurate regardless of
//     an admin override layered on top of it.
//   - Sets subscriptions.admin_granted_access so this is always visibly
//     distinguishable from a real paying subscriber, in the admin panel and
//     in any future audit.
import { NextRequest, NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'

const ADMIN_EMAIL = 'titantinstaller@gmail.com'

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
)

async function requireAdmin(req: NextRequest) {
  const token = req.headers.get('authorization')?.replace('Bearer ', '').trim()
  if (!token) return null
  const { data: { user }, error } = await supabase.auth.getUser(token)
  if (error || !user) return null
  if (user.email?.toLowerCase() !== ADMIN_EMAIL.toLowerCase()) return null
  return user
}

// PATCH /api/atlas/admin/grant-access
// body: { user_id: string, granted: boolean }
export async function PATCH(req: NextRequest) {
  const admin = await requireAdmin(req)
  if (!admin) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })

  let body: { user_id?: string; granted?: boolean } = {}
  try { body = await req.json() } catch { /* no body sent */ }

  const userID = body.user_id?.trim()
  if (!userID) return NextResponse.json({ error: 'missing_user_id' }, { status: 400 })
  if (typeof body.granted !== 'boolean') return NextResponse.json({ error: 'missing_granted_boolean' }, { status: 400 })

  const { data: existingSub } = await supabase
    .from('subscriptions')
    .select('id')
    .eq('user_id', userID)
    .maybeSingle()

  if (body.granted) {
    // Both tables matter here for two different reasons: AuthManager.swift's
    // hard sign-in block checks profiles.subscription_status, while
    // GET /api/atlas/entitlement (feature-gating within an already-open
    // session) checks subscriptions.status — granting access needs both to
    // read 'active', or she'd pass one check and fail the other.
    const { error: profileErr } = await supabase
      .from('profiles')
      .update({ subscription_status: 'active' })
      .eq('id', userID)
    if (profileErr) return NextResponse.json({ error: profileErr.message }, { status: 500 })

    const subPayload = {
      status: 'active',
      cancel_at_period_end: false,
      cancelled_at: null,
      admin_granted_access: true,
      updated_at: new Date().toISOString(),
    }

    const { error: subErr } = existingSub
      ? await supabase.from('subscriptions').update(subPayload).eq('user_id', userID)
      : await supabase.from('subscriptions').insert({ user_id: userID, plan: 'atlas', ...subPayload })
    if (subErr) return NextResponse.json({ error: subErr.message }, { status: 500 })
  } else {
    // Revoke: back to a plain cancelled state. Does not touch atlas_suspended
    // (a separate, harsher lock) — revoking an admin grant just removes the
    // grant, it doesn't suspend the account.
    const { error: profileErr } = await supabase
      .from('profiles')
      .update({ subscription_status: 'cancelled' })
      .eq('id', userID)
    if (profileErr) return NextResponse.json({ error: profileErr.message }, { status: 500 })

    const { error: subErr } = await supabase
      .from('subscriptions')
      .update({ status: 'canceled', admin_granted_access: false, updated_at: new Date().toISOString() })
      .eq('user_id', userID)
    if (subErr) return NextResponse.json({ error: subErr.message }, { status: 500 })
  }

  return NextResponse.json({ ok: true, user_id: userID, granted: body.granted })
}
