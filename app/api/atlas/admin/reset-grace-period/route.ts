// Admin-only: let a specific account use the 10-day free-reactivation
// cancellation grace period again, as a one-off exception to the
// once-per-lifetime policy (see app/api/atlas/cancel/route.ts and
// supabase/migrations/20261111010000_grace_period_once_only.sql).
//
// Deliberately a single, isolated field clear — profiles.grace_period_used_at
// was built as a standalone eligibility flag with no live link to Stripe, so
// this never touches Stripe, never reactivates or modifies any subscription,
// and has no effect on the account's CURRENT cancellation state (a genuinely
// cancelled Stripe subscription can't be revived). It only changes what
// happens the NEXT time this account cancels, whenever that is: the grace
// flow applies again instead of an immediate, final cancellation.
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

// PATCH /api/atlas/admin/reset-grace-period
// body: { user_id: string }
export async function PATCH(req: NextRequest) {
  const admin = await requireAdmin(req)
  if (!admin) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })

  let body: { user_id?: string } = {}
  try { body = await req.json() } catch { /* no body sent */ }

  const userID = body.user_id?.trim()
  if (!userID) return NextResponse.json({ error: 'missing_user_id' }, { status: 400 })

  const { error } = await supabase
    .from('profiles')
    .update({ grace_period_used_at: null })
    .eq('id', userID)
  if (error) return NextResponse.json({ error: error.message }, { status: 500 })

  return NextResponse.json({ ok: true, user_id: userID })
}
