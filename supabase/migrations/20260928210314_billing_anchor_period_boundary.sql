-- Server-authoritative install-period boundaries, replacing the flat
-- date_trunc('month', CURRENT_DATE) reset that ignored billing cadence.
--
-- Product rule:
--   monthly subscribers  -> resets on their billing_anchor_day each month,
--                           clamped to the last valid day of a short month
--                           (anchor 31 -> Feb 28/29, Apr 30, etc.)
--   annual subscribers   -> resets on the 1st of every calendar month
--
-- reserve_install_slot and confirm_install_reservation both call the same
-- atlas_period_start() so there is exactly one period-boundary calculation,
-- not two competing ones. Entitlement (subscriptions.status) is untouched —
-- these functions only read profiles.billing_interval/billing_anchor_day for
-- period math, never for entitlement.

CREATE OR REPLACE FUNCTION public.atlas_clamp_day(p_year int, p_month int, p_day int)
 RETURNS date
 LANGUAGE sql
AS $function$
  SELECT make_date(
    p_year, p_month,
    LEAST(p_day, EXTRACT(DAY FROM (make_date(p_year, p_month, 1) + interval '1 month - 1 day'))::int)
  );
$function$;

CREATE OR REPLACE FUNCTION public.atlas_period_start(
  p_billing_interval text,
  p_billing_anchor_day int,
  p_as_of date DEFAULT CURRENT_DATE
)
 RETURNS date
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_anchor     int := COALESCE(p_billing_anchor_day, 1);
  v_this_month date;
  v_prev_month date;
BEGIN
  IF p_billing_interval = 'annual' THEN
    RETURN date_trunc('month', p_as_of)::date;
  END IF;

  -- 'monthly' and any null/unrecognized value default to the monthly,
  -- anchor-day rule (matches the prior behavior's bias toward monthly).
  v_this_month := atlas_clamp_day(EXTRACT(YEAR FROM p_as_of)::int, EXTRACT(MONTH FROM p_as_of)::int, v_anchor);
  IF v_this_month <= p_as_of THEN
    RETURN v_this_month;
  END IF;

  v_prev_month := (date_trunc('month', p_as_of) - interval '1 month')::date;
  RETURN atlas_clamp_day(EXTRACT(YEAR FROM v_prev_month)::int, EXTRACT(MONTH FROM v_prev_month)::int, v_anchor);
END;
$function$;

CREATE OR REPLACE FUNCTION public.atlas_next_period_start(
  p_billing_interval text,
  p_billing_anchor_day int,
  p_as_of date DEFAULT CURRENT_DATE
)
 RETURNS date
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_anchor        int := COALESCE(p_billing_anchor_day, 1);
  v_current_start date;
  v_next_month    date;
BEGIN
  v_current_start := atlas_period_start(p_billing_interval, p_billing_anchor_day, p_as_of);

  IF p_billing_interval = 'annual' THEN
    RETURN (v_current_start + interval '1 month')::date;
  END IF;

  v_next_month := (date_trunc('month', v_current_start) + interval '1 month')::date;
  RETURN atlas_clamp_day(EXTRACT(YEAR FROM v_next_month)::int, EXTRACT(MONTH FROM v_next_month)::int, v_anchor);
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.atlas_clamp_day(int, int, int) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.atlas_period_start(text, int, date) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.atlas_next_period_start(text, int, date) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.atlas_clamp_day(int, int, int) TO service_role;
GRANT EXECUTE ON FUNCTION public.atlas_period_start(text, int, date) TO service_role;
GRANT EXECUTE ON FUNCTION public.atlas_next_period_start(text, int, date) TO service_role;

-- reserve_install_slot: identical to the current version except the period
-- boundary is now atlas_period_start(profile.billing_interval,
-- profile.billing_anchor_day) instead of a flat date_trunc('month', ...).
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

-- confirm_install_reservation: identical to the current version except the
-- period boundary is now atlas_period_start(...) instead of a flat
-- date_trunc('month', ...), matching reserve_install_slot exactly.
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

  -- status = 'reserved' -> transition to 'confirmed', increment exactly once.
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
