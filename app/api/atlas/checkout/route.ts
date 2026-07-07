import { NextRequest, NextResponse } from 'next/server'
import Stripe from 'stripe'
import { createClient } from '@supabase/supabase-js'

const stripe = new Stripe(process.env.STRIPE_SECRET_KEY!, { apiVersion: '2024-06-20' })

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
)

const PRICE_IDS: Record<string, string> = {
  standard: 'price_1TdIbOA1Bm2dPCGcBzQIiXGV', // $14.99/mo
  pro:      'price_1TqJSEA1Bm2dPCGcEtL4Au0e',  // $0.50 TEST — restore to price_1TdIbOA1Bm2dPCGcpLFkuAea after test
}

export async function POST(req: NextRequest) {
  const { plan, email, userId } = await req.json()

  if (!plan || !email || !userId) {
    return NextResponse.json({ error: 'Missing plan, email, or userId' }, { status: 400 })
  }

  const priceId = PRICE_IDS[plan]
  if (!priceId) {
    return NextResponse.json({ error: 'Invalid plan' }, { status: 400 })
  }

  // Verify the auth user actually exists
  const { data: { user: authUser }, error: authErr } = await supabase.auth.admin.getUserById(userId)
  if (authErr || !authUser) {
    return NextResponse.json({ error: 'User not found' }, { status: 404 })
  }

  // Ensure a profiles row exists — the DB trigger should create it on signup,
  // but upsert here to close the race window between signUp() and this call.
  await supabase.from('profiles').upsert(
    { id: userId, email, plan: 'free', subscription_status: 'inactive' },
    { onConflict: 'id', ignoreDuplicates: true }
  )

  const session = await stripe.checkout.sessions.create({
    mode: 'subscription',
    payment_method_types: ['card'],
    customer_email: email,
    client_reference_id: userId,
    line_items: [{ price: priceId, quantity: 1 }],
    success_url: `https://www.interlinked.digital/atlas/checkout/success?session_id={CHECKOUT_SESSION_ID}`,
    cancel_url:  `https://www.interlinked.digital/atlas?cancelled=1`,
    metadata: { plan, supabase_user_id: userId },
  })

  return NextResponse.json({ url: session.url })
}
