-- Enforces the one-subscription-row-per-user data model that
-- upsertSubscription() already assumes. Verified via a read-only production
-- query (SELECT user_id, count(*) ... HAVING count(*) > 1) that zero
-- duplicate rows exist today, so this constraint is safe to add as-is —
-- no cleanup/merge step is required before applying it.
--
-- This closes the TOCTOU race in upsertSubscription(): previously it did a
-- separate SELECT-then-INSERT-or-UPDATE, so two concurrent webhook
-- deliveries for a brand-new subscriber could both pass the SELECT before
-- either write landed, producing two rows for one user. With this
-- constraint in place, the application is updated (same commit) to use a
-- single `.upsert(payload, { onConflict: 'user_id' })` call, which Postgres
-- resolves atomically against this constraint — a concurrent second
-- attempt deterministically updates the same row instead of racing to
-- insert a duplicate.
ALTER TABLE public.subscriptions
  ADD CONSTRAINT subscriptions_user_id_key UNIQUE (user_id);
