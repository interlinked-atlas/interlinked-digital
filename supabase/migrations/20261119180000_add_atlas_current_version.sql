-- The ATLAS client's actually-running version, reported on every live-sync
-- poll (POST /api/atlas/install-status). Distinct from atlas_forced_update_version,
-- which is what an admin is pushing a client to, not what it's on.
alter table profiles add column if not exists atlas_current_version text;
