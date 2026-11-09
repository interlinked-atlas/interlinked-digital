import { NextRequest, NextResponse } from 'next/server'
import Stripe from 'stripe'
import { createClient } from '@supabase/supabase-js'

const stripe = new Stripe(process.env.STRIPE_SECRET_KEY!, { apiVersion: '2025-04-30.basil' })

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
)

// GET /api/atlas/billing-history — past invoices for the logged-in user's
// Stripe customer. Read-only, no amounts can be mutated through this route.
export async function GET(req: NextRequest) {
  const token = req.headers.get('authorization')?.replace('Bearer ', '').trim()
  if (!token) return NextResponse.json({ error: 'Missing authorization' }, { status: 401 })

  const { data: { user }, error: authError } = await supabase.auth.getUser(token)
  if (authError || !user) return NextResponse.json({ error: 'Invalid token' }, { status: 401 })

  const { data: sub } = await supabase
    .from('subscriptions')
    .select('stripe_customer_id')
    .eq('user_id', user.id)
    .maybeSingle()

  let customerId: string | null = sub?.stripe_customer_id ?? null

  if (!customerId || customerId.startsWith('admin')) {
    const { data: profile } = await supabase
      .from('profiles').select('email').eq('id', user.id).single()
    if (!profile?.email) return NextResponse.json({ invoices: [] })
    const customers = await stripe.customers.list({ email: profile.email, limit: 1 })
    customerId = customers.data[0]?.id ?? null
  }

  if (!customerId) return NextResponse.json({ invoices: [] })

  const list = await stripe.invoices.list({
    customer: customerId,
    limit: 24,
    expand: ['data.charge.payment_method_details'],
  })

  const invoices = list.data
    .filter(inv => inv.status === 'paid' || inv.status === 'open' || inv.status === 'uncollectible')
    .map(inv => ({
      id: inv.id,
      amount: inv.amount_paid || inv.amount_due,
      currency: inv.currency,
      status: inv.status,
      date: inv.status_transitions?.paid_at ?? inv.created,
      billing_reason: inv.billing_reason,
      card_brand: (inv as { charge?: { payment_method_details?: { card?: { brand?: string } } } }).charge?.payment_method_details?.card?.brand ?? null,
      card_last4: (inv as { charge?: { payment_method_details?: { card?: { last4?: string } } } }).charge?.payment_method_details?.card?.last4 ?? null,
      hosted_invoice_url: inv.hosted_invoice_url,
      invoice_pdf: inv.invoice_pdf,
    }))

  return NextResponse.json({ invoices })
}
