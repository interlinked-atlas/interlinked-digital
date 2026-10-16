
-- Add target device column: null = visible to all devices on the account
ALTER TABLE shared_files ADD COLUMN IF NOT EXISTS target_device_id TEXT DEFAULT NULL;

-- Index for fast per-device lookups
CREATE INDEX IF NOT EXISTS idx_shared_files_target_device ON shared_files(user_id, target_device_id);
