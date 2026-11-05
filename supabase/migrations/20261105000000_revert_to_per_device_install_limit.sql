-- Revert the 25-install limit from account-wide (Oct 7, c1_account_wide_install_counts.sql)
-- back to per-device. Product decision 2026-11-05: 25 installs is now a per-device
-- allowance, not a shared account-wide pool. install_counts is confirmed to have 0 live
-- rows at the time of this migration, so no data migration/reset is needed.
--
-- reserve_install_slot / confirm_install_reservation are restored to their
-- 20260928210314_billing_anchor_period_boundary.sql bodies verbatim — that version
-- already combines per-(user_id, hardware_uuid) scoping with the billing-anchor-aware
-- period reset, which stays unchanged here. release_install_reservation never touched
-- install_counts and needs no change.

ALTER TABLE install_counts ADD COLUMN IF NOT EXISTS hardware_uuid text;
UPDATE install_counts SET hardware_uuid = 'unknown' WHERE hardware_uuid IS NULL;
ALTER TABLE install_counts ALTER COLUMN hardware_uuid SET NOT NULL;
ALTER TABLE install_counts DROP CONSTRAINT IF EXISTS install_counts_user_pkey;
ALTER TABLE install_counts ADD CONSTRAINT install_counts_user_device_pkey PRIMARY KEY (user_id, hardware_uuid);

CREATE OR REPLACE FUNCTION public.reserve_install_slot(p_user_id uuid, p_hardware_uuid text, p_reservation_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_row install_counts;
  v_monthly_limit int := 25;
  v_billing_interval text;
  v_billing_anchor_day int;
  v_period_start date;
  v_existing install_reservations;
  v_confirmed int;
  v_active_reservations int;
  v_is_entitled boolean;
BEGIN
  SELECT * INTO v_existing FROM install_reservations WHERE id = p_reservation_id;
  IF FOUND THEN
    RETURN jsonb_build_object('allowed', v_existing.status = 'reserved' OR v_existing.status = 'confirmed', 'status', v_existing.status);
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM subscriptions WHERE user_id = p_user_id AND status = 'active'
  ) INTO v_is_entitled;

  IF NOT v_is_entitled THEN
    RETURN jsonb_build_object('allowed', false, 'reason', 'not_entitled');
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM devices WHERE user_id = p_user_id AND hardware_uuid = p_hardware_uuid
  ) THEN
    RETURN jsonb_build_object('allowed', false, 'reason', 'device_not_registered');
  END IF;

  SELECT billing_interval, billing_anchor_day INTO v_billing_interval, v_billing_anchor_day
    FROM profiles WHERE id = p_user_id;
  v_period_start := atlas_period_start(v_billing_interval, v_billing_anchor_day, CURRENT_DATE);

  INSERT INTO install_counts (user_id, hardware_uuid, today_date, installs_today, period_start, installs_this_month)
    VALUES (p_user_id, p_hardware_uuid, CURRENT_DATE, 0, v_period_start, 0)
    ON CONFLICT (user_id, hardware_uuid) DO NOTHING;

  SELECT * INTO v_row FROM install_counts
    WHERE user_id = p_user_id AND hardware_uuid = p_hardware_uuid
    FOR UPDATE;

  IF v_row.period_start < v_period_start THEN
    v_row.installs_this_month := 0;
    v_row.period_start := v_period_start;
    UPDATE install_counts SET installs_this_month = 0, period_start = v_period_start, updated_at = now()
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
$function$;

CREATE OR REPLACE FUNCTION public.confirm_install_reservation(p_reservation_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_res install_reservations;
  v_row install_counts;
  v_monthly_limit int := 25;
  v_billing_interval text;
  v_billing_anchor_day int;
  v_period_start date;
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

  SELECT billing_interval, billing_anchor_day INTO v_billing_interval, v_billing_anchor_day
    FROM profiles WHERE id = v_res.user_id;
  v_period_start := atlas_period_start(v_billing_interval, v_billing_anchor_day, CURRENT_DATE);

  SELECT * INTO v_row FROM install_counts
    WHERE user_id = v_res.user_id AND hardware_uuid = v_res.hardware_uuid
    FOR UPDATE;

  IF v_row.period_start < v_period_start THEN
    v_row.installs_this_month := 0;
    v_row.period_start := v_period_start;
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
$function$;
