'use server'

import { stripe } from '@/lib/stripe'
import { PRODUCTS } from '@/lib/products'
import { createClient } from '@/lib/supabase/server'
import { headers } from 'next/headers'

export async function startCheckoutSession(productId: string, email?: string) {
  const product = PRODUCTS.find((p) => p.id === productId)
  if (!product) {
    throw new Error(`Product with id "${productId}" not found`)
  }

  const headersList = await headers()
  const origin = headersList.get('origin') || 'https://interlinked.digital'

  // Check if user is already logged in
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()

  const sessionConfig: Parameters<typeof stripe.checkout.sessions.create>[0] = {
    ui_mode: 'embedded',
    redirect_on_completion: 'never',
    line_items: [
      {
        price_data: {
          currency: 'usd',
          product_data: {
            name: product.name,
            description: product.description,
          },
          unit_amount: product.priceInCents,
          recurring: {
            interval: product.interval,
          },
        },
        quantity: 1,
      },
    ],
    mode: 'subscription',
    subscription_data: {
      metadata: {
        plan: productId.replace('atlas-', ''),
      },
    },
    metadata: {
      plan: productId.replace('atlas-', ''),
    },
  }

  // If user is logged in, attach their customer ID or email
  if (user) {
    // Check if they already have a stripe customer ID
    const { data: subscription } = await supabase
      .from('subscriptions')
      .select('stripe_customer_id')
      .eq('user_id', user.id)
      .single()

    if (subscription?.stripe_customer_id) {
      sessionConfig.customer = subscription.stripe_customer_id
    } else {
      sessionConfig.customer_email = user.email
    }
  } else if (email) {
    sessionConfig.customer_email = email
  }

  const session = await stripe.checkout.sessions.create(sessionConfig)

  return session.client_secret
}

export async function getCheckoutSessionStatus(sessionId: string) {
  const session = await stripe.checkout.sessions.retrieve(sessionId, {
    expand: ['customer', 'subscription'],
  })

  return {
    status: session.status,
    customerEmail: typeof session.customer === 'object' && session.customer !== null 
      ? session.customer.email 
      : session.customer_email,
    subscriptionId: typeof session.subscription === 'object' && session.subscription !== null
      ? session.subscription.id
      : session.subscription,
  }
}
