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

  // ATLAS policy (2026-10-20): schedule cancellation for the end of the
  // current billing period rather than cancelling immediately — the customer
  // has already paid for this period and keeps access through it. Do NOT
  // write 'cancelled'/'canceled' to profiles/subscriptions here: the account
  // remains active until Stripe's customer.subscription.updated (recording
  // cancel_at_period_end) and, at the actual period end,
  // customer.subscription.deleted fire and the webhook updates status itself.
  // Writing a terminal status here would incorrectly revoke access early.
  const updatedSub = await stripe.subscriptions.update(stripeSubId, { cancel_at_period_end: true })

  return NextResponse.json({
    ok: true,
    cancel_at_period_end: true,
    access_until: updatedSub.current_period_end
      ? new Date(updatedSub.current_period_end * 1000).toISOString()
      : null,
  })
}
