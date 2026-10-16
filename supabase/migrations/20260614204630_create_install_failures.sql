
create table if not exists install_failures (
  id                  uuid primary key default gen_random_uuid(),
  user_id             uuid references auth.users(id) on delete set null,
  product_name        text not null,
  source_filename     text not null,
  failure_reason      text,
  failure_step        text,
  failure_type        text,   -- 'pkg' | 'script' | 'binary' | 'verify' | 'demo' | 'unknown'
  steps_attempted     text[], -- ordered list of step labels attempted
  error_output        text,   -- raw stderr / exception text
  install_log         text,   -- full ATLAS install log
  device_name         text,
  hardware_uuid       text,
  macos_version       text,
  support_ticket_id   uuid references support_tickets(id) on delete set null,
  admin_note          text,   -- admin writes fix notes here
  admin_fix_status    text default 'open',  -- 'open' | 'investigating' | 'fixed' | 'wont_fix'
  pattern_id          uuid references install_patterns(id) on delete set null,
  created_at          timestamptz not null default now()
);

create index if not exists install_failures_product_name_idx on install_failures (product_name);
create index if not exists install_failures_admin_fix_status_idx on install_failures (admin_fix_status);
create index if not exists install_failures_created_at_idx on install_failures (created_at desc);

alter table install_failures enable row level security;

-- Users can insert their own failures, read their own
create policy "Users can insert own failures"
  on install_failures for insert to authenticated
  with check (auth.uid() = user_id);

create policy "Users can read own failures"
  on install_failures for select to authenticated
  using (auth.uid() = user_id);
