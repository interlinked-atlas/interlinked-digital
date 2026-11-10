import { NextRequest, NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'
import { sendEmail } from '@/lib/email'

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
)

const GRACE_DAYS = 10
const REMINDER_AT_DAYS = 8 // "2 days left"

// GET /api/cron/grace-period-sweep — runs daily via vercel.json cron.
//
// Two jobs, both scoped to subscriptions still mid-cancellation
// (cancel_at_period_end = true, cancelled_at set, never reactivated):
//   1. At day 8 (2 days left): send the reminder email once.
//   2. Past day 10: permanently suspend the account (reason:
//      'grace_expired') and send the closure email. Deliberately never
//      touches Stripe — cancel_at_period_end already finishes the
//      cancellation there on its own schedule; this only gates ATLAS
//      access going forward. Logs/devices/history/recovery kits are
//      untouched — nothing is deleted.
export async function GET(req: NextRequest) {
  const authHeader = req.headers.get('authorization')
  if (process.env.CRON_SECRET && authHeader !== `Bearer ${process.env.CRON_SECRET}`) {
    return NextResponse.json({ error: 'unauthorized' }, { status: 401 })
  }

  const now = Date.now()

  const { data: candidates, error } = await supabase
    .from('subscriptions')
    .select('user_id, cancelled_at')
    .eq('cancel_at_period_end', true)
    .not('cancelled_at', 'is', null)

  if (error) return NextResponse.json({ error: error.message }, { status: 500 })

  let reminded = 0
  let suspended = 0

  for (const row of candidates ?? []) {
    const cancelledAt = new Date(row.cancelled_at as string).getTime()
    const daysElapsed = (now - cancelledAt) / (24 * 60 * 60 * 1000)

    const { data: profile } = await supabase
      .from('profiles')
      .select('email, atlas_suspended, grace_reminder_sent_at')
      .eq('id', row.user_id)
      .maybeSingle()
    if (!profile?.email || profile.atlas_suspended) continue

    if (daysElapsed >= GRACE_DAYS) {
      await supabase.from('profiles').update({
        atlas_suspended: true,
        atlas_suspended_reason: 'grace_expired',
      }).eq('id', row.user_id)
      await sendEmail({ to: profile.email, template: 'account-suspended' })
      suspended++
      continue
    }

    if (daysElapsed >= REMINDER_AT_DAYS && !profile.grace_reminder_sent_at) {
      const deadline = new Date(cancelledAt + GRACE_DAYS * 24 * 60 * 60 * 1000)
      await sendEmail({
        to: profile.email,
        template: 'grace-period-reminder',
        data: { deadlineDate: deadline.toLocaleDateString('en-US', { month: 'long', day: 'numeric', year: 'numeric' }) },
      })
      await supabase.from('profiles').update({ grace_reminder_sent_at: new Date().toISOString() }).eq('id', row.user_id)
      reminded++
    }
  }

  return NextResponse.json({ ok: true, checked: candidates?.length ?? 0, reminded, suspended })
}
