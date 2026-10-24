import { NextRequest, NextResponse } from 'next/server'
import Stripe from 'stripe'
import { createClient } from '@supabase/supabase-js'
import { sendEmail } from '@/lib/email'
import { isAlreadyCancelledStatus, computeEffectiveEntitlement } from '@/lib/billingStatus'

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
  // 'cancelled' (British) to match handleCancellation/revokeAccessForCustomer's
  // spelling for this exact column — previously this wrote Stripe's raw
  // 'canceled' (American) status string here, which those functions' own
  // idempotency guards didn't recognize, causing duplicate cancellation
  // emails/audit rows when a .updated(status: canceled) event was followed
  // by the matching .deleted event. subscriptions.status is unaffected and
  // intentionally still uses Stripe's own spelling ('canceled') below, since
  // nothing else's guard logic depends on that column's exact string.
  //
  // ATLAS policy (2026-10-23, supersedes the 2026-10-20 note this replaces):
  // cancel_at_period_end === true revokes ATLAS access immediately, not at
  // current_period_end. Stripe's own `status` stays 'active' throughout that
  // window (Stripe itself only flips status at period end / on
  // subscription.deleted) — so entitlement here is computed from BOTH
  // fields, not status alone. This is a pure function of each event's own
  // fields: a later event reporting cancelAtPeriodEnd === false (the
  // customer reversed the cancellation) naturally recomputes 'active' again
  // with no separate reversal branch needed, and no risk of permanently
  // revoking access past a reversal.
  const { profileStatus, subStatus } = computeEffectiveEntitlement(status, cancelAtPeriodEnd)

  const { error: profileErr } = await supabase
    .from('profiles')
    .update({ plan: plan.profile, subscription_status: profileStatus })
    .eq('id', userId)
  if (profileErr) console.error('[ATLAS] Profile update failed:', profileErr.message)

  // Atomic upsert keyed on the subscriptions_user_id_key unique constraint
  // (supabase/migrations/20261022000000_subscriptions_user_id_unique.sql).
  // A single INSERT ... ON CONFLICT (user_id) DO UPDATE is one statement, so
  // two concurrent webhook deliveries for the same new subscriber can no
  // longer both pass a stale "does a row exist" check and insert duplicate
  // rows — Postgres resolves the race against the constraint itself. This
  // requires that migration to be applied before this code path is live.
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

  const { error: upsertErr } = await supabase
    .from('subscriptions')
    .upsert(subPayload, { onConflict: 'user_id' })
  if (upsertErr) console.error('[ATLAS] Subscription upsert failed:', upsertErr.message)

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
  // Checks both spellings: upsertSubscription() can write the raw Stripe
  // status string ('canceled', American) to this same column, while this
  // function and revokeAccessForCustomer() write 'cancelled' (British) — a
  // real, confirmed mismatch that let a .updated event (status: 'canceled')
  // followed by the matching .deleted event re-send the cancellation email
  // and audit row, since the guard only recognized one spelling.
  const { data: currentProfile } = await supabase
    .from('profiles')
    .select('subscription_status')
    .eq('id', userId)
    .single()
  if (isAlreadyCancelledStatus(currentProfile?.subscription_status)) {
    console.log(`[ATLAS] handleCancellation: already cancelled for ${email} — skipping`)
    return
  }

  // Both writes happen inside one Postgres function/transaction — either
  // both land or neither does, so a crash between them can never leave
  // profiles and subscriptions disagreeing about entitlement.
  const { error: rpcErr } = await supabase.rpc('atlas_set_entitlement_status', {
    p_user_id: userId,
    p_stripe_customer_id: customerId,
    p_profile_status: 'cancelled',
    p_plan: 'free',
    p_sub_status: 'canceled',
  })
  if (rpcErr) throw new Error(`atlas_set_entitlement_status failed: ${rpcErr.message}`)

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
  // Same both-spellings guard as handleCancellation above.
  if (isAlreadyCancelledStatus(currentProfile?.subscription_status)) {
    console.log(`[ATLAS] revokeAccessForCustomer(${reason}): already non-active for ${email} — skipping`)
    return
  }

  // Same atomic pairing as handleCancellation — see its comment.
  const { error: rpcErr } = await supabase.rpc('atlas_set_entitlement_status', {
    p_user_id: userId,
    p_stripe_customer_id: customerId,
    p_profile_status: 'cancelled',
    p_plan: 'free',
    p_sub_status: 'canceled',
  })
  if (rpcErr) throw new Error(`atlas_set_entitlement_status failed: ${rpcErr.message}`)

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

  // Idempotency + concurrency ownership. Fails CLOSED: if the claim RPC
  // itself cannot be reached or errors (e.g. migration 20261021000000 isn't
  // applied yet, or any other RPC-level failure), this request has no
  // confirmed ownership of the event and must not run any billing,
  // entitlement, email, or audit side effect. Returning a 500 here causes
  // Stripe to retry — once the RPC is actually available, that retry
  // reprocesses normally. This is a deliberate reversal of an earlier
  // fail-open design (log-and-continue on claim failure), which allowed
  // exactly the side effects this function exists to prevent.
  //
  // Three explicit outcomes from the atomic RPC on success — see its
  // definition for the full ownership/liveness reasoning:
  //   'claimed'            — this request owns the event; run the handler.
  //   'already_processing' — a concurrent/near-concurrent delivery already
  //                           owns this event and is still within its
  //                           liveness window. This request is the losing
  //                           side of a real race and MUST NOT run any
  //                           billing/email/audit side effect — return
  //                           immediately, exactly like a true duplicate.
  //   'already_succeeded'  — fully done already; return immediately.
  // The side effects (email/admin notify) remain NOT perfectly exactly-once
  // across a crash-then-retry sequence (a crash after the state writes but
  // before the 'succeeded' marker can cause one repeat email on the next
  // retry) — that specific, narrower case is a known, accepted limitation;
  // what this resolves is genuine concurrent/near-concurrent delivery, which
  // can no longer run the handler twice at all.
  const { data: claimResult, error: claimErr } = await supabase.rpc('atlas_claim_webhook_event', {
    p_id: event.id,
    p_type: event.type,
  })

  if (claimErr) {
    console.error('[ATLAS] atlas_claim_webhook_event failed — refusing to process without confirmed ownership:', claimErr.message)
    return NextResponse.json({ error: 'Claim failed' }, { status: 500 })
  }
  if (claimResult === 'already_succeeded' || claimResult === 'already_processing') {
    console.log(`[ATLAS] Not processing ${event.id} (${event.type}) — ${claimResult}`)
    return NextResponse.json({ received: true, duplicate: true })
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

        // ATLAS policy (2026-10-23): scheduling a cancellation
        // (cancel_at_period_end: true) revokes ATLAS access immediately —
        // upsertSubscription() above already wrote profiles/subscriptions to
        // a non-active state for this event, regardless of Stripe's own
        // status still reading 'active'. This supersedes the 2026-10-20
        // paid-period-access decision. Logged for auditability since it's a
        // real access-affecting transition, not merely a metadata change.
        if (sub.cancel_at_period_end && !prevSub?.cancel_at_period_end) {
          await auditLog('subscription.cancellation_scheduled', {
            userId, email, plan: plan.profile,
            stripeEvent: event.type,
            metadata: {
              stripe_subscription_id: sub.id,
              stripe_customer_id: sub.customer,
              current_period_end: sub.current_period_end,
            },
            notes: 'ATLAS access revoked immediately; Stripe subscription remains active (billed) until current_period_end unless separately cancelled there.',
          })
        }

        // Reversal: the customer undid a scheduled cancellation before it took
        // effect. upsertSubscription() above already recomputed 'active' from
        // this event's own cancel_at_period_end/status fields — nothing further
        // needed for entitlement. Logged only for auditability.
        if (!sub.cancel_at_period_end && prevSub?.cancel_at_period_end) {
          await auditLog('subscription.cancellation_reversed', {
            userId, email, plan: plan.profile,
            stripeEvent: event.type,
            metadata: { stripe_subscription_id: sub.id, stripe_customer_id: sub.customer },
            notes: 'ATLAS access restored immediately.',
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

        const { data: failedProf } = await supabase
          .from('profiles')
          .select('plan')
          .eq('id', userId)
          .single()

        const { error: failedRpcErr } = await supabase.rpc('atlas_set_entitlement_status', {
          p_user_id: userId,
          p_stripe_customer_id: invoice.customer as string,
          p_profile_status: 'payment_failed',
          p_plan: failedProf?.plan ?? 'free',
          p_sub_status: 'past_due',
        })
        if (failedRpcErr) throw new Error(`atlas_set_entitlement_status failed: ${failedRpcErr.message}`)

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
            const { error: recoveredRpcErr } = await supabase.rpc('atlas_set_entitlement_status', {
              p_user_id: userId,
              p_stripe_customer_id: invoice.customer as string,
              p_profile_status: 'active',
              p_plan: prof.plan ?? 'free',
              p_sub_status: 'active',
            })
            if (recoveredRpcErr) throw new Error(`atlas_set_entitlement_status failed: ${recoveredRpcErr.message}`)

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
    // Mark 'failed', not deleted — Stripe will retry a non-2xx response, and
    // that retry must be reprocessed (a 'failed' row is not treated as a
    // duplicate above), while still leaving a permanent record that this
    // event was attempted and did not cleanly succeed.
    await supabase.from('stripe_webhook_events').update({ status: 'failed' }).eq('id', event.id)
    return NextResponse.json({ error: 'Handler failed' }, { status: 500 })
  }

  // Only now — after every side effect for this event has run — is the event
  // marked fully done. This is the single source of truth a duplicate
  // delivery is checked against above.
  await supabase
    .from('stripe_webhook_events')
    .update({ status: 'succeeded', completed_at: new Date().toISOString() })
    .eq('id', event.id)

  return NextResponse.json({ received: true })
}
