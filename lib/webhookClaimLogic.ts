// Pure-logic mirror of the decision branching inside the
// atlas_claim_webhook_event Postgres function (see
// supabase/migrations/20261021000000_atomic_entitlement_status_rpc.sql).
//
// This does NOT execute SQL and does NOT prove Postgres's actual row-locking
///serialization behavior — only a real database can prove that (see the
// staging procedure in the release report). What this verifies is that the
// three-way decision logic itself (claimed vs already_processing vs
// already_succeeded, and the staleness threshold) matches intent, so the SQL
// can be reviewed against a working, tested reference instead of by eye
// alone. Keep this in sync with the SQL function by hand — there is no
// automated way to guarantee the two never drift apart.
export type WebhookEventRow = { status: 'processing' | 'succeeded' | 'failed'; claimedAt: Date } | null
export type ClaimOutcome = 'claimed' | 'already_processing' | 'already_succeeded'

export function decideClaim(
  row: WebhookEventRow,
  now: Date,
  staleAfterSeconds = 360
): { outcome: ClaimOutcome; nextRow: { status: 'processing' | 'succeeded'; claimedAt: Date } } {
  if (row === null) {
    return { outcome: 'claimed', nextRow: { status: 'processing', claimedAt: now } }
  }
  if (row.status === 'succeeded') {
    return { outcome: 'already_succeeded', nextRow: { status: 'succeeded', claimedAt: row.claimedAt } }
  }
  const ageSeconds = (now.getTime() - row.claimedAt.getTime()) / 1000
  if (row.status === 'processing' && ageSeconds < staleAfterSeconds) {
    return { outcome: 'already_processing', nextRow: { status: 'processing', claimedAt: row.claimedAt } }
  }
  // 'failed', or stale 'processing' (abandoned) — reclaim.
  return { outcome: 'claimed', nextRow: { status: 'processing', claimedAt: now } }
}
