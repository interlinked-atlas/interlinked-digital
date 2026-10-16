-- Monthly install-limit reservation architecture.
-- Closes the check-then-install-then-record race identified in investigation:
-- reserve (atomic capacity claim) -> install -> confirm (success) / release (failure).
-- install_counts.installs_this_month keeps its exact existing meaning: confirmed
-- successful installs only. Nothing about that table's existing shape changes.

CREATE TABLE IF NOT EXISTS install_reservations (
  id            uuid PRIMARY KEY,
  user_id       uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  hardware_uuid text NOT NULL,
  status        text NOT NULL CHECK (status IN ('reserved','confirmed','released')),
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_install_reservations_device_active
  ON install_reservations (user_id, hardware_uuid, status, created_at);

ALTER TABLE install_reservations ENABLE ROW LEVEL SECURITY;
CREATE POLICY service_role_only ON install_reservations
  FOR ALL USING (false);

-- Atomic check + claim. Locks the install_counts row for (user_id, hardware_uuid),
-- so the capacity read and the reservation insert happen in one transaction —
-- concurrent reserve calls for the same device fully serialize on this lock.
-- 60-minute freshness window: deliberately above the existing, confirmed 45-minute
-- worst-case install duration (InstallationManager.swift's own watcher deadline),
-- so a legitimately still-running install's reservation is never prematurely
-- excluded from the active count.
CREATE OR REPLACE FUNCTION reserve_install_slot(
  p_user_id uuid, p_hardware_uuid text, p_reservation_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_row install_counts;
  v_monthly_limit int := 25;
  v_month_start date := date_trunc('month', CURRENT_DATE)::date;
  v_existing install_reservations;
  v_confirmed int;
  v_active_reservations int;
BEGIN
  -- Idempotent on retry: a reservation with this exact id already exists.
  SELECT * INTO v_existing FROM install_reservations WHERE id = p_reservation_id;
  IF FOUND THEN
    RETURN jsonb_build_object('allowed', v_existing.status = 'reserved' OR v_existing.status = 'confirmed', 'status', v_existing.status);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM devices WHERE user_id = p_user_id AND hardware_uuid = p_hardware_uuid
  ) THEN
    RETURN jsonb_build_object('allowed', false, 'reason', 'device_not_registered');
  END IF;

  INSERT INTO install_counts (user_id, hardware_uuid, today_date, installs_today, period_start, installs_this_month)
    VALUES (p_user_id, p_hardware_uuid, CURRENT_DATE, 0, v_month_start, 0)
    ON CONFLICT (user_id, hardware_uuid) DO NOTHING;

  SELECT * INTO v_row FROM install_counts
    WHERE user_id = p_user_id AND hardware_uuid = p_hardware_uuid
    FOR UPDATE;

  IF v_row.period_start < v_month_start THEN
    v_row.installs_this_month := 0;
    v_row.period_start := v_month_start;
    UPDATE install_counts SET installs_this_month = 0, period_start = v_month_start, updated_at = now()
      WHERE user_id = p_user_id AND hardware_uuid = p_hardware_uuid;
  END IF;

  v_confirmed := v_row.installs_this_month;

  SELECT count(*) INTO v_active_reservations FROM install_reservations
    WHERE user_id = p_user_id AND hardware_uuid = p_hardware_uuid
      AND status = 'reserved' AND created_at > now() - interval '60 minutes';

  IF v_confirmed + v_active_reservations >= v_monthly_limit THEN
    RETURN jsonb_build_object('allowed', false, 'reason', 'monthly_limit',
      'monthly_used', v_confirmed, 'monthly_limit', v_monthly_limit, 'monthly_remaining', 0);
  END IF;

  INSERT INTO install_reservations (id, user_id, hardware_uuid, status)
    VALUES (p_reservation_id, p_user_id, p_hardware_uuid, 'reserved');

  RETURN jsonb_build_object('allowed', true, 'reason', null,
    'monthly_used', v_confirmed, 'monthly_limit', v_monthly_limit,
    'monthly_remaining', v_monthly_limit - v_confirmed - v_active_reservations - 1);
END;
$$;

-- The ONLY function that increments installs_this_month. Only transitions
-- reserved -> confirmed. Already-confirmed is a harmless no-op returning the
-- same result (idempotent against retries/duplicate requests). released -> confirm
-- is explicitly rejected — a released attempt can never later become a success.
CREATE OR REPLACE FUNCTION confirm_install_reservation(p_reservation_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_res install_reservations;
  v_row install_counts;
  v_monthly_limit int := 25;
  v_month_start date := date_trunc('month', CURRENT_DATE)::date;
BEGIN
  SELECT * INTO v_res FROM install_reservations WHERE id = p_reservation_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('confirmed', false, 'reason', 'reservation_not_found');
  END IF;

  IF v_res.status = 'released' THEN
    RETURN jsonb_build_object('confirmed', false, 'reason', 'reservation_released');
  END IF;

  IF v_res.status = 'confirmed' THEN
    SELECT * INTO v_row FROM install_counts
      WHERE user_id = v_res.user_id AND hardware_uuid = v_res.hardware_uuid;
    RETURN jsonb_build_object('confirmed', true, 'used', v_row.installs_this_month,
      'limit', v_monthly_limit, 'remaining', GREATEST(0, v_monthly_limit - v_row.installs_this_month));
  END IF;

  -- status = 'reserved' -> transition to 'confirmed', increment exactly once.
  SELECT * INTO v_row FROM install_counts
    WHERE user_id = v_res.user_id AND hardware_uuid = v_res.hardware_uuid
    FOR UPDATE;

  IF v_row.period_start < v_month_start THEN
    v_row.installs_this_month := 0;
    v_row.period_start := v_month_start;
  END IF;
  v_row.installs_this_month := v_row.installs_this_month + 1;

  UPDATE install_counts SET
    installs_this_month = v_row.installs_this_month,
    period_start = v_row.period_start,
    updated_at = now()
    WHERE user_id = v_res.user_id AND hardware_uuid = v_res.hardware_uuid;

  UPDATE install_reservations SET status = 'confirmed', updated_at = now()
    WHERE id = p_reservation_id;

  RETURN jsonb_build_object('confirmed', true, 'used', v_row.installs_this_month,
    'limit', v_monthly_limit, 'remaining', GREATEST(0, v_monthly_limit - v_row.installs_this_month));
END;
$$;

-- Frees a reservation without incrementing anything. confirmed -> release is
-- explicitly rejected — a genuine confirmed success can never be undone this way.
-- released -> released is a harmless no-op.
CREATE OR REPLACE FUNCTION release_install_reservation(p_reservation_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_res install_reservations;
BEGIN
  SELECT * INTO v_res FROM install_reservations WHERE id = p_reservation_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('released', false, 'reason', 'reservation_not_found');
  END IF;

  IF v_res.status = 'confirmed' THEN
    RETURN jsonb_build_object('released', false, 'reason', 'already_confirmed');
  END IF;

  UPDATE install_reservations SET status = 'released', updated_at = now()
    WHERE id = p_reservation_id AND status != 'confirmed';

  RETURN jsonb_build_object('released', true);
END;
$$;
