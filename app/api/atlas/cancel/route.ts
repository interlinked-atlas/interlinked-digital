import { NextResponse } from 'next/server'
import Stripe from 'stripe'
import { createClient } from '@supabase/supabase-js'

const stripe = new Stripe(process.env.STRIPE_SECRET_KEY!, { apiVersion: '2024-06-20' })

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
)

// POST /api/atlas/cancel
// Called by ATLAS app when user cancels subscription.
// Cancels Stripe subscription immediately, updates DB, returns signal to log out.
export async function POST(request: Request) {
  const authHeader = request.headers.get('authorization')
  if (!authHeader?.startsWith('Bearer ')) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  }

  const token = authHeader.substring(7)
  const { data: { user }, error: authError } = await supabase.auth.getUser(token)
  if (authError || !user) {
    return NextResponse.json({ error: 'Invalid token' }, { status: 401 })
  }

  try {
    // 1. Find stripe_subscription_id — first check subscriptions table
    const { data: sub } = await supabase
      .from('subscriptions')
      .select('stripe_subscription_id, stripe_customer_id')
      .eq('user_id', user.id)
      .in('status', ['active', 'past_due', 'trialing'])
      .order('updated_at', { ascending: false })
      .limit(1)
      .single()

    let subscriptionId = sub?.stripe_subscription_id ?? null

    // 2. Fallback: look up by email in Stripe
    if (!subscriptionId && user.email) {
      const customers = await stripe.customers.list({ email: user.email, limit: 1 })
      const customer = customers.data[0]
      if (customer) {
        const subs = await stripe.subscriptions.list({
          customer: customer.id,
          status: 'active',
          limit: 1,
        })
        subscriptionId = subs.data[0]?.id ?? null
      }
    }

    if (!subscriptionId) {
      return NextResponse.json({ error: 'No active subscription found' }, { status: 404 })
    }

    // 3. Cancel immediately in Stripe
    await stripe.subscriptions.cancel(subscriptionId)

    // 4. Update profiles table (ATLAS app reads this)
    await supabase
      .from('profiles')
      .update({ subscription_status: 'cancelled' })
      .eq('id', user.id)

    // 5. Update subscriptions table (website reads this)
    await supabase
      .from('subscriptions')
      .update({ status: 'canceled', cancel_at_period_end: false, updated_at: new Date().toISOString() })
      .eq('user_id', user.id)

    console.log(`[ATLAS] Subscription cancelled for ${user.email}`)

    return NextResponse.json({ success: true, action: 'sign_out' })
  } catch (err: any) {
    console.error('[ATLAS] Cancel error:', err.message)
    return NextResponse.json({ error: err.message }, { status: 500 })
  }
}
