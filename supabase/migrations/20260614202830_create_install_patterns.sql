
create table if not exists install_patterns (
  id                uuid primary key default gen_random_uuid(),
  product_name      text not null,
  match_patterns    text[] not null default '{}',
  pkg_receipt_ids   text[] not null default '{}',
  installed_paths   text[] not null default '{}',
  hosts_entries     text[] not null default '{}',
  success_count     integer not null default 1,
  contributed_by    uuid references auth.users(id) on delete set null,
  last_confirmed_at timestamptz not null default now(),
  last_device_name  text,
  hardware_uuid     text,
  created_at        timestamptz not null default now()
);

-- Index for fast pattern matching queries
create index if not exists install_patterns_product_name_idx
  on install_patterns using gin (to_tsvector('english', product_name));

create index if not exists install_patterns_success_count_idx
  on install_patterns (success_count desc);

-- RLS: any authenticated user can read all patterns (shared knowledge base)
-- Only the server-side API (service role) can insert/update
alter table install_patterns enable row level security;

create policy "Authenticated users can read patterns"
  on install_patterns for select
  to authenticated
  using (true);
