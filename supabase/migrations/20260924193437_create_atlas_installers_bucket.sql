-- P0-3: private bucket for entitlement-gated installer downloads, built
-- alongside the existing public/downloads/ATLAS-latest.dmg — that public
-- file is NOT touched, moved, or deleted by this migration. This bucket is
-- created empty; uploading the actual installer file(s) into it is a
-- separate, explicitly-deferred step (not performed in this pass).
INSERT INTO storage.buckets (id, name, public)
VALUES ('atlas-installers', 'atlas-installers', false)
ON CONFLICT (id) DO NOTHING;