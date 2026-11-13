create table if not exists atlas_settings (
  key text primary key,
  value text not null,
  updated_at timestamptz default now()
);

alter table atlas_settings enable row level security;

create policy atlas_settings_public_read on atlas_settings
  for select using (true);

insert into atlas_settings (key, value) values ('browser_maintenance', 'false')
  on conflict (key) do nothing;
