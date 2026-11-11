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

  // ATLAS policy (2026-10-23): ATLAS access is revoked immediately on
  // cancellation, not at period end. This route still only schedules the
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
  const updatedSub = await stripe.subscriptions.update(stripeSubId, { cancel_at_period_end: true })

  // 10-day free-reactivation grace period starts now, at the moment of
  // cancellation — not at Stripe's eventual period-end deletion (which can
  // be weeks away). Stripe itself is untouched beyond cancel_at_period_end
  // above: the subscription stays fully enrolled, so reactivating within
  // the window is just flipping cancel_at_period_end back to false later
  // (see /api/atlas/reactivate) — same card, same renewal date, no new charge.
  const cancelledAt = new Date()
  const deadline = new Date(cancelledAt.getTime() + 10 * 24 * 60 * 60 * 1000)
  await supabase.from('subscriptions').update({ cancelled_at: cancelledAt.toISOString() }).eq('user_id', user.id)

  const { data: profile } = await supabase.from('profiles').select('email').eq('id', user.id).maybeSingle()
  if (profile?.email) {
    await sendEmail({
      to: profile.email,
      template: 'subscription-cancelled',
      data: { deadlineDate: deadline.toLocaleDateString('en-US', { month: 'long', day: 'numeric', year: 'numeric' }) },
    })
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
    cancel_at_period_end: true,
    grace_deadline: deadline.toISOString(),
    access_until: updatedSub.current_period_end
      ? new Date(updatedSub.current_period_end * 1000).toISOString()
      : null,
  })
}
