import { NextRequest, NextResponse } from 'next/server'
import Stripe from 'stripe'
import { createClient } from '@supabase/supabase-js'
import { sendEmail } from '@/lib/email'

const stripe = new Stripe(process.env.STRIPE_SECRET_KEY!, { apiVersion: '2025-04-30.basil' })
// Test-mode counterpart — only used when a test-mode event is received
// (event.livemode === false). A live event always uses `stripe` above.
const stripeTest = process.env.STRIPE_SECRET_KEY_TEST
  ? new Stripe(process.env.STRIPE_SECRET_KEY_TEST, { apiVersion: '2025-04-30.basil' })
  : null

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
)

const ADMIN_EMAIL = 'interlinked.digital@gmail.com'

const PRICE_PLAN: Record<string, { profile: string; subscription: string }> = {
  // ATLAS — new single plan (monthly + annual)
  'price_1U9uOBA1Bm2dPCGc73d3ZbA5': { profile: 'atlas', subscription: 'atlas' }, // $30/month
  'price_1U9uOCA1Bm2dPCGcjRbOpXii': { profile: 'atlas', subscription: 'atlas' }, // $300/year
  // Legacy prices — map to atlas for backward compat (test accounts, replays)
  'price_1TdIbOA1Bm2dPCGcBzQIiXGV': { profile: 'atlas', subscription: 'atlas' }, // old standard monthly
  'price_1TdIbOA1Bm2dPCGcpLFkuAea': { profile: 'atlas', subscription: 'atlas' }, // old pro monthly
  'price_1TnTWwA1Bm2dPCGchzhfeeZy': { profile: 'atlas', subscription: 'atlas' }, // old standard annual
  'price_1TnTXWA1Bm2dPCGcPInuLsUt': { profile: 'atlas', subscription: 'atlas' }, // old pro annual
  'price_1TliuWA1Bm2dPCGcbpXH9hE5': { profile: 'atlas', subscription: 'atlas' }, // old test standard
  'price_1TlitLA1Bm2dPCGcZRFxm68J': { profile: 'atlas', subscription: 'atlas' }, // old test pro
  'price_1TqJSEA1Bm2dPCGcEtL4Au0e': { profile: 'atlas', subscription: 'atlas' }, // $0.50 flow test
}

async function getUserByEmail(email: string) {
  const { data } = await supabase
    .from('profiles')
    .select('id')
    .eq('email', email)
    .single()
  return data?.id ?? null
}

async function auditLog(event: string, opts: {
  userId?: string | null
  email?: string | null
  plan?: string | null
  stripeEvent?: string
  metadata?: Record<string, unknown>
  notes?: string
}) {
  await supabase.from('billing_audit_log').insert({
    event,
    user_id:      opts.userId   ?? null,
    email:        opts.email    ?? null,
    plan:         opts.plan     ?? null,
    stripe_event: opts.stripeEvent ?? null,
    metadata:     opts.metadata ?? null,
    notes:        opts.notes    ?? null,
  })
}

async function notifyAdmin(subject: string, body: string) {
  await sendEmail({
    to: ADMIN_EMAIL,
    template: 'admin-notification',
    data: { subject, body },
  })
}

async function upsertSubscription(
  userId: string,
  stripeCustomerId: string,
  stripeSubscriptionId: string,
  plan: { profile: string; subscription: string },
  status: string,
  periodEnd: number | null,
  cancelAtPeriodEnd: boolean
) {
  const profileStatus = status === 'active' ? 'active' : status
  const subStatus = status === 'active' ? 'active'
    : status === 'canceled' ? 'canceled'
    : status === 'past_due' ? 'past_due'
    : 'incomplete'

  const { error: profileErr } = await supabase
    .from('profiles')
    .update({ plan: plan.profile, subscription_status: profileStatus })
    .eq('id', userId)
  if (profileErr) console.error('[ATLAS] Profile update failed:', profileErr.message)

  // Safe upsert: check for existing row by user_id, then update or insert.
  // Avoids relying on a unique constraint on stripe_subscription_id.
  const subPayload = {
    user_id: userId,
    stripe_customer_id: stripeCustomerId,
    stripe_subscription_id: stripeSubscriptionId,
    plan: plan.subscription,
    status: subStatus,
    current_period_end: periodEnd ? new Date(periodEnd * 1000).toISOString() : null,
    cancel_at_period_end: cancelAtPeriodEnd,
    updated_at: new Date().toISOString(),
  }

  const { data: existing } = await supabase
    .from('subscriptions').select('id').eq('user_id', userId).maybeSingle()

  if (existing) {
    const { error: updErr } = await supabase
      .from('subscriptions').update(subPayload).eq('user_id', userId)
    if (updErr) console.error('[ATLAS] Subscription update failed:', updErr.message)
  } else {
    const { error: insErr } = await supabase
      .from('subscriptions').insert(subPayload)
    if (insErr) console.error('[ATLAS] Subscription insert failed:', insErr.message)
  }

  console.log(`[ATLAS] Updated user ${userId} → plan:${plan.profile} status:${profileStatus}`)
}

async function handleCancellation(stripeClient: Stripe, customerId: string, stripeEvent: string) {
  const customer = await stripeClient.customers.retrieve(customerId)
  if (customer.deleted) return
  const email = (customer as Stripe.Customer).email
  if (!email) return

  const userId = await getUserByEmail(email)
  if (!userId) return

  // Idempotency guard: if already cancelled, skip writes and emails.
  // Prevents duplicates when cancel_at_period_end triggers an early cancellation
  // and customer.subscription.deleted fires again at period end.
  const { data: currentProfile } = await supabase
    .from('profiles')
    .select('subscription_status')
    .eq('id', userId)
    .single()
  if (currentProfile?.subscription_status === 'cancelled') {
    console.log(`[ATLAS] handleCancellation: already cancelled for ${email} — skipping`)
    return
  }

  await supabase
    .from('profiles')
    .update({ subscription_status: 'cancelled', plan: 'free' })
    .eq('id', userId)

  await supabase
    .from('subscriptions')
    .update({ status: 'canceled', updated_at: new Date().toISOString() })
    .eq('stripe_customer_id', customerId)

  // User email
  await sendEmail({ to: email, template: 'subscription-cancelled' })

  // Admin notification
  await notifyAdmin(
    `❌ Subscription Cancelled — ${email}`,
    `User ${email} has cancelled their ATLAS subscription.\n\nStripe Customer: ${customerId}\nTime: ${new Date().toUTCString()}`
  )

  // Audit log
  await auditLog('subscription.cancelled', {
    userId, email, plan: 'free',
    stripeEvent,
    metadata: { stripe_customer_id: customerId },
  })

  console.log(`[ATLAS] Cancelled subscription for ${email}`)
}

// Revokes paid access in Supabase only — never calls any Stripe refund/cancel
// API. Used by dispute/full-refund handling below. Idempotent: a no-op if the
// account is already non-active, same guard pattern as handleCancellation.
async function revokeAccessForCustomer(customerId: string, reason: string, stripeEvent: string, metadata: Record<string, unknown>) {
  let customer: Stripe.Customer | Stripe.DeletedCustomer
  try { customer = await stripe.customers.retrieve(customerId) } catch { return }
  if (customer.deleted) return
  const email = (customer as Stripe.Customer).email
  if (!email) return
  const userId = await getUserByEmail(email)
  if (!userId) return

  const { data: currentProfile } = await supabase
    .from('profiles')
    .select('subscription_status')
    .eq('id', userId)
    .single()
  if (currentProfile?.subscription_status === 'cancelled') {
    console.log(`[ATLAS] revokeAccessForCustomer(${reason}): already non-active for ${email} — skipping`)
    return
  }

  await supabase
    .from('profiles')
    .update({ subscription_status: 'cancelled', plan: 'free' })
    .eq('id', userId)

  await supabase
    .from('subscriptions')
    .update({ status: 'canceled', updated_at: new Date().toISOString() })
    .eq('stripe_customer_id', customerId)

  await notifyAdmin(
    `⚠️ Access Revoked (${reason}) — ${email}`,
    `ATLAS access revoked for ${email} due to ${reason}.\n\nStripe Customer: ${customerId}\nTime: ${new Date().toUTCString()}`
  )

  await auditLog(`access.revoked.${reason}`, {
    userId, email, plan: 'free',
    stripeEvent,
    metadata,
  })

  console.log(`[ATLAS] Revoked access for ${email} (${reason})`)
}

export async function POST(req: NextRequest) {
  const body = await req.text()
  const signature = req.headers.get('stripe-signature') ?? ''

  // Accept events signed with either the live or the test-mode webhook
  // secret — Stripe treats the two as entirely separate signing secrets
  // even when both point at this same endpoint URL. Tries live first
  // (the common case), falls back to test, and only rejects if neither
  // secret verifies the signature.
  const webhookSecrets = [
    process.env.STRIPE_WEBHOOK_SECRET,
    process.env.STRIPE_WEBHOOK_SECRET_TEST,
  ].filter(Boolean) as string[]

  let event: Stripe.Event | undefined
  let verificationError: Error | undefined
  for (const secret of webhookSecrets) {
    try {
      event = stripe.webhooks.constructEvent(body, signature, secret)
      break
    } catch (err: any) {
      verificationError = err
    }
  }
  if (!event) {
    console.error('[ATLAS] Webhook signature verification failed:', verificationError?.message)
    return NextResponse.json({ error: 'Invalid signature' }, { status: 400 })
  }

  // Use the Stripe client whose API key matches this specific event's mode —
  // a test-mode event's object IDs don't exist under the live key and vice
  // versa. Falls back to the live client if no test key is configured.
  const stripeClient = event.livemode ? stripe : (stripeTest ?? stripe)

  // Idempotency: record this event.id before running any side effects. Stripe
  // retries deliveries (and out-of-order/duplicate delivery is explicitly
  // possible), so a repeat of the same event.id must not re-send emails,
  // re-insert audit rows, or re-run an irreversible write (e.g. a second
  // entitlement revocation). Requires the stripe_webhook_events table
  // (migration 20261020000000) — if that table is missing, this fails open
  // (logs and continues) rather than silently dropping all webhook
  // processing, since a missing dedup table is an infra gap, not a reason to
  // stop honoring Stripe events.
  const { error: dedupeError } = await supabase
    .from('stripe_webhook_events')
    .insert({ id: event.id, type: event.type })
  if (dedupeError) {
    if (dedupeError.code === '23505') {
      console.log(`[ATLAS] Duplicate webhook delivery for ${event.id} (${event.type}) — skipping`)
      return NextResponse.json({ received: true, duplicate: true })
    }
    console.warn('[ATLAS] stripe_webhook_events insert failed (continuing):', dedupeError.message)
  }

  try {
    switch (event.type) {

      case 'checkout.session.completed': {
        const session = event.data.object as Stripe.Checkout.Session
        const email = session.customer_details?.email ?? session.customer_email
        if (!email) break

        if (session.mode === 'subscription' && session.subscription) {
          const sub = await stripeClient.subscriptions.retrieve(session.subscription as string)
          const priceId = sub.items.data[0]?.price.id ?? ''
          const plan = PRICE_PLAN[priceId] ?? { profile: 'atlas', subscription: 'atlas' }

          // Prefer matching by Supabase user ID (set via dynamic checkout), fall back to email
          const supabaseUserId = session.client_reference_id ?? session.metadata?.supabase_user_id
          const userId = supabaseUserId ?? await getUserByEmail(email)
          if (!userId) break

          await upsertSubscription(
            userId, sub.customer as string, sub.id,
            plan, sub.status, sub.current_period_end, sub.cancel_at_period_end
          )

          // Store billing anchor day and interval for reset logic in app
          const anchorDay = new Date(sub.current_period_start * 1000).getDate()
          const interval = sub.items.data[0]?.price.recurring?.interval ?? 'month'
          await supabase.from('profiles').update({
            billing_anchor_day: anchorDay,
            billing_interval: interval === 'year' ? 'annual' : 'monthly',
          }).eq('id', userId)

          const renewDate = sub.current_period_end
            ? new Date(sub.current_period_end * 1000).toLocaleDateString('en-US', { month: 'long', day: 'numeric', year: 'numeric' })
            : ''
          const name = session.customer_details?.name ?? email.split('@')[0]

          // User emails
          await sendEmail({ to: email, template: 'welcome', data: { name } })
          await sendEmail({ to: email, template: 'subscription-confirmed', data: { renewDate } })

          // Admin notification
          await notifyAdmin(
            `✅ New Subscriber — ${email}`,
            `${email} just subscribed to ATLAS.\n\nRenews: ${renewDate}\nStripe Customer: ${sub.customer}\nStripe Sub: ${sub.id}\nTime: ${new Date().toUTCString()}`
          )

          // Audit log
          await auditLog('subscription.created', {
            userId, email, plan: plan.profile,
            stripeEvent: event.type,
            metadata: { stripe_subscription_id: sub.id, stripe_customer_id: sub.customer, renew_date: renewDate },
          })
        }
        break
      }

      case 'customer.subscription.updated': {
        const sub = event.data.object as Stripe.Subscription
        const prevSub = event.data.previous_attributes as Partial<Stripe.Subscription> | undefined
        const priceId = sub.items.data[0]?.price.id ?? ''
        const plan = PRICE_PLAN[priceId] ?? { profile: 'standard', subscription: 'standard' }
        let customer: Stripe.Customer | Stripe.DeletedCustomer
        try { customer = await stripeClient.customers.retrieve(sub.customer as string) } catch { break }
        if (customer.deleted) break
        const email = (customer as Stripe.Customer).email
        if (!email) break
        const userId = await getUserByEmail(email)
        if (!userId) break

        await upsertSubscription(
          userId, sub.customer as string, sub.id,
          plan, sub.status, sub.current_period_end, sub.cancel_at_period_end
        )

        // Keep billing_anchor_day/billing_interval in sync with Stripe on every
        // update, not just initial checkout — a cadence switch (e.g. "Switch to
        // Annual") fires this event and previously left these fields stale.
        // Install-period math (atlas_period_start) reads these; entitlement
        // itself is untouched and still comes solely from subscriptions.status.
        {
          const anchorDay = new Date(sub.current_period_start * 1000).getDate()
          const interval = sub.items.data[0]?.price.recurring?.interval ?? 'month'
          await supabase.from('profiles').update({
            billing_anchor_day: anchorDay,
            billing_interval: interval === 'year' ? 'annual' : 'monthly',
          }).eq('id', userId)
        }

        // ATLAS policy (2026-10-20): a scheduled cancellation (cancel_at_period_end
        // === true, status still 'active') preserves access through the period the
        // customer already paid for — it does NOT revoke immediately. Access only
        // stops when Stripe's actual customer.subscription.deleted fires at period
        // end (handled below), or sooner via payment failure, which remains an
        // immediate revocation under the active-only entitlement policy. This is a
        // deliberate change from the previous immediate-revoke-on-schedule behavior;
        // log it for auditability since it affects when access is lost.
        if (sub.cancel_at_period_end && !prevSub?.cancel_at_period_end) {
          await auditLog('subscription.cancellation_scheduled', {
            userId, email, plan: plan.profile,
            stripeEvent: event.type,
            metadata: {
              stripe_subscription_id: sub.id,
              stripe_customer_id: sub.customer,
              current_period_end: sub.current_period_end,
            },
            notes: 'Access preserved until current_period_end; no immediate revocation.',
          })
        }

        // Log interval changes (monthly ↔ annual) if price changed
        const prevPriceId = (prevSub?.items as any)?.data?.[0]?.price?.id
        if (prevPriceId && prevPriceId !== priceId) {
          await auditLog('subscription.price_changed', {
            userId, email, plan: plan.profile,
            stripeEvent: event.type,
            metadata: { from_price: prevPriceId, to_price: priceId, stripe_subscription_id: sub.id },
          })
        }
        break
      }

      case 'customer.subscription.deleted': {
        const sub = event.data.object as Stripe.Subscription
        await handleCancellation(stripeClient, sub.customer as string, event.type)
        break
      }

      case 'invoice.payment_failed': {
        const invoice = event.data.object as Stripe.Invoice
        const email = invoice.customer_email
        if (!email) break
        const userId = await getUserByEmail(email)
        if (!userId) break

        await supabase
          .from('profiles')
          .update({ subscription_status: 'payment_failed' })
          .eq('id', userId)

        await supabase
          .from('subscriptions')
          .update({ status: 'past_due', updated_at: new Date().toISOString() })
          .eq('stripe_customer_id', invoice.customer as string)

        // User email
        await sendEmail({ to: email, template: 'payment-failed' })

        // Admin notification
        await notifyAdmin(
          `⚠️ Payment Failed — ${email}`,
          `Payment failed for ${email}.\n\nAmount: $${((invoice.amount_due ?? 0) / 100).toFixed(2)}\nStripe Invoice: ${invoice.id}\nTime: ${new Date().toUTCString()}`
        )

        // Audit log
        await auditLog('payment.failed', {
          userId, email,
          stripeEvent: event.type,
          metadata: { invoice_id: invoice.id, amount_due: invoice.amount_due, stripe_customer_id: invoice.customer },
        })
        break
      }

      case 'invoice.paid': {
        const invoice = event.data.object as Stripe.Invoice
        const email = invoice.customer_email
        if (!email) break
        const userId = await getUserByEmail(email)

        // Reactivate users who were in payment_failed / past_due state
        if (userId) {
          const { data: prof } = await supabase
            .from('profiles')
            .select('subscription_status, plan')
            .eq('id', userId)
            .single()

          if (prof && (prof.subscription_status === 'payment_failed' || prof.subscription_status === 'past_due')) {
            await supabase
              .from('profiles')
              .update({ subscription_status: 'active' })
              .eq('id', userId)

            await supabase
              .from('subscriptions')
              .update({ status: 'active', updated_at: new Date().toISOString() })
              .eq('stripe_customer_id', invoice.customer as string)

            await sendEmail({ to: email, template: 'subscription-confirmed', data: { renewDate: '' } })

            await notifyAdmin(
              `✅ Payment Recovered — ${email}`,
              `${email} successfully paid after a failed payment. Subscription reactivated.\n\nStripe Invoice: ${invoice.id}\nTime: ${new Date().toUTCString()}`
            )
          }
        }

        // Audit log every successful charge
        await auditLog('payment.succeeded', {
          userId, email,
          stripeEvent: event.type,
          metadata: { invoice_id: invoice.id, amount_paid: invoice.amount_paid, stripe_customer_id: invoice.customer },
          notes: `$${((invoice.amount_paid ?? 0) / 100).toFixed(2)} charged successfully`,
        })
        break
      }

      case 'charge.refunded': {
        const charge = event.data.object as Stripe.Charge
        const customerId = typeof charge.customer === 'string' ? charge.customer : charge.customer?.id
        const isFullRefund = charge.amount_refunded >= charge.amount
        const userId = customerId ? await (async () => {
          let customer: Stripe.Customer | Stripe.DeletedCustomer
          try { customer = await stripeClient.customers.retrieve(customerId) } catch { return null }
          if (customer.deleted) return null
          const email = (customer as Stripe.Customer).email
          return email ? await getUserByEmail(email) : null
        })() : null

        await auditLog(isFullRefund ? 'payment.refunded.full' : 'payment.refunded.partial', {
          userId, stripeEvent: event.type,
          metadata: {
            charge_id: charge.id,
            stripe_customer_id: customerId,
            amount: charge.amount,
            amount_refunded: charge.amount_refunded,
            currency: charge.currency,
          },
          notes: `${(charge.amount_refunded / 100).toFixed(2)} ${charge.currency.toUpperCase()} refunded of ${(charge.amount / 100).toFixed(2)}`,
        })

        // A full refund of a charge means the customer did not, in the end, pay
        // for that period — revoke access. A partial refund is a goodwill/
        // billing adjustment, not grounds on its own to revoke paid access.
        if (isFullRefund && customerId) {
          await revokeAccessForCustomer(customerId, 'full_refund', event.type, { charge_id: charge.id })
        }
        break
      }

      case 'charge.dispute.created': {
        const dispute = event.data.object as Stripe.Dispute
        const charge = typeof dispute.charge === 'string'
          ? await stripeClient.charges.retrieve(dispute.charge)
          : dispute.charge
        const customerId = typeof charge.customer === 'string' ? charge.customer : charge.customer?.id

        await auditLog('dispute.created', {
          stripeEvent: event.type,
          metadata: {
            dispute_id: dispute.id,
            charge_id: charge.id,
            stripe_customer_id: customerId,
            amount: dispute.amount,
            currency: dispute.currency,
            reason: dispute.reason,
            status: dispute.status,
          },
        })

        // Fail closed: a disputed charge must not continue to authorize paid
        // access while the dispute is open, regardless of outcome.
        if (customerId) {
          await revokeAccessForCustomer(customerId, 'dispute_opened', event.type, { dispute_id: dispute.id })
        }
        break
      }

      case 'charge.dispute.closed': {
        const dispute = event.data.object as Stripe.Dispute
        const charge = typeof dispute.charge === 'string'
          ? await stripeClient.charges.retrieve(dispute.charge)
          : dispute.charge
        const customerId = typeof charge.customer === 'string' ? charge.customer : charge.customer?.id

        // Record the outcome only. Do NOT auto-restore access on a 'won'
        // outcome — per policy, access is only re-granted after reconciling
        // the payment and current subscription state, which requires a human
        // (or a separate, deliberate reconciliation path) to confirm the
        // account should be re-activated, not an automatic webhook action.
        await auditLog('dispute.closed', {
          stripeEvent: event.type,
          metadata: {
            dispute_id: dispute.id,
            charge_id: charge.id,
            stripe_customer_id: customerId,
            status: dispute.status,
          },
          notes: `Dispute closed with status "${dispute.status}" — access NOT automatically restored; requires manual reconciliation.`,
        })

        if (customerId) {
          await notifyAdmin(
            `ℹ️ Dispute Closed (${dispute.status}) — review access manually`,
            `Dispute ${dispute.id} closed with status "${dispute.status}" for Stripe customer ${customerId}.\n\nAccess was not automatically changed. Review and restore manually if appropriate.\nTime: ${new Date().toUTCString()}`
          )
        }
        break
      }
    }
  } catch (err: any) {
    console.error('[ATLAS] Webhook handler error:', err.message)
    // Release the dedupe claim on failure — Stripe will retry a non-2xx
    // response, and that retry must be reprocessed, not silently dropped as
    // a false "duplicate" of an attempt that never actually completed.
    await supabase.from('stripe_webhook_events').delete().eq('id', event.id)
    return NextResponse.json({ error: 'Handler failed' }, { status: 500 })
  }

  return NextResponse.json({ received: true })
}
