import { NextRequest, NextResponse } from 'next/server'
import Stripe from 'stripe'
import { createClient } from '@supabase/supabase-js'

const stripe = new Stripe(process.env.STRIPE_SECRET_KEY!, { apiVersion: '2025-04-30.basil' })

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
)

export async function POST(req: NextRequest) {
  const token = req.headers.get('authorization')?.replace('Bearer ', '').trim()
  if (!token) return NextResponse.json({ error: 'Missing authorization' }, { status: 401 })

  const { data: { user }, error: authError } = await supabase.auth.getUser(token)
  if (authError || !user) return NextResponse.json({ error: 'Invalid token' }, { status: 401 })

  // Prefer stripe_customer_id from subscriptions table (set by webhook, reliable)
  // Fall back to email lookup for legacy accounts
  const { data: sub } = await supabase
    .from('subscriptions')
    .select('stripe_customer_id')
    .eq('user_id', user.id)
    .maybeSingle()

  let customerId: string | null = sub?.stripe_customer_id ?? null

  if (!customerId || customerId === 'admin_bypass') {
    // Fallback: look up by email
    const { data: profile } = await supabase
      .from('profiles').select('email').eq('id', user.id).single()
    if (!profile?.email) return NextResponse.json({ error: 'Profile not found' }, { status: 404 })
    const customers = await stripe.customers.list({ email: profile.email, limit: 1 })
    customerId = customers.data[0]?.id ?? null
  }

  if (!customerId) {
    return NextResponse.json({ error: 'No Stripe customer found' }, { status: 404 })
  }

  const session = await stripe.billingPortal.sessions.create({
    customer: customerId,
    return_url: 'https://www.interlinked.digital/atlas/account',
    configuration: 'bpc_1Tr2qTA1Bm2dPCGcziZYlzD7',
  })

  return NextResponse.json({ url: session.url })
}
