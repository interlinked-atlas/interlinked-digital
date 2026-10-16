-- P0-1 (install path): reserve_install_slot must reject any user without an
-- active ATLAS subscription BEFORE touching device checks, counts, or
-- reservations — entitlement is checked first, then capacity.
CREATE OR REPLACE FUNCTION public.reserve_install_slot(p_user_id uuid, p_hardware_uuid text, p_reservation_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_row install_counts;
  v_monthly_limit int := 25;
  v_month_start date := date_trunc('month', CURRENT_DATE)::date;
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
$function$;