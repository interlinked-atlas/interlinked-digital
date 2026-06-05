import { NextRequest, NextResponse } from 'next/server'
import Stripe from 'stripe'
import { createClient } from '@supabase/supabase-js'

const stripe = new Stripe(process.env.STRIPE_SECRET_KEY!, { apiVersion: '2024-06-20' })

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
)

const PRO_PRICE_ID = 'price_1TdIbOA1Bm2dPCGcpLFkuAea' // $29.99/mo

export async function POST(req: NextRequest) {
  const token = req.headers.get('authorization')?.replace('Bearer ', '').trim()
  if (!token) return NextResponse.json({ error: 'Missing authorization' }, { status: 401 })

  const { data: { user }, error: authError } = await supabase.auth.getUser(token)
  if (authError || !user) return NextResponse.json({ error: 'Invalid token' }, { status: 401 })

  const { data: profile } = await supabase
    .from('profiles').select('email, plan').eq('id', user.id).single()

  if (!profile?.email) return NextResponse.json({ error: 'Profile not found' }, { status: 404 })
  if (profile.plan === 'pro') return NextResponse.json({ ok: true, alreadyPro: true })

  const customers = await stripe.customers.list({ email: profile.email, limit: 1 })
  const customer = customers.data[0]
  if (!customer) return NextResponse.json({ error: 'No Stripe customer found' }, { status: 404 })

  // Get active subscription
  const subs = await stripe.subscriptions.list({ customer: customer.id, status: 'active', limit: 1 })
  const sub = subs.data[0]
  if (!sub) return NextResponse.json({ error: 'No active subscription to upgrade' }, { status: 404 })

  // Swap the price to Pro — prorated immediately
  const item = sub.items.data[0]
  await stripe.subscriptions.update(sub.id, {
    items: [{ id: item.id, price: PRO_PRICE_ID }],
    proration_behavior: 'always_invoice',
  })

  // Update Supabase profile immediately
  await supabase.from('profiles')
    .update({ plan: 'pro', subscription_status: 'active' })
    .eq('id', user.id)

  // Update subscriptions table
  await supabase.from('subscriptions').upsert({
    user_id: user.id,
    stripe_customer_id: customer.id,
    stripe_subscription_id: sub.id,
    plan: 'pro',
    status: 'active',
    updated_at: new Date().toISOString(),
  }, { onConflict: 'user_id' })

  return NextResponse.json({ ok: true })
}
