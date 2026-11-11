-- Lets an admin manually grant ATLAS access to an account despite no active
-- Stripe subscription (e.g. unblocking a cancelled test account for further
-- testing) — see app/api/atlas/admin/grant-access/route.ts. This is a pure
-- local entitlement override: it never touches Stripe, never creates a real
-- subscription, and never clears profiles.grace_period_used_at (the account's
-- real grace-period history stays accurate regardless of an admin override).
ALTER TABLE subscriptions
  ADD COLUMN IF NOT EXISTS admin_granted_access boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN subscriptions.admin_granted_access IS
  'True when an admin manually granted ATLAS access via /atlas/admin despite no active Stripe subscription — distinct from a real paying subscriber. Never touches Stripe or grace_period_used_at.';
