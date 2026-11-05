-- Close the VM-churn loophole: register a device, burn its 25-install
-- allowance, delete it, register a fresh device (e.g. a new VM with its own
-- hardware_uuid) to get another fresh allowance, repeat. A device's
-- install_counts row is never deleted/reset on de-registration (by design,
-- confirmed elsewhere), but nothing previously stopped a brand-new
-- hardware_uuid from simply taking the freed slot immediately.
--
-- Fix: passively log every device removal via a trigger (no app code calls
-- this directly — it fires on any DELETE from devices, including the
-- existing direct-REST-DELETE paths in the website and Mac app), then have
-- register_device block a NEVER-BEFORE-SEEN hardware_uuid for 24 hours after
-- the account's most recent device removal. Re-registering a hardware_uuid
-- the account has already had (i.e. a genuine returning device) is never
-- blocked — only unfamiliar ones during the cooldown window.

CREATE TABLE IF NOT EXISTS device_removals (
  id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id       uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  hardware_uuid text NOT NULL,
  removed_at    timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_device_removals_user_recent
  ON device_removals (user_id, removed_at);

ALTER TABLE device_removals ENABLE ROW LEVEL SECURITY;
CREATE POLICY service_role_only ON device_removals FOR ALL USING (false);

CREATE OR REPLACE FUNCTION public.log_device_removal()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
BEGIN
  INSERT INTO device_removals (user_id, hardware_uuid)
    VALUES (OLD.user_id, OLD.hardware_uuid);
  RETURN OLD;
END;
$function$;

DROP TRIGGER IF EXISTS trg_log_device_removal ON devices;
CREATE TRIGGER trg_log_device_removal
  AFTER DELETE ON devices
  FOR EACH ROW EXECUTE FUNCTION public.log_device_removal();

-- register_device: identical to the existing version, with one added check
-- between the idempotent-existing-device path and the device-limit count.
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
  v_recent_removal timestamptz;
  v_had_before boolean;
BEGIN
  SELECT EXISTS (
    SELECT 1 FROM subscriptions WHERE user_id = p_user_id AND status = 'active'
  ) INTO v_is_entitled;

  IF NOT v_is_entitled THEN
    RETURN jsonb_build_object('allowed', false, 'reason', 'not_entitled');
  END IF;

  SELECT * INTO v_existing FROM devices
    WHERE user_id = p_user_id AND hardware_uuid = p_hardware_uuid
    FOR UPDATE;

  IF FOUND THEN
    UPDATE devices SET device_name = p_device_name, last_seen = now()
      WHERE user_id = p_user_id AND hardware_uuid = p_hardware_uuid;
    RETURN jsonb_build_object('allowed', true, 'already_registered', true);
  END IF;

  -- Cooldown only applies to a hardware_uuid this account has genuinely
  -- never had before. Taking back a device you JUST removed yourself (e.g.
  -- you deleted it by mistake, or you're reinstalling on the same Mac) is
  -- never blocked, no matter how recently it was removed — only an
  -- unfamiliar hardware_uuid showing up within 24h of ANY removal on this
  -- account is treated as possible VM-churn and held back.
  SELECT EXISTS (
    SELECT 1 FROM device_removals
      WHERE user_id = p_user_id AND hardware_uuid = p_hardware_uuid
  ) INTO v_had_before;

  IF NOT v_had_before THEN
    SELECT max(removed_at) INTO v_recent_removal
      FROM device_removals WHERE user_id = p_user_id;

    IF v_recent_removal IS NOT NULL AND v_recent_removal > now() - interval '24 hours' THEN
      RETURN jsonb_build_object(
        'allowed', false, 'reason', 'device_slot_cooldown',
        'retry_after', v_recent_removal + interval '24 hours'
      );
    END IF;
  END IF;

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
