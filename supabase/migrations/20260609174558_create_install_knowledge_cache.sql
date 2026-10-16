
create table if not exists install_knowledge (
  id           uuid primary key default gen_random_uuid(),
  product_key  text not null unique,
  source_name  text,
  source_url   text,
  steps        jsonb,
  hosts_entries jsonb,
  mentions_rosetta    boolean default false,
  requires_admin      boolean default false,
  mentions_select_all boolean default false,
  app_to_launch       text,
  known_issues        jsonb,
  notes               text,
  confidence          float default 0.5,
  created_at   timestamptz default now(),
  expires_at   timestamptz default (now() + interval '7 days')
);

create index if not exists install_knowledge_product_key_idx on install_knowledge(product_key);
create index if not exists install_knowledge_expires_at_idx  on install_knowledge(expires_at);
