create table if not exists atlas_catalog (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  brand text,
  category text not null,
  platform text not null,
  image_url text,
  external_url text,
  sort_order int default 0,
  created_at timestamptz default now()
);

create index if not exists atlas_catalog_category_idx on atlas_catalog (category);
create index if not exists atlas_catalog_platform_idx on atlas_catalog (platform);

alter table atlas_catalog enable row level security;

-- Public read: the catalog is marketing content, not user data — anyone
-- (including the unauthenticated app endpoint) can read it. All writes go
-- through the service-role admin API route, which bypasses RLS entirely.
create policy "atlas_catalog_public_read" on atlas_catalog
  for select using (true);
