// Run with: npx tsx --test lib/webhookClaimLogic.test.ts
// See webhookClaimLogic.ts for what this does and does not prove — it
// verifies the decision logic mirrored from the SQL function, not Postgres's
// actual row-locking/serialization behavior (that needs a live database;
// see the release report's staging procedure).
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { decideClaim } from './webhookClaimLogic'

test('sequential duplicate: fresh event, then a retry after it succeeded', () => {
  const t0 = new Date('2026-10-21T00:00:00Z')
  const first = decideClaim(null, t0)
  assert.equal(first.outcome, 'claimed')

  // First attempt completes successfully.
  const succeededRow = { status: 'succeeded' as const, claimedAt: t0 }
  const retry = decideClaim(succeededRow, new Date(t0.getTime() + 5000))
  assert.equal(retry.outcome, 'already_succeeded')
})

test('simultaneous claims: the second caller to resolve against the committed row loses', () => {
  const t0 = new Date('2026-10-21T00:00:00Z')
  // Caller A claims first (models A's transaction committing first under
  // Postgres's row-lock serialization).
  const callerA = decideClaim(null, t0)
  assert.equal(callerA.outcome, 'claimed')

  // Caller B's claim resolves against A's now-committed row, a moment later —
  // this is what every other concurrent caller sees once Postgres's internal
  // lock on the first INSERT/SELECT-FOR-UPDATE releases.
  const callerB = decideClaim(callerA.nextRow, new Date(t0.getTime() + 50))
  assert.equal(callerB.outcome, 'already_processing', 'loser must not run side effects')
})

test('retry after explicit failure is allowed through immediately, no staleness wait', () => {
  const failedRow = { status: 'failed' as const, claimedAt: new Date('2026-10-21T00:00:00Z') }
  const retry = decideClaim(failedRow, new Date('2026-10-21T00:00:01Z')) // 1s later
  assert.equal(retry.outcome, 'claimed')
})

test('retry while a claim is still fresh ("processing") is rejected — not a failure, not stale', () => {
  const freshProcessing = { status: 'processing' as const, claimedAt: new Date('2026-10-21T00:00:00Z') }
  const retry = decideClaim(freshProcessing, new Date('2026-10-21T00:01:00Z')) // 60s later, under 360s default
  assert.equal(retry.outcome, 'already_processing')
})

test('abandoned processing (crashed, never resolved) becomes reclaimable after the staleness window', () => {
  const abandoned = { status: 'processing' as const, claimedAt: new Date('2026-10-21T00:00:00Z') }
  const retry = decideClaim(abandoned, new Date('2026-10-21T00:07:00Z')) // 420s later, over 360s default
  assert.equal(retry.outcome, 'claimed')
})
