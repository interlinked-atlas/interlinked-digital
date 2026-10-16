-- Step 2: split check-and-increment into a read-only check and an atomic, success-only
-- increment, both keyed by (user_id, hardware_uuid), monthly limit flat 25 for all plans,
-- period is always a calendar month regardless of billing_interval/plan.
-- The old check_and_increment_install RPC is left untouched and unused by the new client
-- code path once the app is updated; it is not dropped here.

-- Read-only pre-flight check. Does NOT mutate install_counts.
-- Verifies hardware_uuid is a device actually registered to this user before trusting it.
CREATE OR REPLACE FUNCTION check_install_allowed(p_user_id uuid, p_hardware_uuid text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_row install_counts;
  v_monthly_limit int := 25;
  v_month_start date := date_trunc('month', CURRENT_DATE)::date;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM devices
    WHERE user_id = p_user_id AND hardware_uuid = p_hardware_uuid
  ) THEN
    RETURN jsonb_build_object('allowed', false, 'reason', 'device_not_registered');
  END IF;

  SELECT * INTO v_row FROM install_counts
    WHERE user_id = p_user_id AND hardware_uuid = p_hardware_uuid;

  IF NOT FOUND OR v_row.period_start < v_month_start THEN
    RETURN jsonb_build_object(
      'allowed', true, 'reason', null,
      'monthly_used', 0, 'monthly_limit', v_monthly_limit,
      'monthly_remaining', v_monthly_limit
    );
  END IF;

  IF v_row.installs_this_month >= v_monthly_limit THEN
    RETURN jsonb_build_object(
      'allowed', false, 'reason', 'monthly_limit',
      'monthly_used', v_row.installs_this_month, 'monthly_limit', v_monthly_limit,
      'monthly_remaining', 0
    );
  END IF;

  RETURN jsonb_build_object(
    'allowed', true, 'reason', null,
    'monthly_used', v_row.installs_this_month, 'monthly_limit', v_monthly_limit,
    'monthly_remaining', v_monthly_limit - v_row.installs_this_month
  );
END;
$$;

-- Atomic success-only increment. The ONLY function that mutates install_counts usage.
-- p_count lets a multi-product mission record N successful products in one atomic call.
-- Row-locked (FOR UPDATE) exactly like the original RPC, extended to the device-scoped key,
-- so concurrent calls for the same (user_id, hardware_uuid) cannot overshoot the limit.
CREATE OR REPLACE FUNCTION record_successful_install(p_user_id uuid, p_hardware_uuid text, p_count int DEFAULT 1)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_row install_counts;
  v_monthly_limit int := 25;
  v_month_start date := date_trunc('month', CURRENT_DATE)::date;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM devices
    WHERE user_id = p_user_id AND hardware_uuid = p_hardware_uuid
  ) THEN
    RETURN jsonb_build_object('recorded', false, 'reason', 'device_not_registered');
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
  END IF;
  IF v_row.today_date < CURRENT_DATE THEN
    v_row.installs_today := 0;
    v_row.today_date := CURRENT_DATE;
  END IF;

  v_row.installs_this_month := v_row.installs_this_month + p_count;
  v_row.installs_today := v_row.installs_today + p_count;

  UPDATE install_counts SET
    installs_this_month = v_row.installs_this_month,
    period_start = v_row.period_start,
    installs_today = v_row.installs_today,
    today_date = v_row.today_date,
    updated_at = now()
  WHERE user_id = p_user_id AND hardware_uuid = p_hardware_uuid;

  RETURN jsonb_build_object(
    'recorded', true,
    'monthly_used', v_row.installs_this_month, 'monthly_limit', v_monthly_limit,
    'monthly_remaining', GREATEST(0, v_monthly_limit - v_row.installs_this_month)
  );
END;
$$;
