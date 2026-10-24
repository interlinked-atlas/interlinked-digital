-- Server-side idempotency for install_logs, prepared per the Oct 22 audit
-- finding: the Mac app's retroactive log-catch-up path (syncExistingLogs(),
-- Desktop/ATLAS.Test/ATLAS/Core/InstallLogger.swift) could re-upload a log
-- its own live/immediate upload had already sent, because nothing on the
-- server (or client, before this pass's fix) recorded that the row already
-- existed. The client-side fix (immediate uploads now mark the same sentinel
-- syncExistingLogs() checks) closes the common case; this migration adds a
-- server-side backstop for genuine redelivery (e.g. the app crashing after
-- the server accepted the row but before the client recorded success).
--
-- client_log_id is the Mac app's own on-disk log filename for the four log
-- types that come from a real, timestamped, globally-unique file
-- (install/failed/uninstall/crashed) — already unique per event today, nothing
-- new is generated. It is intentionally nullable: the remaining log_types
-- (confirmed-success, install-failure-guided, install-failure-feedback,
-- install-demo, install-activation, install-warning) use a product name as
-- "filename," which is NOT unique across repeat events for the same product,
-- and are never produced by syncExistingLogs()'s retroactive scan — so they
-- have no duplicate-delivery risk to fix, and must never be constrained by
-- this index. A plain (non-partial) unique constraint would incorrectly
-- collapse legitimate repeat events for those types.
--
-- NOT YET APPLIED TO PRODUCTION — prepared for a separately authorized
-- release step, per instruction. Existing rows are unaffected either way:
-- the column defaults to NULL, which the partial index simply ignores.

ALTER TABLE public.install_logs
  ADD COLUMN IF NOT EXISTS client_log_id text;

CREATE UNIQUE INDEX IF NOT EXISTS install_logs_user_client_log_id_key
  ON public.install_logs (user_id, client_log_id)
  WHERE client_log_id IS NOT NULL;
