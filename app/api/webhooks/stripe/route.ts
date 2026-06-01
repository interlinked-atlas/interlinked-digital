import { NextResponse } from 'next/server'
import { headers } from 'next/headers'
import { stripe } from '@/lib/stripe'
import { createClient } from '@supabase/supabase-js'
import Stripe from 'stripe'

// Use service role for webhooks since there's no user session
const supabaseAdmin = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
)

export async function POST(request: Request) {
  const body = await request.text()
  const headersList = await headers()
  const sig = headersList.get('stripe-signature')

  if (!sig) {
    return NextResponse.json({ error: 'No signature' }, { status: 400 })
  }

  let event: Stripe.Event

  try {
    event = stripe.webhooks.constructEvent(
      body,
      sig,
      process.env.STRIPE_WEBHOOK_SECRET!
    )
  } catch (err) {
    console.error('Webhook signature verification failed:', err)
    return NextResponse.json({ error: 'Invalid signature' }, { status: 400 })
  }

  try {
    switch (event.type) {
      case 'checkout.session.completed': {
        const session = event.data.object as Stripe.Checkout.Session
        await handleCheckoutComplete(session)
        break
      }

      case 'customer.subscription.updated': {
        const subscription = event.data.object as Stripe.Subscription
        await handleSubscriptionUpdated(subscription)
        break
      }

      case 'customer.subscription.deleted': {
        const subscription = event.data.object as Stripe.Subscription
        await handleSubscriptionDeleted(subscription)
        break
      }

      case 'invoice.payment_failed': {
        const invoice = event.data.object as Stripe.Invoice
        await handlePaymentFailed(invoice)
        break
      }
    }

    return NextResponse.json({ received: true })
  } catch (error) {
    console.error('Webhook handler error:', error)
    return NextResponse.json({ error: 'Webhook handler failed' }, { status: 500 })
  }
}

async function handleCheckoutComplete(session: Stripe.Checkout.Session) {
  const customerEmail = session.customer_email || (session.customer_details?.email)
  const customerId = session.customer as string
  const subscriptionId = session.subscription as string
  const plan = session.metadata?.plan || 'basic'

  if (!customerEmail) {
    console.error('No customer email in checkout session')
    return
  }

  // Get subscription details
  const subscription = await stripe.subscriptions.retrieve(subscriptionId)

  // Check if user exists in Supabase
  const { data: existingUsers } = await supabaseAdmin.auth.admin.listUsers()
  let userId: string

  const existingUser = existingUsers?.users.find(u => u.email === customerEmail)
  
  if (existingUser) {
    userId = existingUser.id
  } else {
    // Create a new user with a temporary password (they'll need to reset it)
    const tempPassword = crypto.randomUUID()
    const { data: newUser, error: createError } = await supabaseAdmin.auth.admin.createUser({
      email: customerEmail,
      password: tempPassword,
      email_confirm: true, // Auto-confirm since they paid
      user_metadata: {
        plan,
        stripe_customer_id: customerId,
      },
    })

    if (createError || !newUser.user) {
      console.error('Failed to create user:', createError)
      return
    }

    userId = newUser.user.id

    // Send password reset email so they can set their password
    // TODO: Integrate with Resend for custom email
  }

  // Create or update subscription record
  const { error: subscriptionError } = await supabaseAdmin
    .from('subscriptions')
    .upsert({
      user_id: userId,
      stripe_customer_id: customerId,
      stripe_subscription_id: subscriptionId,
      plan,
      status: subscription.status,
      current_period_start: new Date(subscription.current_period_start * 1000).toISOString(),
      current_period_end: new Date(subscription.current_period_end * 1000).toISOString(),
      cancel_at_period_end: subscription.cancel_at_period_end,
      updated_at: new Date().toISOString(),
    }, {
      onConflict: 'stripe_subscription_id',
    })

  if (subscriptionError) {
    console.error('Failed to create subscription:', subscriptionError)
  }
}

async function handleSubscriptionUpdated(subscription: Stripe.Subscription) {
  const plan = subscription.metadata?.plan || 'basic'

  const { error } = await supabaseAdmin
    .from('subscriptions')
    .update({
      plan,
      status: subscription.status,
      current_period_start: new Date(subscription.current_period_start * 1000).toISOString(),
      current_period_end: new Date(subscription.current_period_end * 1000).toISOString(),
      cancel_at_period_end: subscription.cancel_at_period_end,
      updated_at: new Date().toISOString(),
    })
    .eq('stripe_subscription_id', subscription.id)

  if (error) {
    console.error('Failed to update subscription:', error)
  }
}

async function handleSubscriptionDeleted(subscription: Stripe.Subscription) {
  const { error } = await supabaseAdmin
    .from('subscriptions')
    .update({
      status: 'canceled',
      updated_at: new Date().toISOString(),
    })
    .eq('stripe_subscription_id', subscription.id)

  if (error) {
    console.error('Failed to cancel subscription:', error)
  }
}

async function handlePaymentFailed(invoice: Stripe.Invoice) {
  const subscriptionId = invoice.subscription as string
  
  if (!subscriptionId) return

  const { error } = await supabaseAdmin
    .from('subscriptions')
    .update({
      status: 'past_due',
      updated_at: new Date().toISOString(),
    })
    .eq('stripe_subscription_id', subscriptionId)

  if (error) {
    console.error('Failed to update subscription status:', error)
  }
}
