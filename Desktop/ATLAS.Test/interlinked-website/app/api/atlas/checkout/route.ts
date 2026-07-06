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
  pro:      'price_1TdIbOA1Bm2dPCGcpLFkuAea',  // $29.99/mo
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

  // Verify the user actually exists in Supabase
  const { data: profile } = await supabase
    .from('profiles').select('id, email').eq('id', userId).maybeSingle()

  if (!profile) {
    return NextResponse.json({ error: 'User not found' }, { status: 404 })
  }

  const session = await stripe.checkout.sessions.create({
    mode: 'subscription',
    payment_method_types: ['card'],
    customer_email: email,           // pre-filled, user can't change it
    client_reference_id: userId,     // Supabase user ID — webhook uses this
    line_items: [{ price: priceId, quantity: 1 }],
    success_url: `https://www.interlinked.digital/atlas/account?welcome=1`,
    cancel_url:  `https://www.interlinked.digital/atlas?cancelled=1`,
    metadata: { plan, supabase_user_id: userId },
  })

  return NextResponse.json({ url: session.url })
}
