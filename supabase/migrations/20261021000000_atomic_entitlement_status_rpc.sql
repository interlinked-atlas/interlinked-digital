-- Fixes a real partial-failure gap identified in review: the Stripe webhook
-- handler (handleCancellation, revokeAccessForCustomer, upsertSubscription)
-- previously issued two independent, sequential writes — one to `profiles`,
-- one to `subscriptions` — with no transaction between them. If the process
-- crashed or the request failed between the two writes, a retry could leave
-- the account permanently split between an old profile status and a new
-- subscription status (or vice versa), because each write is individually
-- idempotent but the PAIR of writes was not atomic.
--
-- This function performs both updates inside a single Postgres function,
-- which runs as one implicit transaction — either both writes land or
-- neither does. Service-role only; never exposed to anon/authenticated.
CREATE OR REPLACE FUNCTION public.atlas_set_entitlement_status(
  p_user_id             uuid,
  p_stripe_customer_id  text,
  p_profile_status      text,
  p_plan                text,
  p_sub_status          text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_profiles_updated     int;
  v_subscriptions_updated int;
BEGIN
  UPDATE profiles
  SET subscription_status = p_profile_status,
      plan                = p_plan
  WHERE id = p_user_id;
  GET DIAGNOSTICS v_profiles_updated = ROW_COUNT;

  UPDATE subscriptions
  SET status     = p_sub_status,
      updated_at = now()
  WHERE stripe_customer_id = p_stripe_customer_id;
  GET DIAGNOSTICS v_subscriptions_updated = ROW_COUNT;

  -- Without this, the function previously returned success even if
  -- p_user_id or p_stripe_customer_id matched no row at all — the caller
  -- (handleCancellation/revokeAccessForCustomer) would then send a
  -- "subscription cancelled" email and write an audit row claiming access
  -- was revoked, while the database was silently untouched. Raising here
  -- makes that case a genuine failure: the exception rolls back both
  -- UPDATEs (atomicity preserved either way) and propagates to the caller
  -- as an RPC error, which the webhook route already treats as a failure —
  -- marking the event 'failed' and letting Stripe's retry try again.
  IF v_profiles_updated = 0 THEN
    RAISE EXCEPTION 'atlas_set_entitlement_status: no profiles row for user_id %', p_user_id;
  END IF;
  IF v_subscriptions_updated = 0 THEN
    RAISE EXCEPTION 'atlas_set_entitlement_status: no subscriptions row for stripe_customer_id %', p_stripe_customer_id;
  END IF;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.atlas_set_entitlement_status(uuid, text, text, text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.atlas_set_entitlement_status(uuid, text, text, text, text) TO service_role;

-- Idempotency ledger upgrade: the original stripe_webhook_events table
-- (migration 20261020000000) only ever recorded "claimed" vs "not present,"
-- and a failed attempt deleted its own claim row — meaning a retry could not
-- tell the difference between "never attempted" and "attempted but crashed
-- partway through," and (before this migration) a crash between the two
-- writes above could leave inconsistent state with no record it had
-- happened at all.
--
-- Add an explicit status + timestamps so a retry can tell these apart:
--   'processing' — claimed, not yet known to have finished (fresh attempt OR
--                   a crashed previous attempt — both are safe to re-run,
--                   since the entitlement writes above are themselves
--                   idempotent SETs, and this status alone never blocks a retry)
--   'succeeded'  — fully completed, including side effects (email/audit/
--                   notify) — a genuine duplicate delivery of a 'succeeded'
--                   event is skipped entirely, which is what actually
--                   prevents duplicate emails/audit rows on Stripe's normal
--                   retry-until-2xx behavior.
--   'failed'     — the attempt raised; kept (not deleted) so there is a
--                   permanent record distinguishing "never ran" from "ran
--                   and failed," and so a retry is still allowed through.
ALTER TABLE stripe_webhook_events
  ADD COLUMN status text NOT NULL DEFAULT 'processing',
  ADD COLUMN completed_at timestamptz,
  ADD COLUMN claimed_at timestamptz NOT NULL DEFAULT now();

ALTER TABLE stripe_webhook_events
  ADD CONSTRAINT stripe_webhook_events_status_check
  CHECK (status IN ('processing', 'succeeded', 'failed'));

-- Resolves event-ownership atomically, including true concurrent delivery of
-- the same event.id — not just the narrower SELECT-then-INSERT gap an
-- earlier version of this function closed only partially.
--
-- Three explicit outcomes, so the caller can never confuse "I own this, run
-- the handler" with "someone else owns this right now, do nothing":
--   'claimed'            — this call now owns the event. Either it's brand
--                           new, or the previous owner's claim is stale
--                           (abandoned: crashed/timed out past
--                           p_stale_after_seconds with no resolution) or
--                           explicitly 'failed'. Caller MUST run the handler.
--   'already_processing' — another call claimed this event and is still
--                           within its liveness window (claimed_at recent).
--                           Caller MUST return immediately and run NO
--                           billing/email/audit side effects — this is the
--                           losing side of a genuine concurrent race.
--   'already_succeeded'  — fully done. Caller MUST return immediately with
--                           no side effects.
--
-- Ownership determination is atomic even when the row does not exist yet:
-- SELECT ... FOR UPDATE serializes against an existing row (a second
-- transaction blocks on the first's row lock until it commits, then sees the
-- committed status/claimed_at — never a stale read); for a brand-new event,
-- concurrent INSERTs of the same primary key serialize the same way (the
-- second's INSERT blocks on the first's row-level lock, then raises
-- unique_violation once the first commits, which sends it back through the
-- loop to the now-visible row). At no point can two callers both reach
-- 'claimed' for the same event while a prior claim is still live.
--
-- p_stale_after_seconds defaults to 360s — comfortably above this app's
-- actual webhook-handler duration and above typical serverless function
-- timeouts, so a still-genuinely-running attempt is never reclaimed out from
-- under itself; only a truly abandoned one (crashed, or the platform killed
-- it without this function's own failure path running) becomes reclaimable.
CREATE OR REPLACE FUNCTION public.atlas_claim_webhook_event(
  p_id                 text,
  p_type               text,
  p_stale_after_seconds int DEFAULT 360
)
RETURNS text  -- 'claimed' | 'already_processing' | 'already_succeeded'
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_status     text;
  v_claimed_at timestamptz;
BEGIN
  LOOP
    SELECT status, claimed_at INTO v_status, v_claimed_at
      FROM stripe_webhook_events WHERE id = p_id FOR UPDATE;

    IF FOUND THEN
      IF v_status = 'succeeded' THEN
        RETURN 'already_succeeded';
      END IF;

      IF v_status = 'processing' AND v_claimed_at > now() - (p_stale_after_seconds || ' seconds')::interval THEN
        -- Someone else claimed this very recently and hasn't failed or
        -- succeeded yet — this is the losing side of a real concurrent (or
        -- near-concurrent) delivery. Do not take ownership.
        RETURN 'already_processing';
      END IF;

      -- 'failed' (always reclaimable), or 'processing' but stale beyond the
      -- liveness window (abandoned — the previous owner never resolved it).
      -- Reclaim: take ownership and reset claimed_at to NOW so a third
      -- concurrent caller correctly sees this as freshly owned, not stale.
      UPDATE stripe_webhook_events SET status = 'processing', claimed_at = now() WHERE id = p_id;
      RETURN 'claimed';
    END IF;

    BEGIN
      INSERT INTO stripe_webhook_events (id, type, status, claimed_at) VALUES (p_id, p_type, 'processing', now());
      RETURN 'claimed';
    EXCEPTION WHEN unique_violation THEN
      -- Lost the race to insert to a concurrent caller, who has now
      -- committed — loop back; the SELECT above will see their row and
      -- correctly resolve to 'already_processing' or reclaim if stale.
      CONTINUE;
    END;
  END LOOP;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.atlas_claim_webhook_event(text, text, int) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.atlas_claim_webhook_event(text, text, int) TO service_role;
