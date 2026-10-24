// Run with: npx tsx --test lib/checkoutGuard.test.ts
// Unit-tests the pure decision logic extracted from
// app/actions/stripe.ts's startCheckoutSession — not a real Stripe/Supabase
// call, and not proof the live endpoint behaves identically; it proves the
// guard logic itself is correct given the inputs it can receive.
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { resolveCheckoutPrice, decideCheckoutEligibility, UnknownProductError, NoPriceForProductError } from './checkoutGuard'

test('the only live product resolves to the configured $30/month price', () => {
  const { priceId, planKey } = resolveCheckoutPrice('atlas')
  assert.equal(planKey, 'atlas')
  assert.equal(priceId, 'price_1U9uOBA1Bm2dPCGc73d3ZbA5')
})

test('a tampered/unknown product id is rejected before any Stripe call', () => {
  assert.throws(() => resolveCheckoutPrice('free-forever'), UnknownProductError)
  assert.throws(() => resolveCheckoutPrice(''), UnknownProductError)
  assert.throws(() => resolveCheckoutPrice('atlas; DROP TABLE subscriptions'), UnknownProductError)
})

test('a legacy (removed) tier id is not in PRODUCTS, so it is rejected the same way', () => {
  // "standard"/"pro" still exist in PRICE_IDS for historical webhook replay,
  // but PRODUCTS only lists "atlas" — a client cannot resolve a checkout
  // session against a retired tier even though its price ID is still mapped.
  assert.throws(() => resolveCheckoutPrice('standard'), UnknownProductError)
  assert.throws(() => resolveCheckoutPrice('pro-annual'), UnknownProductError)
})

test('no existing subscription: checkout is allowed', () => {
  assert.equal(decideCheckoutEligibility(null), 'allow')
  assert.equal(decideCheckoutEligibility(undefined), 'allow')
})

test('an active subscription blocks a second checkout session', () => {
  assert.equal(decideCheckoutEligibility({ status: 'active' }), 'already_subscribed')
})

test('a non-active subscription (cancelled, past_due, incomplete) does not block checkout', () => {
  for (const status of ['canceled', 'past_due', 'incomplete', 'incomplete_expired', 'unpaid', 'paused']) {
    assert.equal(decideCheckoutEligibility({ status }), 'allow', `status=${status} should allow checkout`)
  }
})

test('NoPriceForProductError exists as a distinct, catchable error type', () => {
  // Every current PRODUCTS entry has a matching PRICE_IDS entry (verified by
  // the first test above), so this path is unreachable with today's data —
  // this only confirms the error class itself constructs correctly, as a
  // guard against a future PRODUCTS/PRICE_IDS entry drifting out of sync.
  const err = new NoPriceForProductError('atlas-missing')
  assert.match(err.message, /No Stripe price ID found/)
})
