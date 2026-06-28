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

  const { data: profile, error: profileError } = await supabase
    .from('profiles')
    .select('email')
    .eq('id', user.id)
    .single()

  if (profileError || !profile?.email) {
    return NextResponse.json({ error: 'Profile not found' }, { status: 404 })
  }

  const customers = await stripe.customers.list({ email: profile.email, limit: 1 })
  const customer = customers.data[0]
  if (!customer) {
    return NextResponse.json({ error: 'No Stripe customer found' }, { status: 404 })
  }

  const subscriptions = await stripe.subscriptions.list({
    customer: customer.id,
    status: 'active',
    limit: 1,
  })
  const sub = subscriptions.data[0]
  if (!sub) {
    return NextResponse.json({ error: 'No active subscription' }, { status: 404 })
  }

  // Cancel immediately — no remaining access, no free days
  await stripe.subscriptions.cancel(sub.id)

  await supabase
    .from('profiles')
    .update({ subscription_status: 'cancelled', plan: 'free' })
    .eq('id', user.id)

  await supabase
    .from('subscriptions')
    .update({ status: 'canceled', updated_at: new Date().toISOString() })
    .eq('stripe_customer_id', customer.id)

  // Cancellation email sent by Stripe webhook (customer.subscription.deleted) — not here, to avoid duplicates

  return NextResponse.json({ ok: true })
}
