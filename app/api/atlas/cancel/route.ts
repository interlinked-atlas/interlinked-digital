import { NextRequest, NextResponse } from 'next/server'
import Stripe from 'stripe'
import { createClient } from '@supabase/supabase-js'
import { sendEmail } from '@/lib/email'

const stripe = new Stripe(process.env.STRIPE_SECRET_KEY!, {
  apiVersion: '2025-04-30.basil',
})

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
)

export async function POST(req: NextRequest) {
  const token = req.headers.get('authorization')?.replace('Bearer ', '').trim()
  if (!token) {
    return NextResponse.json({ error: 'Missing authorization' }, { status: 401 })
  }

  // Optional, skippable cancellation-reason survey from the confirm modal —
  // never required, never parsed strictly: a missing/invalid body just means
  // no reason was given, and is never a reason to fail the cancellation
  // itself (survey logging happens after the real cancellation below, and
  // is itself wrapped so a logging failure can't block it either).
  let reason: string | null = null
  let feedback: string | null = null
  try {
    const body = await req.json()
    reason = typeof body?.reason === 'string' ? body.reason.slice(0, 200) : null
    feedback = typeof body?.feedback === 'string' ? body.feedback.slice(0, 2000) : null
  } catch { /* no/invalid body — treated as skipped survey */ }

  const { data: { user }, error: authError } = await supabase.auth.getUser(token)
  if (authError || !user) {
    return NextResponse.json({ error: 'Invalid token' }, { status: 401 })
  }

  // Prefer stripe_customer_id from subscriptions table — set by webhook, ID-based (reliable)
  // Fall back to email lookup for legacy accounts
  const { data: subRow } = await supabase
    .from('subscriptions')
    .select('stripe_customer_id, stripe_subscription_id')
    .eq('user_id', user.id)
    .maybeSingle()

  let customerId: string | null = subRow?.stripe_customer_id ?? null
  let stripeSubId: string | null = subRow?.stripe_subscription_id ?? null

  // Skip admin_bypass sentinel rows
  if (customerId === 'admin_bypass') { customerId = null; stripeSubId = null }

  if (!customerId) {
    const { data: profile } = await supabase
      .from('profiles').select('email').eq('id', user.id).single()
    if (!profile?.email) return NextResponse.json({ error: 'Profile not found' }, { status: 404 })
    const customers = await stripe.customers.list({ email: profile.email, limit: 1 })
    customerId = customers.data[0]?.id ?? null
  }

  if (!customerId) {
    return NextResponse.json({ error: 'No Stripe customer found' }, { status: 404 })
  }

  // Get subscription ID if not already known
  if (!stripeSubId) {
    const subscriptions = await stripe.subscriptions.list({
      customer: customerId,
      status: 'active',
      limit: 1,
    })
    stripeSubId = subscriptions.data[0]?.id ?? null
  }

  if (!stripeSubId) {
    return NextResponse.json({ error: 'No active subscription' }, { status: 404 })
  }

  const { data: profile } = await supabase.from('profiles').select('email, grace_period_used_at').eq('id', user.id).maybeSingle()

  // ATLAS policy (2026-11-11): the 10-day free-reactivation grace period is a
  // once-per-account lifetime benefit, not something repeatable by
  // cancelling and reactivating over and over — grace_period_used_at is set
  // the first time it's granted (below) and never cleared, including on
  // reactivation. A second-or-later cancellation skips the grace path
  // entirely and goes straight to a real, immediate Stripe cancellation —
  // she can still resubscribe normally at any time, she just never gets
  // another free-reactivate-no-charge window.
  let graceDeadline: Date | null = null

  if (!profile?.grace_period_used_at) {
    // ATLAS policy (2026-10-23): ATLAS access is revoked immediately on
    // cancellation, not at period end. This path still only schedules the
    // cancellation in Stripe (cancel_at_period_end: true) rather than calling
    // stripe.subscriptions.cancel() outright — Stripe keeps billing/charging
    // for the remainder of the paid period either way (a separate, deliberately
    // untouched question from ATLAS access itself), and this keeps the
    // subscription easily reversible via the Stripe-side reversal this same
    // update call supports. Entitlement itself is NOT written here — the
    // customer.subscription.updated webhook this call triggers now revokes
    // access immediately (see app/api/webhooks/stripe/route.ts's
    // upsertSubscription()), rather than waiting for the eventual
    // customer.subscription.deleted at period end.
    await stripe.subscriptions.update(stripeSubId, { cancel_at_period_end: true })

    // 10-day free-reactivation grace period starts now, at the moment of
    // cancellation — not at Stripe's eventual period-end deletion (which can
    // be weeks away). Stripe itself is untouched beyond cancel_at_period_end
    // above: the subscription stays fully enrolled, so reactivating within
    // the window is just flipping cancel_at_period_end back to false later
    // (see /api/atlas/reactivate) — same card, same renewal date, no new charge.
    const cancelledAt = new Date()
    graceDeadline = new Date(cancelledAt.getTime() + 10 * 24 * 60 * 60 * 1000)
    await supabase.from('subscriptions').update({ cancelled_at: cancelledAt.toISOString() }).eq('user_id', user.id)
    // Claimed the instant the grace period is granted — whether she goes on
    // to reactivate or lets it expire into suspension doesn't matter, she's
    // had the benefit of the option either way.
    await supabase.from('profiles').update({ grace_period_used_at: cancelledAt.toISOString() }).eq('id', user.id)

    if (profile?.email) {
      await sendEmail({
        to: profile.email,
        template: 'subscription-cancelled',
        data: { deadlineDate: graceDeadline.toLocaleDateString('en-US', { month: 'long', day: 'numeric', year: 'numeric' }) },
      })
    }
  } else {
    // Grace period already used once before — real, immediate cancellation.
    // No cancelled_at write (nothing for the grace-period-sweep cron or
    // /api/atlas/reactivate to key off), no pending Stripe-side cancellation
    // to reverse. The resulting customer.subscription.deleted webhook event
    // runs handleCancellation() (app/api/webhooks/stripe/route.ts), which
    // already writes the terminal 'cancelled' state atomically and
    // deliberately sends no email of its own — this route sends the one
    // user-facing email synchronously instead, same pattern as the grace path.
    await stripe.subscriptions.cancel(stripeSubId)
    if (profile?.email) {
      await sendEmail({ to: profile.email, template: 'subscription-cancelled-no-grace' })
    }
  }

  // Best-effort only — a logging failure here must never surface as a
  // cancellation failure to the user; the cancellation above has already
  // succeeded on both Stripe and our own side by this point.
  if (reason || feedback) {
    try {
      await supabase.from('billing_audit_log').insert({
        event: 'subscription.cancellation_feedback',
        user_id: user.id,
        email: profile?.email ?? null,
        plan: 'atlas',
        stripe_event: null,
        metadata: { reason, feedback, stripe_customer_id: customerId, stripe_subscription_id: stripeSubId },
        notes: 'Optional, skippable reason/feedback collected at the cancel-confirmation modal.',
      })
    } catch { /* non-blocking */ }
  }

  return NextResponse.json({
    ok: true,
    cancel_at_period_end: graceDeadline !== null,
    grace_deadline: graceDeadline ? graceDeadline.toISOString() : null,
  })
}
