
CREATE TABLE IF NOT EXISTS atlas_waitlist (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  email       TEXT NOT NULL UNIQUE,
  signed_up_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE atlas_waitlist ENABLE ROW LEVEL SECURITY;

CREATE POLICY "service role only" ON atlas_waitlist
  USING (false)
  WITH CHECK (false);
