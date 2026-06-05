import { NextRequest, NextResponse } from 'next/server'
import Stripe from 'stripe'
import { createClient } from '@supabase/supabase-js'

const stripe = new Stripe(process.env.STRIPE_SECRET_KEY!, { apiVersion: '2024-06-20' })

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
)

// Stripe price IDs → plan names
const PRICE_PLAN: Record<string, { profile: string; subscription: string }> = {
  'price_1TdIbOA1Bm2dPCGcBzQIiXGV': { profile: 'standard', subscription: 'standard' },
  'price_1TdIbOA1Bm2dPCGcpLFkuAea': { profile: 'pro',      subscription: 'pro'      },
}

async function getUserByEmail(email: string) {
  const { data } = await supabase
    .from('profiles')
    .select('id')
    .eq('email', email)
    .single()
  return data?.id ?? null
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

  // Update profiles (for ATLAS app)
  await supabase
    .from('profiles')
    .update({ plan: plan.profile, subscription_status: profileStatus })
    .eq('id', userId)

  // Upsert subscriptions (for website + cancel flow)
  await supabase
    .from('subscriptions')
    .upsert({
      user_id: userId,
      stripe_customer_id: stripeCustomerId,
      stripe_subscription_id: stripeSubscriptionId,
      plan: plan.subscription,
      status: subStatus,
      current_period_end: periodEnd
        ? new Date(periodEnd * 1000).toISOString()
        : null,
      cancel_at_period_end: cancelAtPeriodEnd,
      updated_at: new Date().toISOString(),
    }, { onConflict: 'stripe_subscription_id' })

  console.log(`[ATLAS] Updated user ${userId} → plan:${plan.profile} status:${profileStatus}`)
}

async function handleCancellation(customerId: string) {
  const customer = await stripe.customers.retrieve(customerId)
  if (customer.deleted) return
  const email = (customer as Stripe.Customer).email
  if (!email) return

  const userId = await getUserByEmail(email)
  if (!userId) return

  await supabase
    .from('profiles')
    .update({ subscription_status: 'cancelled' })
    .eq('id', userId)

  await supabase
    .from('subscriptions')
    .update({ status: 'canceled', updated_at: new Date().toISOString() })
    .eq('stripe_customer_id', customerId)

  console.log(`[ATLAS] Cancelled subscription for ${email}`)
}

export async function POST(req: NextRequest) {
  const body = await req.text()
  const signature = req.headers.get('stripe-signature') ?? ''

  let event: Stripe.Event
  try {
    event = stripe.webhooks.constructEvent(body, signature, process.env.STRIPE_WEBHOOK_SECRET!)
  } catch (err: any) {
    console.error('[ATLAS] Webhook signature failed:', err.message)
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
          const userId = await getUserByEmail(email)
          if (!userId) break

          await upsertSubscription(
            userId,
            sub.customer as string,
            sub.id,
            plan,
            sub.status,
            sub.current_period_end,
            sub.cancel_at_period_end
          )
        }
        break
      }

      case 'customer.subscription.updated': {
        const sub = event.data.object as Stripe.Subscription
        const priceId = sub.items.data[0]?.price.id ?? ''
        const plan = PRICE_PLAN[priceId] ?? { profile: 'standard', subscription: 'standard' }
        const customer = await stripe.customers.retrieve(sub.customer as string)
        if (customer.deleted) break
        const email = (customer as Stripe.Customer).email
        if (!email) break
        const userId = await getUserByEmail(email)
        if (!userId) break

        await upsertSubscription(
          userId,
          sub.customer as string,
          sub.id,
          plan,
          sub.status,
          sub.current_period_end,
          sub.cancel_at_period_end
        )
        break
      }

      case 'customer.subscription.deleted': {
        const sub = event.data.object as Stripe.Subscription
        await handleCancellation(sub.customer as string)
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
        break
      }
    }
  } catch (err: any) {
    console.error('[ATLAS] Webhook handler error:', err.message)
    return NextResponse.json({ error: 'Handler failed' }, { status: 500 })
  }

  return NextResponse.json({ received: true })
}
