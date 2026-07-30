import { NextRequest, NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
)

export async function POST(req: NextRequest) {
  const token = req.headers.get('authorization')?.replace('Bearer ', '').trim()
  if (!token) return NextResponse.json({ error: 'Missing authorization' }, { status: 401 })

  const { data: { user }, error: authError } = await supabase.auth.getUser(token)
  if (authError || !user) return NextResponse.json({ error: 'Invalid token' }, { status: 401 })

  let body: Record<string, unknown>
  try { body = await req.json() }
  catch { return NextResponse.json({ error: 'Invalid JSON' }, { status: 400 }) }

  const {
    product_name, match_patterns, pkg_receipt_ids,
    installed_paths, hosts_entries, device_name, hardware_uuid
  } = body as Record<string, unknown>

  if (!product_name || !Array.isArray(match_patterns) || match_patterns.length === 0) {
    return NextResponse.json({ error: 'Missing required fields' }, { status: 400 })
  }

  // Upsert: if this product already exists (by name match), increment success_count.
  // Otherwise insert a new entry.
  const { data: existing } = await supabase
    .from('install_patterns')
    .select('id, success_count, match_patterns, installed_paths, hosts_entries, device_uuids')
    .ilike('product_name', product_name as string)
    .maybeSingle()

  if (existing) {
    // Merge new match patterns + installed paths with existing ones (deduplicate)
    const mergedPatterns = Array.from(new Set([
      ...(existing.match_patterns ?? []),
      ...(match_patterns as string[])
    ]))
    const mergedPaths = Array.from(new Set([
      ...(existing.installed_paths ?? []),
      ...((installed_paths as string[]) ?? [])
    ]))
    const mergedHosts = Array.from(new Set([
      ...(existing.hosts_entries ?? []),
      ...((hosts_entries as string[]) ?? [])
    ]))
    const mergedDevices = Array.from(new Set([
      ...(existing.device_uuids ?? []),
      ...((hardware_uuid as string) ? [hardware_uuid as string] : [])
    ]))

    await supabase
      .from('install_patterns')
      .update({
        success_count:    (existing.success_count ?? 0) + 1,
        match_patterns:   mergedPatterns,
        installed_paths:  mergedPaths,
        hosts_entries:    mergedHosts,
        device_uuids:     mergedDevices,
        last_confirmed_at: new Date().toISOString(),
        last_device_name:  device_name ?? 'Unknown',
      })
      .eq('id', existing.id)
  } else {
    await supabase.from('install_patterns').insert({
      product_name:      product_name,
      match_patterns:    match_patterns,
      pkg_receipt_ids:   pkg_receipt_ids ?? [],
      installed_paths:   installed_paths ?? [],
      hosts_entries:     hosts_entries ?? [],
      success_count:     1,
      contributed_by:    user.id,
      last_confirmed_at: new Date().toISOString(),
      last_device_name:  device_name ?? 'Unknown',
      hardware_uuid:     hardware_uuid ?? '',
    })
  }

  return NextResponse.json({ ok: true })
}
