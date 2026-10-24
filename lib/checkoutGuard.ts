// Pure decision logic extracted from app/actions/stripe.ts's startCheckoutSession
// so it can be unit-tested without a real Stripe/Supabase call. The server
// action itself remains the source of truth at runtime — this module mirrors
// its two security-relevant decisions: which Stripe price a product ID
// resolves to, and whether an already-subscribed user may start a new
// checkout session.

import { PRODUCTS, PRICE_IDS } from './products'

export class UnknownProductError extends Error {
  constructor(productId: string) {
    super(`Product with id "${productId}" not found`)
  }
}

export class NoPriceForProductError extends Error {
  constructor(productId: string) {
    super(`No Stripe price ID found for product "${productId}"`)
  }
}

// Resolves a client-supplied product ID to the server's own configured
// Stripe price ID. A tampered/unknown productId (anything other than the
// single live "atlas" entry in PRODUCTS) throws before any Stripe call is
// made — the client can request a product by ID, never supply a price.
export function resolveCheckoutPrice(productId: string): { priceId: string; planKey: string } {
  const product = PRODUCTS.find((p) => p.id === productId)
  if (!product) {
    throw new UnknownProductError(productId)
  }

  const planKey = productId.startsWith('atlas') ? productId : productId.replace('atlas-', '')
  const priceId = PRICE_IDS[planKey as keyof typeof PRICE_IDS]
  if (!priceId) {
    throw new NoPriceForProductError(productId)
  }

  return { priceId, planKey }
}

export type ExistingSubscription = { status: string } | null | undefined

export type CheckoutEligibility = 'allow' | 'already_subscribed'

// A logged-in user with a currently-active subscription must not be allowed
// to open a second Checkout Session — that would risk a duplicate Stripe
// subscription for one account. Any other status (none, canceled, past_due,
// etc, all denied-access statuses under the active-only entitlement policy)
// is allowed to check out, since it represents no live paid access today.
export function decideCheckoutEligibility(subscription: ExistingSubscription): CheckoutEligibility {
  if (subscription?.status === 'active') return 'already_subscribed'
  return 'allow'
}
