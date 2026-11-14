alter table profiles add column if not exists monthly_browser_download_limit integer;

create or replace function report_browser_download(
  p_user_id uuid,
  p_catalog_item_id uuid,
  p_product_name text,
  p_brand text,
  p_link_url text,
  p_hardware_uuid text,
  p_device_name text
) returns jsonb
language plpgsql
security definer
as $$
declare
  v_limit int;
  v_billing_interval text;
  v_billing_anchor_day int;
  v_period_start date;
  v_used int;
  v_next_reset date;
begin
  perform pg_advisory_xact_lock(hashtext(p_user_id::text));

  select billing_interval, billing_anchor_day, monthly_browser_download_limit
    into v_billing_interval, v_billing_anchor_day, v_limit
    from profiles where id = p_user_id;
  v_limit := coalesce(v_limit, 25);
  v_period_start := atlas_period_start(v_billing_interval, v_billing_anchor_day, current_date);
  v_next_reset := atlas_next_period_start(v_billing_interval, v_billing_anchor_day, current_date);

  select count(*) into v_used from atlas_browser_downloads
    where user_id = p_user_id and downloaded_at >= v_period_start;

  if v_used >= v_limit then
    return jsonb_build_object('allowed', false, 'reason', 'monthly_limit',
      'used', v_used, 'limit', v_limit, 'next_reset', v_next_reset);
  end if;

  insert into atlas_browser_downloads (user_id, catalog_item_id, product_name, brand, link_url, hardware_uuid, device_name)
    values (p_user_id, p_catalog_item_id, p_product_name, p_brand, p_link_url, p_hardware_uuid, p_device_name);

  return jsonb_build_object('allowed', true, 'reason', null,
    'used', v_used + 1, 'limit', v_limit, 'next_reset', v_next_reset);
end;
$$;

create or replace function atlas_browser_usage(p_user_id uuid) returns jsonb
language plpgsql
security definer
as $$
declare
  v_limit int;
  v_billing_interval text;
  v_billing_anchor_day int;
  v_period_start date;
  v_used int;
  v_next_reset date;
begin
  select billing_interval, billing_anchor_day, monthly_browser_download_limit
    into v_billing_interval, v_billing_anchor_day, v_limit
    from profiles where id = p_user_id;
  v_limit := coalesce(v_limit, 25);
  v_period_start := atlas_period_start(v_billing_interval, v_billing_anchor_day, current_date);
  v_next_reset := atlas_next_period_start(v_billing_interval, v_billing_anchor_day, current_date);

  select count(*) into v_used from atlas_browser_downloads
    where user_id = p_user_id and downloaded_at >= v_period_start;

  return jsonb_build_object('used', v_used, 'limit', v_limit,
    'remaining', greatest(0, v_limit - v_used), 'next_reset', v_next_reset);
end;
$$;
