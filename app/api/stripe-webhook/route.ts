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

const PRICE_PLAN: Record<string, string> = {
  'price_1TdIbOA1Bm2dPCGcBzQIiXGV': 'standard',
  'price_1TdIbOA1Bm2dPCGcpLFkuAea': 'pro',
}

export const config = { api: { bodyParser: false } }

async function updateProfileByEmail(email: string, plan: string, status: string) {
  const { error } = await supabase
    .from('profiles')
    .update({ plan, subscription_status: status })
    .eq('email', email)
  if (error) {
    console.error(`[ATLAS] profiles update failed for ${email}:`, error.message)
    throw error
  }
  console.log(`[ATLAS] profiles → ${email}: plan=${plan}, status=${status}`)
}

async function upsertSubscription(email: string, sub: Stripe.Subscription) {
  const { data: profile } = await supabase
    .from('profiles')
    .select('id')
    .eq('email', email)
    .maybeSingle()

  if (!profile?.id) {
    console.warn(`[ATLAS] No profile found for ${email} — skipping subscriptions upsert`)
    return
  }

  const priceId = sub.items.data[0]?.price.id ?? ''
  const plan    = PRICE_PLAN[priceId] ?? 'standard'

  const { error } = await supabase.from('subscriptions').upsert({
    user_id:                profile.id,
    stripe_customer_id:     sub.customer as string,
    stripe_subscription_id: sub.id,
    plan,
    status:                 sub.status,
    current_period_start:   new Date(sub.current_period_start * 1000).toISOString(),
    current_period_end:     new Date(sub.current_period_end   * 1000).toISOString(),
    cancel_at_period_end:   sub.cancel_at_period_end,
    updated_at:             new Date().toISOString(),
  }, { onConflict: 'user_id' })

  if (error) console.error(`[ATLAS] subscriptions upsert failed for ${email}:`, error.message)
  else console.log(`[ATLAS] subscriptions → ${email}: plan=${plan}`)
}

export async function POST(req: NextRequest) {
  const body      = await req.text()
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
        const email   = session.customer_details?.email ?? session.customer_email
        if (!email) break
        if (session.mode === 'subscription' && session.subscription) {
          const sub = await stripe.subscriptions.retrieve(session.subscription as string)
          const priceId = sub.items.data[0]?.price.id ?? ''
          const plan    = PRICE_PLAN[priceId] ?? 'standard'
          await updateProfileByEmail(email, plan, 'active')
          await upsertSubscription(email, sub)
        }
        break
      }

      case 'customer.subscription.deleted': {
        const sub      = event.data.object as Stripe.Subscription
        const customer = await stripe.customers.retrieve(sub.customer as string)
        if (customer.deleted) break
        const email = (customer as Stripe.Customer).email
        if (!email) break
        await updateProfileByEmail(email, 'standard', 'cancelled')
        await upsertSubscription(email, sub)
        break
      }

      case 'customer.subscription.updated': {
        const sub      = event.data.object as Stripe.Subscription
        const customer = await stripe.customers.retrieve(sub.customer as string)
        if (customer.deleted) break
        const email = (customer as Stripe.Customer).email
        if (!email) break
        const priceId = sub.items.data[0]?.price.id ?? ''
        const plan    = PRICE_PLAN[priceId] ?? 'standard'
        const status  = sub.status === 'active' ? 'active' : sub.status
        await updateProfileByEmail(email, plan, status)
        await upsertSubscription(email, sub)
        break
      }

      case 'invoice.payment_failed': {
        const invoice = event.data.object as Stripe.Invoice
        const email   = invoice.customer_email
        if (email) await updateProfileByEmail(email, 'standard', 'payment_failed')
        break
      }

      default:
        break
    }
  } catch (err: any) {
    console.error('[ATLAS] Webhook handler error:', err.message)
    return NextResponse.json({ error: 'Handler failed' }, { status: 500 })
  }

  return NextResponse.json({ received: true })
}
