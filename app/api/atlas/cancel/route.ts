import { NextRequest, NextResponse } from 'next/server'
import Stripe from 'stripe'
import { createClient } from '@supabase/supabase-js'

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

  await stripe.subscriptions.cancel(stripeSubId)

  await supabase
    .from('profiles')
    .update({ subscription_status: 'cancelled', plan: 'free' })
    .eq('id', user.id)

  await supabase
    .from('subscriptions')
    .update({ status: 'canceled', updated_at: new Date().toISOString() })
    .eq('stripe_customer_id', customerId)

  // Cancellation email sent by Stripe webhook (customer.subscription.deleted) — not here, to avoid duplicates

  return NextResponse.json({ ok: true })
}
