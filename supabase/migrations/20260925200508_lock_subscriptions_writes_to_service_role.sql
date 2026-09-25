
DROP POLICY IF EXISTS "subscriptions_insert_service" ON public.subscriptions;
DROP POLICY IF EXISTS "subscriptions_update_service" ON public.subscriptions;

CREATE POLICY "subscriptions_insert_service" ON public.subscriptions
  FOR INSERT
  TO service_role
  WITH CHECK (true);

CREATE POLICY "subscriptions_update_service" ON public.subscriptions
  FOR UPDATE
  TO service_role
  USING (true)
  WITH CHECK (true);
