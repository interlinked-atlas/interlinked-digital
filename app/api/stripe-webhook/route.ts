import { NextRequest, NextResponse } from 'next/server'
import Stripe from 'stripe'
import { createClient } from '@supabase/supabase-js'

const stripe = new Stripe(process.env.STRIPE_SECRET_KEY!, {
  apiVersion: '2024-06-20',
})

// Service-role client — bypasses RLS, server-side only, never expose to browser
const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
)

// Map Stripe price IDs → ATLAS plan names
const PRICE_PLAN: Record<string, string> = {
  'price_1TdIbOA1Bm2dPCGcBzQIiXGV': 'standard', // $14.99/mo
  'price_1TdIbOA1Bm2dPCGcpLFkuAea': 'pro',       // $29.99/mo
}

// Disable Next.js body parsing — Stripe needs the raw body to verify the signature
export const config = { api: { bodyParser: false } }

async function updatePlan(email: string, plan: string, status: string) {
  const { error } = await supabase
    .from('profiles')
    .update({ plan, subscription_status: status })
    .eq('email', email)

  if (error) {
    console.error(`[ATLAS] Failed to update plan for ${email}:`, error.message)
    throw error
  }
  console.log(`[ATLAS] Updated ${email} → plan: ${plan}, status: ${status}`)
}

export async function POST(req: NextRequest) {
  const body = await req.text()
  const signature = req.headers.get('stripe-signature') ?? ''

  // 1. Verify the request actually came from Stripe
  let event: Stripe.Event
  try {
    event = stripe.webhooks.constructEvent(
      body,
      signature,
      process.env.STRIPE_WEBHOOK_SECRET!
    )
  } catch (err: any) {
    console.error('[ATLAS] Webhook signature failed:', err.message)
    return NextResponse.json({ error: 'Invalid signature' }, { status: 400 })
  }

  // 2. Handle events
  try {
    switch (event.type) {

      // ── Payment completed (subscription starts) ──────────────────────────
      case 'checkout.session.completed': {
        const session = event.data.object as Stripe.Checkout.Session
        const email = session.customer_details?.email ?? session.customer_email
        if (!email) break

        if (session.mode === 'subscription' && session.subscription) {
          const sub = await stripe.subscriptions.retrieve(
            session.subscription as string
          )
          const priceId = sub.items.data[0]?.price.id ?? ''
          const plan = PRICE_PLAN[priceId] ?? 'standard'
          await updatePlan(email, plan, 'active')
        }
        break
      }

      // ── Subscription cancelled ────────────────────────────────────────────
      case 'customer.subscription.deleted': {
        const sub = event.data.object as Stripe.Subscription
        const customer = await stripe.customers.retrieve(sub.customer as string)
        if (customer.deleted) break
        const email = (customer as Stripe.Customer).email
        if (email) await updatePlan(email, 'standard', 'cancelled')
        break
      }

      // ── Subscription changed (upgrade / downgrade / reactivation) ─────────
      case 'customer.subscription.updated': {
        const sub = event.data.object as Stripe.Subscription
        const priceId = sub.items.data[0]?.price.id ?? ''
        const plan = PRICE_PLAN[priceId] ?? 'standard'
        const status = sub.status === 'active' ? 'active' : sub.status
        const customer = await stripe.customers.retrieve(sub.customer as string)
        if (customer.deleted) break
        const email = (customer as Stripe.Customer).email
        if (email) await updatePlan(email, plan, status)
        break
      }

      // ── Payment failed (card declined, expired, etc.) ─────────────────────
      case 'invoice.payment_failed': {
        const invoice = event.data.object as Stripe.Invoice
        const email = invoice.customer_email
        if (email) await updatePlan(email, 'standard', 'payment_failed')
        break
      }

      default:
        // Unhandled event — ignore silently
        break
    }
  } catch (err: any) {
    console.error('[ATLAS] Webhook handler error:', err.message)
    return NextResponse.json({ error: 'Handler failed' }, { status: 500 })
  }

  return NextResponse.json({ received: true })
}
