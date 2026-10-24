// Regression test for the canceled/cancelled spelling fix found in the
// 2026-10-21 webhook audit. Run with: npx tsx --test lib/billingStatus.test.ts
// (no test framework added — uses Node's built-in test runner).
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { isAlreadyCancelledStatus, computeEffectiveEntitlement } from './billingStatus'

test('recognizes British spelling (written by handleCancellation/revokeAccessForCustomer)', () => {
  assert.equal(isAlreadyCancelledStatus('cancelled'), true)
})

test('recognizes American spelling (Stripe\'s raw status, previously written by upsertSubscription)', () => {
  assert.equal(isAlreadyCancelledStatus('canceled'), true)
})

test('does not match active/past_due/etc', () => {
  assert.equal(isAlreadyCancelledStatus('active'), false)
  assert.equal(isAlreadyCancelledStatus('past_due'), false)
  assert.equal(isAlreadyCancelledStatus('trialing'), false)
})

test('handles null/undefined (no profile row yet) without throwing', () => {
  assert.equal(isAlreadyCancelledStatus(null), false)
  assert.equal(isAlreadyCancelledStatus(undefined), false)
})

// Immediate-revocation policy (2026-10-23) — computeEffectiveEntitlement()

test('active status, no scheduled cancellation: active', () => {
  assert.deepEqual(computeEffectiveEntitlement('active', false), { profileStatus: 'active', subStatus: 'active' })
})

test('active status, but cancel_at_period_end=true: revoked immediately, not left active', () => {
  // This is the exact case the fix targets — Stripe's own status is still
  // 'active' throughout the cancel-scheduled window.
  assert.deepEqual(computeEffectiveEntitlement('active', true), { profileStatus: 'cancelled', subStatus: 'canceled' })
})

test('reversal: cancel_at_period_end flips back to false with status still active: access restored', () => {
  // Pure function of the current event's own fields — no separate reversal
  // branch, so a reversal can never be "missed" by stale prior state.
  assert.deepEqual(computeEffectiveEntitlement('active', false), { profileStatus: 'active', subStatus: 'active' })
})

test('Stripe status already canceled (actual deletion/period end): revoked, cancelAtPeriodEnd irrelevant', () => {
  assert.deepEqual(computeEffectiveEntitlement('canceled', false), { profileStatus: 'cancelled', subStatus: 'canceled' })
  assert.deepEqual(computeEffectiveEntitlement('canceled', true), { profileStatus: 'cancelled', subStatus: 'canceled' })
})

test('past_due with no scheduled cancellation: past_due, not revoked, not active', () => {
  assert.deepEqual(computeEffectiveEntitlement('past_due', false), { profileStatus: 'past_due', subStatus: 'past_due' })
})

test('past_due AND cancel_at_period_end=true: cancellation takes priority over past_due', () => {
  assert.deepEqual(computeEffectiveEntitlement('past_due', true), { profileStatus: 'cancelled', subStatus: 'canceled' })
})

test('unrecognized/incomplete status: passed through for profile, normalized to incomplete for subscription', () => {
  assert.deepEqual(computeEffectiveEntitlement('incomplete_expired', false), { profileStatus: 'incomplete_expired', subStatus: 'incomplete' })
})
