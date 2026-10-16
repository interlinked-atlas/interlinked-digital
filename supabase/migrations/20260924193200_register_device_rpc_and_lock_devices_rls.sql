-- P0-4: atomic, entitlement-gated, server-authoritative device registration.
-- SECURITY: this function is NOT safe to expose to arbitrary authenticated
-- clients directly — p_user_id must be derived and verified server-side
-- (from a Supabase-verified access token) by the calling API route, never
-- taken from client-supplied request fields. EXECUTE is revoked from
-- anon/authenticated below so it can only be invoked with the service-role
-- key, i.e. only via the trusted server route.
CREATE OR REPLACE FUNCTION public.register_device(
  p_user_id uuid,
  p_hardware_uuid text,
  p_device_name text
)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_is_entitled boolean;
  v_existing devices;
  v_count int;
  v_limit int := 3;
BEGIN
  SELECT EXISTS (
    SELECT 1 FROM subscriptions WHERE user_id = p_user_id AND status = 'active'
  ) INTO v_is_entitled;

  IF NOT v_is_entitled THEN
    RETURN jsonb_build_object('allowed', false, 'reason', 'not_entitled');
  END IF;

  -- Idempotent: an already-registered device just refreshes last_seen/name
  -- and never counts against the limit a second time.
  SELECT * INTO v_existing FROM devices
    WHERE user_id = p_user_id AND hardware_uuid = p_hardware_uuid
    FOR UPDATE;

  IF FOUND THEN
    UPDATE devices SET device_name = p_device_name, last_seen = now()
      WHERE user_id = p_user_id AND hardware_uuid = p_hardware_uuid;
    RETURN jsonb_build_object('allowed', true, 'already_registered', true);
  END IF;

  -- Lock this user's device rows for the duration of the count+insert so two
  -- simultaneous registrations can't both observe count=2 and both insert.
  PERFORM 1 FROM devices WHERE user_id = p_user_id FOR UPDATE;

  SELECT count(*) INTO v_count FROM devices WHERE user_id = p_user_id;

  IF v_count >= v_limit THEN
    RETURN jsonb_build_object('allowed', false, 'reason', 'device_limit', 'device_count', v_count, 'device_limit', v_limit);
  END IF;

  INSERT INTO devices (user_id, hardware_uuid, device_name, last_seen)
    VALUES (p_user_id, p_hardware_uuid, p_device_name, now());

  RETURN jsonb_build_object('allowed', true, 'already_registered', false, 'device_count', v_count + 1, 'device_limit', v_limit);
END;
$function$;

-- Lock down EXECUTE: only the service role (i.e. only our trusted API route
-- using SUPABASE_SERVICE_ROLE_KEY) may call this — not a normal client with
-- its own user access token, so no client can invoke it with a spoofed
-- p_user_id, and no client can call it at all outside the verified route.
REVOKE EXECUTE ON FUNCTION public.register_device(uuid, text, text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.register_device(uuid, text, text) FROM anon;
REVOKE EXECUTE ON FUNCTION public.register_device(uuid, text, text) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.register_device(uuid, text, text) TO service_role;

-- Close the direct-REST-insert bypass: only the RPC above (via service role)
-- may create device rows now. Read/delete/update by the owning user remain
-- unchanged.
DROP POLICY IF EXISTS "own devices insert" ON public.devices;