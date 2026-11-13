alter table atlas_catalog
  add column if not exists description text,
  add column if not exists file_size text,
  add column if not exists specs text;
