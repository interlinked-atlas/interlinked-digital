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
BEGIN
  UPDATE profiles
  SET subscription_status = p_profile_status,
      plan                = p_plan
  WHERE id = p_user_id;

  UPDATE subscriptions
  SET status     = p_sub_status,
      updated_at = now()
  WHERE stripe_customer_id = p_stripe_customer_id;
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
  ADD COLUMN completed_at timestamptz;

ALTER TABLE stripe_webhook_events
  ADD CONSTRAINT stripe_webhook_events_status_check
  CHECK (status IN ('processing', 'succeeded', 'failed'));
