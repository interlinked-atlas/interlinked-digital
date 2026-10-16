
CREATE TABLE IF NOT EXISTS public.monthly_install_counts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  period_start date NOT NULL,
  period_end date NOT NULL,
  count integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, period_start)
);

ALTER TABLE public.monthly_install_counts ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can read own monthly counts"
  ON public.monthly_install_counts FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Service role full access"
  ON public.monthly_install_counts FOR ALL
  USING (true)
  WITH CHECK (true);
