
-- Fix subscriptions.plan CHECK to allow 'standard' (ATLAS uses standard/pro, not basic/pro)
ALTER TABLE public.subscriptions DROP CONSTRAINT IF EXISTS subscriptions_plan_check;
ALTER TABLE public.subscriptions ADD CONSTRAINT subscriptions_plan_check
  CHECK (plan IN ('standard', 'pro', 'basic'));

-- Remove fake seed log entries (identified by TEST-UUID hardware IDs)
DELETE FROM public.install_logs
WHERE hardware_uuid LIKE 'TEST-%'
   OR hardware_uuid IS NULL AND app_name = 'RLS Test App';

-- Add index on installed_at for faster account page queries
CREATE INDEX IF NOT EXISTS idx_install_logs_installed_at
  ON public.install_logs (user_id, installed_at DESC);

-- Ensure service role can insert logs (bypass RLS for the /api/atlas/logs route)
-- Policy already exists via service role key, but add explicit grant for completeness
GRANT INSERT ON public.install_logs TO service_role;
GRANT SELECT ON public.install_logs TO service_role;
