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

const GRACE_DAYS = 10

// POST /api/atlas/reactivate
//
// Self-service "I changed my mind" within the 10-day free-reactivation
// window. Un-cancels the SAME Stripe subscription (cancel_at_period_end ->
// false) — the existing webhook (customer.subscription.updated) already
// restores entitlement the instant that flips, so this route doesn't need
// to touch profiles/subscriptions entitlement fields itself. No new
// charge: same card, same billing anchor, same subscription object.
export async function POST(req: NextRequest) {
  const token = req.headers.get('authorization')?.replace('Bearer ', '').trim()
  if (!token) return NextResponse.json({ error: 'Missing authorization' }, { status: 401 })

  const { data: { user }, error: authError } = await supabase.auth.getUser(token)
  if (authError || !user) return NextResponse.json({ error: 'Invalid token' }, { status: 401 })

  const { data: profile } = await supabase.from('profiles').select('atlas_suspended').eq('id', user.id).maybeSingle()
  if (profile?.atlas_suspended) {
    return NextResponse.json({ error: 'account_suspended', message: 'This account is permanently closed and cannot be reactivated. Please sign up again.' }, { status: 403 })
  }

  const { data: sub } = await supabase
    .from('subscriptions')
    .select('stripe_subscription_id, cancel_at_period_end, cancelled_at')
    .eq('user_id', user.id)
    .maybeSingle()

  if (!sub?.stripe_subscription_id || !sub.cancel_at_period_end) {
    return NextResponse.json({ error: 'not_cancelled', message: 'This account is not currently cancelled.' }, { status: 400 })
  }

  if (sub.cancelled_at) {
    const deadline = new Date(sub.cancelled_at).getTime() + GRACE_DAYS * 24 * 60 * 60 * 1000
    if (Date.now() > deadline) {
      return NextResponse.json({ error: 'grace_period_expired', message: 'The 10-day reactivation window has passed. Please sign up again.' }, { status: 403 })
    }
  }

  await stripe.subscriptions.update(sub.stripe_subscription_id, { cancel_at_period_end: false })
  await supabase.from('subscriptions').update({ cancelled_at: null }).eq('user_id', user.id)

  return NextResponse.json({ ok: true })
}
