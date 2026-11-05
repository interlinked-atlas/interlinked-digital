-- Per-IP / per-email rate limiting for public, unauthenticated routes
-- (waitlist, signup, login, send-code, verify-code). Purely additive:
-- new table, new function, touches nothing existing. Atomic via row
-- locking, same pattern as reserve_install_slot.

CREATE TABLE IF NOT EXISTS rate_limit_attempts (
  rl_key        text NOT NULL,
  route         text NOT NULL,
  window_start  timestamptz NOT NULL,
  count         int NOT NULL DEFAULT 0,
  updated_at    timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (rl_key, route, window_start)
);

CREATE INDEX IF NOT EXISTS idx_rate_limit_attempts_lookup
  ON rate_limit_attempts (rl_key, route, window_start);

ALTER TABLE rate_limit_attempts ENABLE ROW LEVEL SECURITY;
CREATE POLICY service_role_only ON rate_limit_attempts
  FOR ALL USING (false);

-- Buckets requests into fixed windows keyed by floor(now()/window) so
-- concurrent callers for the same (key, route) serialize on one row via
-- the UPSERT + lock, rather than racing across separate rows.
CREATE OR REPLACE FUNCTION check_rate_limit(
  p_key text, p_route text, p_max int, p_window_seconds int
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_window_start timestamptz;
  v_row rate_limit_attempts;
BEGIN
  v_window_start := to_timestamp(floor(extract(epoch FROM now()) / p_window_seconds) * p_window_seconds);

  INSERT INTO rate_limit_attempts (rl_key, route, window_start, count)
    VALUES (p_key, p_route, v_window_start, 0)
    ON CONFLICT (rl_key, route, window_start) DO NOTHING;

  SELECT * INTO v_row FROM rate_limit_attempts
    WHERE rl_key = p_key AND route = p_route AND window_start = v_window_start
    FOR UPDATE;

  IF v_row.count >= p_max THEN
    RETURN false;
  END IF;

  UPDATE rate_limit_attempts SET count = count + 1, updated_at = now()
    WHERE rl_key = p_key AND route = p_route AND window_start = v_window_start;

  RETURN true;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.check_rate_limit(text, text, int, int) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.check_rate_limit(text, text, int, int) TO service_role;
