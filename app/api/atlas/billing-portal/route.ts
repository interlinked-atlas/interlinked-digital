import { NextRequest, NextResponse } from 'next/server'
import Stripe from 'stripe'
import { createClient } from '@supabase/supabase-js'

const stripe = new Stripe(process.env.STRIPE_SECRET_KEY!, { apiVersion: '2024-06-20' })

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
)

export async function POST(req: NextRequest) {
  const authHeader = req.headers.get('authorization')
  if (!authHeader?.startsWith('Bearer ')) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  }
  const token = authHeader.slice(7)

  // Validate user
  const userClient = createClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!
  )
  const { data: { user }, error: authError } = await userClient.auth.getUser(token)
  if (authError || !user) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  }

  // Get stripe_customer_id from subscriptions
  const { data: sub } = await supabase
    .from('subscriptions')
    .select('stripe_customer_id')
    .eq('user_id', user.id)
    .single()

  const customerId = sub?.stripe_customer_id

  if (!customerId || customerId.startsWith('admin')) {
    return NextResponse.json({ error: 'No active Stripe subscription found. Manage your plan from the ATLAS website.' }, { status: 400 })
  }

  const origin = req.headers.get('origin') || 'https://www.interlinked.digital'
  const session = await stripe.billingPortal.sessions.create({
    customer: customerId,
    return_url: `${origin}/atlas/account`,
  })

  return NextResponse.json({ url: session.url })
}
