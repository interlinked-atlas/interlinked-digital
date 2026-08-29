import { NextRequest, NextResponse } from 'next/server'
import Stripe from 'stripe'
import { createClient } from '@supabase/supabase-js'
import { sendEmail } from '@/lib/email'

const stripe = new Stripe(process.env.STRIPE_SECRET_KEY!, { apiVersion: '2025-04-30.basil' })

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
)

const PRICE_IDS: Record<string, string> = {
  // Current ATLAS single plan
  'atlas':           'price_1U9uOBA1Bm2dPCGc73d3ZbA5',
  'atlas-annual':    'price_1U9uOCA1Bm2dPCGcjRbOpXii',
  // Legacy prices — kept for backward compat, all map to ATLAS tier
  standard:          'price_1TdIbOA1Bm2dPCGcBzQIiXGV',
  pro:               'price_1TdIbOA1Bm2dPCGcpLFkuAea',
  'standard-annual': 'price_1TnTWwA1Bm2dPCGchzhfeeZy',
  'pro-annual':      'price_1TnTXWA1Bm2dPCGcPInuLsUt',
}

export async function POST(req: NextRequest) {
  const token = req.headers.get('authorization')?.replace('Bearer ', '').trim()
  if (!token) return NextResponse.json({ error: 'Missing authorization' }, { status: 401 })

  const { data: { user }, error: authError } = await supabase.auth.getUser(token)
  if (authError || !user) return NextResponse.json({ error: 'Invalid token' }, { status: 401 })

  const body = await req.json().catch(() => ({}))
  const targetPlan: string = body.plan ?? 'pro'
  const priceId = PRICE_IDS[targetPlan]
  if (!priceId) return NextResponse.json({ error: 'Invalid plan' }, { status: 400 })

  const { data: profile } = await supabase
    .from('profiles').select('email, plan').eq('id', user.id).single()

  if (!profile?.email) return NextResponse.json({ error: 'Profile not found' }, { status: 404 })
  if (profile.plan === targetPlan) return NextResponse.json({ ok: true, alreadyOnPlan: true })

  // Look up customer ID from subscriptions table first (ID-based, reliable)
  // Fall back to email lookup for legacy accounts
  const { data: subRow } = await supabase
    .from('subscriptions')
    .select('stripe_customer_id, stripe_subscription_id')
    .eq('user_id', user.id)
    .maybeSingle()

  let customerId: string | null = subRow?.stripe_customer_id ?? null
  let stripeSubId: string | null = subRow?.stripe_subscription_id ?? null

  if (!customerId || customerId === 'admin_bypass') {
    const customers = await stripe.customers.list({ email: profile.email, limit: 1 })
    customerId = customers.data[0]?.id ?? null
    stripeSubId = null
  }

  if (!customerId) {
    return NextResponse.json({ error: 'NO_STRIPE_CUSTOMER', redirectTo: `/atlas/checkout?plan=${targetPlan}` }, { status: 404 })
  }

  // Get active subscription if not already known
  if (!stripeSubId || stripeSubId === 'admin_bypass_sub') {
    const subs = await stripe.subscriptions.list({ customer: customerId, status: 'active', limit: 1 })
    stripeSubId = subs.data[0]?.id ?? null
  }

  if (!stripeSubId) {
    return NextResponse.json({ error: 'NO_STRIPE_CUSTOMER', redirectTo: `/atlas/checkout?plan=${targetPlan}` }, { status: 404 })
  }

  const sub = await stripe.subscriptions.retrieve(stripeSubId)
  const item = sub.items.data[0]
  // All plan changes are treated as upgrades (monthly → annual is the primary use case)
  const updatedSub = await stripe.subscriptions.update(sub.id, {
    items: [{ id: item.id, price: priceId }],
    proration_behavior: 'always_invoice',
    billing_cycle_anchor: 'now',
  })

  await supabase.from('profiles')
    .update({ plan: targetPlan, subscription_status: 'active' })
    .eq('id', user.id)

  await supabase.from('subscriptions').upsert({
    user_id:                user.id,
    stripe_customer_id:     customerId,
    stripe_subscription_id: sub.id,
    plan:                   targetPlan,
    status:                 'active',
    updated_at:             new Date().toISOString(),
  }, { onConflict: 'user_id' })

  const renewDate = updatedSub.current_period_end
    ? new Date(updatedSub.current_period_end * 1000).toLocaleDateString('en-US', { month: 'long', day: 'numeric', year: 'numeric' })
    : ''
  await sendEmail({ to: profile.email, template: 'subscription-confirmed', data: { renewDate } })

  return NextResponse.json({ ok: true })
}
