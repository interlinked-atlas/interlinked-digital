-- Step 1 of the monthly-install-limit rework: add per-device dimension to install_counts.
-- Approved migration decision: reset existing counts to 0 rather than attribute historical
-- usage to an arbitrary device. Nothing else in the codebase references install_counts
-- besides check_and_increment_install (confirmed via information_schema query), which is
-- left in place, untouched, until the new RPCs below are wired up and verified.

ALTER TABLE install_counts ADD COLUMN IF NOT EXISTS hardware_uuid text;

-- Reset per approved decision: old rows carry no device attribution and cannot be
-- correctly migrated, so usage starts fresh under the new (user_id, hardware_uuid) key.
DELETE FROM install_counts;

ALTER TABLE install_counts ALTER COLUMN hardware_uuid SET NOT NULL;
ALTER TABLE install_counts DROP CONSTRAINT install_counts_pkey;
ALTER TABLE install_counts ADD CONSTRAINT install_counts_user_device_pkey PRIMARY KEY (user_id, hardware_uuid);
