// Run with: npx tsx --test lib/entitlementPoll.test.ts
// Unit-tests the success page's "keep waiting for the webhook, or give up"
// decision in isolation from React, timers, and the real Supabase client.
// Proves the loop terminates and resolves correctly; does not prove the
// webhook itself completes in any particular time (that depends on Stripe's
// and Vercel's actual delivery/processing latency, which this cannot model).
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { nextPollOutcome } from './entitlementPoll'

test('subscription already active on the first check: stop immediately', () => {
  assert.equal(nextPollOutcome('active', 0, 5), 'active')
})

test('no subscription row yet (webhook has not run at all): keeps retrying', () => {
  assert.equal(nextPollOutcome(null, 0, 5), 'retry')
  assert.equal(nextPollOutcome(undefined, 1, 5), 'retry')
})

test('subscription row exists but not yet active (e.g. still "incomplete"): keeps retrying', () => {
  assert.equal(nextPollOutcome('incomplete', 2, 5), 'retry')
})

test('webhook never lands within the poll window: gives up on the final attempt, never hangs', () => {
  assert.equal(nextPollOutcome(null, 4, 5), 'give_up')
})

test('becomes active exactly on the last allowed attempt: still reports active, not give_up', () => {
  assert.equal(nextPollOutcome('active', 4, 5), 'active')
})

test('a single-attempt budget still terminates deterministically either way', () => {
  assert.equal(nextPollOutcome('active', 0, 1), 'active')
  assert.equal(nextPollOutcome(null, 0, 1), 'give_up')
})
