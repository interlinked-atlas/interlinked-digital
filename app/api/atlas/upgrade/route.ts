import { NextResponse } from 'next/server'
import Stripe from 'stripe'
import { createClient } from '@supabase/supabase-js'

const stripe = new Stripe(process.env.STRIPE_SECRET_KEY!, { apiVersion: '2024-06-20' })
const supabase = createClient(process.env.NEXT_PUBLIC_SUPABASE_URL!, process.env.SUPABASE_SERVICE_ROLE_KEY!)

const PRO_PRICE_ID = 'price_1TdIbOA1Bm2dPCGcpLFkuAea'

// POST /api/atlas/upgrade — upgrade Standard → Pro in-place (Stripe handles proration)
export async function POST(request: Request) {
  const authHeader = request.headers.get('authorization')
  if (!authHeader?.startsWith('Bearer ')) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  const token = authHeader.substring(7)
  const { data: { user }, error: authError } = await supabase.auth.getUser(token)
  if (authError || !user) return NextResponse.json({ error: 'Invalid token' }, { status: 401 })

  const { data: sub } = await supabase
    .from('subscriptions')
    .select('stripe_subscription_id')
    .eq('user_id', user.id)
    .in('status', ['active', 'trialing'])
    .order('updated_at', { ascending: false })
    .limit(1).single()

  if (!sub?.stripe_subscription_id) {
    return NextResponse.json({ error: 'No active subscription found' }, { status: 404 })
  }

  // Retrieve and update the subscription to Pro — Stripe auto-prorates
  const subscription = await stripe.subscriptions.retrieve(sub.stripe_subscription_id)
  const updatedSub = await stripe.subscriptions.update(sub.stripe_subscription_id, {
    items: [{ id: subscription.items.data[0].id, price: PRO_PRICE_ID }],
    proration_behavior: 'create_prorations',
  })

  // Immediately reflect upgrade in DB (webhook will also fire, but this is instant)
  await supabase.from('profiles')
    .update({ plan: 'pro', subscription_status: 'active' })
    .eq('id', user.id)
  await supabase.from('subscriptions')
    .update({ plan: 'pro', status: 'active', updated_at: new Date().toISOString() })
    .eq('user_id', user.id)

  return NextResponse.json({ success: true, plan: 'pro', subscription_id: updatedSub.id })
}
