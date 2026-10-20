-- Idempotency ledger for the Stripe webhook handler (app/api/webhooks/stripe/route.ts).
-- Each Stripe event.id is inserted exactly once before its side effects run; a
-- retried/duplicate delivery hits the primary key conflict and is skipped,
-- preventing duplicate emails, duplicate audit-log rows, or repeated
-- irreversible writes (entitlement revocation, etc).
CREATE TABLE stripe_webhook_events (
  id          text PRIMARY KEY,         -- Stripe event.id
  type        text NOT NULL,
  received_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX stripe_webhook_events_received_at_idx ON stripe_webhook_events(received_at DESC);

ALTER TABLE stripe_webhook_events ENABLE ROW LEVEL SECURITY;
-- Service-role only — the webhook route uses the service-role key; no client ever reads/writes this.
CREATE POLICY "No public access" ON stripe_webhook_events FOR ALL USING (false);
