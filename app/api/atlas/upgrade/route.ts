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
  standard: 'price_1TliuWA1Bm2dPCGcbpXH9hE5', // TEST MODE
  pro:      'price_1TlitLA1Bm2dPCGcZRFxm68J',  // TEST MODE
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

  const customers = await stripe.customers.list({ email: profile.email, limit: 1 })
  const customer  = customers.data[0]
  if (!customer) return NextResponse.json({ error: 'NO_STRIPE_CUSTOMER', redirectTo: `/atlas/checkout?plan=atlas-${targetPlan}` }, { status: 404 })

  const subs = await stripe.subscriptions.list({ customer: customer.id, status: 'active', limit: 1 })
  const sub  = subs.data[0]
  if (!sub) return NextResponse.json({ error: 'NO_STRIPE_CUSTOMER', redirectTo: `/atlas/checkout?plan=atlas-${targetPlan}` }, { status: 404 })

  const item = sub.items.data[0]
  const isDowngrade = profile.plan === 'pro' && targetPlan === 'standard'
  const updatedSub = await stripe.subscriptions.update(sub.id, {
    items: [{ id: item.id, price: priceId }],
    proration_behavior: isDowngrade ? 'none' : 'always_invoice',
    billing_cycle_anchor: isDowngrade ? 'unchanged' : 'now',
  })

  await supabase.from('profiles')
    .update({ plan: targetPlan, subscription_status: 'active' })
    .eq('id', user.id)

  await supabase.from('subscriptions').upsert({
    user_id:                user.id,
    stripe_customer_id:     customer.id,
    stripe_subscription_id: sub.id,
    plan:                   targetPlan,
    status:                 'active',
    updated_at:             new Date().toISOString(),
  }, { onConflict: 'user_id' })

  const renewDate = updatedSub.current_period_end
    ? new Date(updatedSub.current_period_end * 1000).toLocaleDateString('en-US', { month: 'long', day: 'numeric', year: 'numeric' })
    : ''
  await sendEmail({ to: profile.email, template: 'subscription-confirmed', data: { plan: targetPlan, renewDate } })

  return NextResponse.json({ ok: true })
}
