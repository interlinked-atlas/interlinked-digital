import { NextRequest, NextResponse } from 'next/server'
import Stripe from 'stripe'
import { createClient } from '@supabase/supabase-js'

const stripe = new Stripe(process.env.STRIPE_SECRET_KEY!, {
  apiVersion: '2024-06-20',
})

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
)

// Map Stripe price IDs to plan identifiers
// sub_plan: used in subscriptions table (schema allows 'basic' | 'pro')
// profile_plan: used in profiles table ('standard' | 'pro')
const PRICE_MAP: Record<string, { sub_plan: 'basic' | 'pro'; profile_plan: string }> = {
  'price_1TdIbOA1Bm2dPCGcBzQIiXGV': { sub_plan: 'basic', profile_plan: 'standard' },
  'price_1TdIbOA1Bm2dPCGcpLFkuAea': { sub_plan: 'pro',   profile_plan: 'pro'      },
}

export const config = { api: { bodyParser: false } }

async function getUserIdByEmail(email: string): Promise<string | null> {
  const { data } = await supabase
    .from('profiles')
    .select('id')
    .eq('email', email)
    .single()
  return data?.id ?? null
}

async function updateProfile(email: string, profilePlan: string, status: string) {
  const { error } = await supabase
    .from('profiles')
    .update({ plan: profilePlan, subscription_status: status })
    .eq('email', email)
  if (error) {
    console.error(`[webhook] profiles update failed for ${email}:`, error.message)
    throw error
  }
}

async function upsertSubscription(
  userId: string,
  stripeCustomerId: string,
  stripeSubscriptionId: string,
  subPlan: 'basic' | 'pro',
  status: string,
  periodStart: number | null,
  periodEnd: number | null,
  cancelAtPeriodEnd: boolean,
) {
  const { error } = await supabase
    .from('subscriptions')
    .upsert(
      {
        user_id: userId,
        stripe_customer_id: stripeCustomerId,
        stripe_subscription_id: stripeSubscriptionId,
        plan: subPlan,
        status,
        current_period_start: periodStart ? new Date(periodStart * 1000).toISOString() : null,
        current_period_end:   periodEnd   ? new Date(periodEnd   * 1000).toISOString() : null,
        cancel_at_period_end: cancelAtPeriodEnd,
        updated_at: new Date().toISOString(),
      },
      { onConflict: 'stripe_subscription_id' }
    )
  if (error) {
    console.error(`[webhook] subscriptions upsert failed for user ${userId}:`, error.message)
    throw error
  }
}

export async function POST(req: NextRequest) {
  const body = await req.text()
  const signature = req.headers.get('stripe-signature') ?? ''

  let event: Stripe.Event
  try {
    event = stripe.webhooks.constructEvent(body, signature, process.env.STRIPE_WEBHOOK_SECRET!)
  } catch (err: any) {
    console.error('[webhook] signature failed:', err.message)
    return NextResponse.json({ error: 'Invalid signature' }, { status: 400 })
  }

  try {
    switch (event.type) {

      case 'checkout.session.completed': {
        const session = event.data.object as Stripe.Checkout.Session
        const email = session.customer_details?.email ?? session.customer_email
        if (!email || session.mode !== 'subscription' || !session.subscription) break

        const stripeSub = await stripe.subscriptions.retrieve(session.subscription as string)
        const priceId = stripeSub.items.data[0]?.price.id ?? ''
        const map = PRICE_MAP[priceId] ?? { sub_plan: 'basic' as const, profile_plan: 'standard' }

        await updateProfile(email, map.profile_plan, 'active')

        const userId = await getUserIdByEmail(email)
        if (userId) {
          await upsertSubscription(
            userId,
            session.customer as string,
            stripeSub.id,
            map.sub_plan,
            'active',
            stripeSub.current_period_start,
            stripeSub.current_period_end,
            stripeSub.cancel_at_period_end,
          )
        } else {
          console.error(`[webhook] no user found for email: ${email}`)
        }
        console.log(`[webhook] checkout.session.completed -> ${email} ${map.profile_plan}`)
        break
      }

      case 'customer.subscription.updated': {
        const stripeSub = event.data.object as Stripe.Subscription
        const priceId = stripeSub.items.data[0]?.price.id ?? ''
        const map = PRICE_MAP[priceId] ?? { sub_plan: 'basic' as const, profile_plan: 'standard' }
        const status = stripeSub.status === 'active' ? 'active' : stripeSub.status

        const customer = await stripe.customers.retrieve(stripeSub.customer as string)
        if (customer.deleted) break
        const email = (customer as Stripe.Customer).email
        if (!email) break

        await updateProfile(email, map.profile_plan, status)

        const userId = await getUserIdByEmail(email)
        if (userId) {
          await upsertSubscription(
            userId,
            stripeSub.customer as string,
            stripeSub.id,
            map.sub_plan,
            status,
            stripeSub.current_period_start,
            stripeSub.current_period_end,
            stripeSub.cancel_at_period_end,
          )
        }
        console.log(`[webhook] subscription.updated -> ${email} ${map.profile_plan} (${status})`)
        break
      }

      case 'customer.subscription.deleted': {
        const stripeSub = event.data.object as Stripe.Subscription

        const customer = await stripe.customers.retrieve(stripeSub.customer as string)
        if (customer.deleted) break
        const email = (customer as Stripe.Customer).email
        if (!email) break

        await updateProfile(email, 'standard', 'cancelled')

        const { error } = await supabase
          .from('subscriptions')
          .update({ status: 'canceled', updated_at: new Date().toISOString() })
          .eq('stripe_subscription_id', stripeSub.id)
        if (error) console.error('[webhook] cancel update failed:', error.message)

        console.log(`[webhook] subscription.deleted -> ${email} cancelled`)
        break
      }

      case 'invoice.payment_failed': {
        const invoice = event.data.object as Stripe.Invoice
        const email = invoice.customer_email
        if (!email) break

        await updateProfile(email, 'standard', 'payment_failed')

        if (invoice.subscription) {
          const { error } = await supabase
            .from('subscriptions')
            .update({ status: 'past_due', updated_at: new Date().toISOString() })
            .eq('stripe_subscription_id', invoice.subscription as string)
          if (error) console.error('[webhook] past_due update failed:', error.message)
        }
        console.log(`[webhook] invoice.payment_failed -> ${email}`)
        break
      }

      default:
        break
    }
  } catch (err: any) {
    console.error('[webhook] handler error:', err.message)
    return NextResponse.json({ error: 'Handler failed' }, { status: 500 })
  }

  return NextResponse.json({ received: true })
}
