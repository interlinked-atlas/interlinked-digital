-- ATLAS Subscription System Schema
-- Run this in Supabase SQL Editor

-- Subscriptions table
CREATE TABLE IF NOT EXISTS public.subscriptions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  stripe_customer_id TEXT,
  stripe_subscription_id TEXT UNIQUE,
  plan TEXT NOT NULL CHECK (plan IN ('basic', 'pro')),
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'canceled', 'past_due', 'trialing', 'incomplete')),
  current_period_start TIMESTAMPTZ,
  current_period_end TIMESTAMPTZ,
  cancel_at_period_end BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Device activations table
CREATE TABLE IF NOT EXISTS public.device_activations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  machine_uuid TEXT NOT NULL,
  device_name TEXT,
  hardware_hash TEXT,
  activated_at TIMESTAMPTZ DEFAULT NOW(),
  last_seen_at TIMESTAMPTZ DEFAULT NOW(),
  is_active BOOLEAN DEFAULT TRUE,
  UNIQUE(user_id, machine_uuid)
);

-- Install logs table (for Basic plan rate limiting)
CREATE TABLE IF NOT EXISTS public.install_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  device_id UUID REFERENCES public.device_activations(id) ON DELETE SET NULL,
  installed_at TIMESTAMPTZ DEFAULT NOW(),
  app_name TEXT
);

-- Enable RLS
ALTER TABLE public.subscriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.device_activations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.install_logs ENABLE ROW LEVEL SECURITY;

-- RLS Policies for subscriptions
CREATE POLICY "subscriptions_select_own" ON public.subscriptions 
  FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "subscriptions_insert_service" ON public.subscriptions 
  FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "subscriptions_update_service" ON public.subscriptions 
  FOR UPDATE USING (auth.uid() = user_id);

-- RLS Policies for device_activations
CREATE POLICY "devices_select_own" ON public.device_activations 
  FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "devices_insert_own" ON public.device_activations 
  FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "devices_update_own" ON public.device_activations 
  FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY "devices_delete_own" ON public.device_activations 
  FOR DELETE USING (auth.uid() = user_id);

-- RLS Policies for install_logs
CREATE POLICY "installs_select_own" ON public.install_logs 
  FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "installs_insert_own" ON public.install_logs 
  FOR INSERT WITH CHECK (auth.uid() = user_id);

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_subscriptions_user_id ON public.subscriptions(user_id);
CREATE INDEX IF NOT EXISTS idx_subscriptions_stripe_customer ON public.subscriptions(stripe_customer_id);
CREATE INDEX IF NOT EXISTS idx_device_activations_user_id ON public.device_activations(user_id);
CREATE INDEX IF NOT EXISTS idx_install_logs_user_id_time ON public.install_logs(user_id, installed_at DESC);
