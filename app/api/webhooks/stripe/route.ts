import { NextRequest, NextResponse } from 'next/server'
import Stripe from 'stripe'
import { createClient } from '@supabase/supabase-js'
import { sendEmail } from '@/lib/email'

const stripe = new Stripe(process.env.STRIPE_SECRET_KEY!, { apiVersion: '2025-04-30.basil' })

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
)

const ADMIN_EMAIL = 'interlinked.digital@gmail.com'

const PRICE_PLAN: Record<string, { profile: string; subscription: string }> = {
  // LIVE — monthly
  'price_1TdIbOA1Bm2dPCGcBzQIiXGV': { profile: 'standard', subscription: 'standard' },
  'price_1TdIbOA1Bm2dPCGcpLFkuAea': { profile: 'pro',      subscription: 'pro'      },
  // LIVE — annual
  'price_1TnTWwA1Bm2dPCGchzhfeeZy': { profile: 'standard', subscription: 'standard' },
  'price_1TnTXWA1Bm2dPCGcPInuLsUt': { profile: 'pro',      subscription: 'pro'      },
  // TEST MODE
  'price_1TliuWA1Bm2dPCGcbpXH9hE5': { profile: 'standard', subscription: 'standard' },
  'price_1TlitLA1Bm2dPCGcZRFxm68J': { profile: 'pro',      subscription: 'pro'      },
  'price_1TqJSEA1Bm2dPCGcEtL4Au0e': { profile: 'pro',      subscription: 'pro'      }, // $0.50 flow test
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

  await supabase
    .from('profiles')
    .update({ plan: plan.profile, subscription_status: profileStatus })
    .eq('id', userId)

  await supabase
    .from('subscriptions')
    .upsert({
      user_id: userId,
      stripe_customer_id: stripeCustomerId,
      stripe_subscription_id: stripeSubscriptionId,
      plan: plan.subscription,
      status: subStatus,
      current_period_end: periodEnd ? new Date(periodEnd * 1000).toISOString() : null,
      cancel_at_period_end: cancelAtPeriodEnd,
      updated_at: new Date().toISOString(),
    }, { onConflict: 'stripe_subscription_id' })

  console.log(`[ATLAS] Updated user ${userId} → plan:${plan.profile} status:${profileStatus}`)
}

async function handleCancellation(customerId: string, stripeEvent: string) {
  const customer = await stripe.customers.retrieve(customerId)
  if (customer.deleted) return
  const email = (customer as Stripe.Customer).email
  if (!email) return

  const userId = await getUserByEmail(email)
  if (!userId) return

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

export async function POST(req: NextRequest) {
  const body = await req.text()
  const signature = req.headers.get('stripe-signature') ?? ''

  let event: Stripe.Event
  const secrets = [
    process.env.STRIPE_WEBHOOK_SECRET,
    process.env.STRIPE_WEBHOOK_SECRET_TEST,
  ].filter(Boolean) as string[]

  let verified = false
  for (const secret of secrets) {
    try {
      event = stripe.webhooks.constructEvent(body, signature, secret)
      verified = true
      break
    } catch {}
  }
  if (!verified) {
    console.error('[ATLAS] Webhook signature failed against all known secrets')
    return NextResponse.json({ error: 'Invalid signature' }, { status: 400 })
  }

  try {
    switch (event.type) {

      case 'checkout.session.completed': {
        const session = event.data.object as Stripe.Checkout.Session
        const email = session.customer_details?.email ?? session.customer_email
        if (!email) break

        if (session.mode === 'subscription' && session.subscription) {
          const sub = await stripe.subscriptions.retrieve(session.subscription as string)
          const priceId = sub.items.data[0]?.price.id ?? ''
          const plan = PRICE_PLAN[priceId] ?? { profile: 'standard', subscription: 'standard' }

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
          await sendEmail({ to: email, template: 'subscription-confirmed', data: { plan: plan.profile, renewDate } })

          // Admin notification
          await notifyAdmin(
            `✅ New Subscriber — ${email}`,
            `${email} just subscribed to ATLAS ${plan.profile.toUpperCase()}.\n\nRenews: ${renewDate}\nStripe Customer: ${sub.customer}\nStripe Sub: ${sub.id}\nTime: ${new Date().toUTCString()}`
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
        try { customer = await stripe.customers.retrieve(sub.customer as string) } catch { break }
        if (customer.deleted) break
        const email = (customer as Stripe.Customer).email
        if (!email) break
        const userId = await getUserByEmail(email)
        if (!userId) break

        await upsertSubscription(
          userId, sub.customer as string, sub.id,
          plan, sub.status, sub.current_period_end, sub.cancel_at_period_end
        )

        // Only log/notify if the plan price actually changed
        const prevPriceId = (prevSub?.items as any)?.data?.[0]?.price?.id
        const prevPlan = prevPriceId ? PRICE_PLAN[prevPriceId]?.profile : null
        if (prevPlan && prevPlan !== plan.profile) {
          const direction = plan.profile === 'pro' ? '⬆️ Upgraded' : '⬇️ Downgraded'

          // Email user their new plan confirmation
          const renewDate = sub.current_period_end
            ? new Date(sub.current_period_end * 1000).toLocaleDateString('en-US', { month: 'long', day: 'numeric', year: 'numeric' })
            : ''
          await sendEmail({ to: email, template: 'subscription-confirmed', data: { plan: plan.profile, renewDate } })

          await notifyAdmin(
            `${direction} — ${email}`,
            `${email} changed plan: ${prevPlan.toUpperCase()} → ${plan.profile.toUpperCase()}.\n\nStripe Sub: ${sub.id}\nTime: ${new Date().toUTCString()}`
          )
          await auditLog('subscription.plan_changed', {
            userId, email, plan: plan.profile,
            stripeEvent: event.type,
            metadata: { from_plan: prevPlan, to_plan: plan.profile, stripe_subscription_id: sub.id },
          })
        }
        break
      }

      case 'customer.subscription.deleted': {
        const sub = event.data.object as Stripe.Subscription
        await handleCancellation(sub.customer as string, event.type)
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

        // Audit log every successful charge
        await auditLog('payment.succeeded', {
          userId, email,
          stripeEvent: event.type,
          metadata: { invoice_id: invoice.id, amount_paid: invoice.amount_paid, stripe_customer_id: invoice.customer },
          notes: `$${((invoice.amount_paid ?? 0) / 100).toFixed(2)} charged successfully`,
        })
        break
      }
    }
  } catch (err: any) {
    console.error('[ATLAS] Webhook handler error:', err.message)
    return NextResponse.json({ error: 'Handler failed' }, { status: 500 })
  }

  return NextResponse.json({ received: true })
}
