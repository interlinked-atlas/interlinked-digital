
CREATE TABLE billing_audit_log (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at    timestamptz NOT NULL DEFAULT now(),
  event         text NOT NULL,
  user_id       uuid REFERENCES profiles(id) ON DELETE SET NULL,
  email         text,
  plan          text,
  stripe_event  text,
  metadata      jsonb,
  notes         text
);

CREATE INDEX billing_audit_log_user_id_idx ON billing_audit_log(user_id);
CREATE INDEX billing_audit_log_created_at_idx ON billing_audit_log(created_at DESC);

ALTER TABLE billing_audit_log ENABLE ROW LEVEL SECURITY;
-- Admin only — no public access
CREATE POLICY "No public access" ON billing_audit_log FOR ALL USING (false);
