-- C1: make the 25-install allowance account-wide instead of per-device.
-- install_counts currently has 0 rows in production (re-verified immediately
-- before this migration) and is keyed (user_id, hardware_uuid) — re-key to
-- user_id alone. hardware_uuid stays on install_reservations as metadata,
-- it just no longer determines the install-limit pool.

ALTER TABLE install_counts DROP CONSTRAINT install_counts_user_device_pkey;
ALTER TABLE install_counts DROP COLUMN hardware_uuid;
ALTER TABLE install_counts ADD CONSTRAINT install_counts_user_pkey PRIMARY KEY (user_id);

-- reserve_install_slot: capacity check + reservation insert now lock and
-- read the single account-level install_counts row (one per user_id), and
-- the active-reservation window counts reservations from ALL of the
-- account's devices, not just the requesting one. Entitlement check,
-- device-registration check, idempotent-retry-by-reservation_id behavior,
-- and the 60-minute active-reservation window are otherwise unchanged.
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
  -- Idempotent on retry: a reservation with this exact id already exists.
  SELECT * INTO v_existing FROM install_reservations WHERE id = p_reservation_id;
  IF FOUND THEN
    RETURN jsonb_build_object('allowed', v_existing.status = 'reserved' OR v_existing.status = 'confirmed', 'status', v_existing.status);
  END IF;

  -- Entitlement authority: subscriptions.status = 'active' is the ONLY thing
  -- that grants install capability. Checked before any device/count logic.
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

  -- Period math only — never entitlement. profiles.billing_interval/
  -- billing_anchor_day are billing-cadence metadata sourced from Stripe.
  SELECT billing_interval, billing_anchor_day INTO v_billing_interval, v_billing_anchor_day
    FROM profiles WHERE id = p_user_id;
  v_period_start := atlas_period_start(v_billing_interval, v_billing_anchor_day, CURRENT_DATE);

  INSERT INTO install_counts (user_id, today_date, installs_today, period_start, installs_this_month)
    VALUES (p_user_id, CURRENT_DATE, 0, v_period_start, 0)
    ON CONFLICT (user_id) DO NOTHING;

  -- Account-level lock: this is the serialization point. Two concurrent
  -- reservation attempts from different devices on the same account both
  -- try to lock THIS SAME row — Postgres grants the lock to exactly one,
  -- blocks the other until the first transaction commits, and the second
  -- then re-reads the post-commit state rather than a stale pre-lock value.
  SELECT * INTO v_row FROM install_counts
    WHERE user_id = p_user_id
    FOR UPDATE;

  IF v_row.period_start < v_period_start THEN
    v_row.installs_this_month := 0;
    v_row.period_start := v_period_start;
    UPDATE install_counts SET installs_this_month = 0, period_start = v_period_start, updated_at = now()
      WHERE user_id = p_user_id;
  END IF;

  v_confirmed := v_row.installs_this_month;

  -- Active reservations from ALL of the account's devices count toward the
  -- same shared pool — no hardware_uuid filter here.
  SELECT count(*) INTO v_active_reservations FROM install_reservations
    WHERE user_id = p_user_id
      AND status = 'reserved' AND created_at > now() - interval '60 minutes';

  IF v_confirmed + v_active_reservations >= v_monthly_limit THEN
    RETURN jsonb_build_object('allowed', false, 'reason', 'monthly_limit',
      'monthly_used', v_confirmed, 'monthly_limit', v_monthly_limit, 'monthly_remaining', 0);
  END IF;

  -- hardware_uuid is retained here as metadata/audit information only — it
  -- does not affect which pool this reservation draws from.
  INSERT INTO install_reservations (id, user_id, hardware_uuid, status)
    VALUES (p_reservation_id, p_user_id, p_hardware_uuid, 'reserved');

  RETURN jsonb_build_object('allowed', true, 'reason', null,
    'monthly_used', v_confirmed, 'monthly_limit', v_monthly_limit,
    'monthly_remaining', v_monthly_limit - v_confirmed - v_active_reservations - 1);
END;
$function$;

-- confirm_install_reservation: increments the single account-level row.
-- Idempotency unchanged — an already-confirmed reservation returns the
-- current state without incrementing again.
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
    SELECT * INTO v_row FROM install_counts WHERE user_id = v_res.user_id;
    RETURN jsonb_build_object('confirmed', true, 'used', v_row.installs_this_month,
      'limit', v_monthly_limit, 'remaining', GREATEST(0, v_monthly_limit - v_row.installs_this_month));
  END IF;

  SELECT billing_interval, billing_anchor_day INTO v_billing_interval, v_billing_anchor_day
    FROM profiles WHERE id = v_res.user_id;
  v_period_start := atlas_period_start(v_billing_interval, v_billing_anchor_day, CURRENT_DATE);

  -- status = 'reserved' -> transition to 'confirmed', increment exactly once.
  SELECT * INTO v_row FROM install_counts
    WHERE user_id = v_res.user_id
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
    WHERE user_id = v_res.user_id;

  UPDATE install_reservations SET status = 'confirmed', updated_at = now()
    WHERE id = p_reservation_id;

  RETURN jsonb_build_object('confirmed', true, 'used', v_row.installs_this_month,
    'limit', v_monthly_limit, 'remaining', GREATEST(0, v_monthly_limit - v_row.installs_this_month));
END;
$function$;
