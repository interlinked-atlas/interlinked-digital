insert into storage.buckets (id, name, public)
values ('atlas-catalog-images', 'atlas-catalog-images', true)
on conflict (id) do nothing;

-- Public read (these are marketing thumbnails, not entitlement-gated
-- content — deliberate difference from every other bucket in this project,
-- which are private + signed-URL). Writes stay service-role only, same as
-- the admin catalog API route that will manage them.
create policy "atlas_catalog_images_public_read" on storage.objects
  for select using (bucket_id = 'atlas-catalog-images');
