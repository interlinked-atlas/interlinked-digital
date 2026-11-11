-- The 10-day free-reactivation cancellation grace period (see
-- app/api/atlas/cancel/route.ts, app/api/atlas/reactivate/route.ts,
-- app/api/cron/grace-period-sweep) is a once-per-account lifetime benefit,
-- not something a user can repeat by cancelling and reactivating over and
-- over. This column is set the first time a grace period is granted; any
-- cancellation after that is an immediate, real Stripe cancellation with no
-- grace window — the account can still resubscribe normally at any time,
-- it just never gets another free-reactivate-no-charge option.
ALTER TABLE profiles
  ADD COLUMN IF NOT EXISTS grace_period_used_at timestamptz;

COMMENT ON COLUMN profiles.grace_period_used_at IS
  'Set the first time this account is granted the 10-day free-reactivation cancellation grace period. Any cancellation after this is set is an immediate, real cancellation with no grace window.';
