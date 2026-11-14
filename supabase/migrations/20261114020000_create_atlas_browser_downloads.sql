create table atlas_browser_downloads (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id),
  catalog_item_id uuid references atlas_catalog(id) on delete set null,
  product_name text not null,
  brand text,
  link_url text,
  hardware_uuid text,
  device_name text,
  downloaded_at timestamptz not null default now()
);
create index on atlas_browser_downloads (user_id);
create index on atlas_browser_downloads (catalog_item_id);
