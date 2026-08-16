import { NextRequest, NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
)

export async function POST(req: NextRequest) {
  const token = req.headers.get('authorization')?.replace('Bearer ', '')
  if (!token) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

  const { data: { user }, error: authErr } = await supabase.auth.getUser(token)
  if (authErr || !user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

  const { data: profile } = await supabase
    .from('profiles')
    .select('plan')
    .eq('id', user.id)
    .single()
  if (profile?.plan !== 'pro') {
    return NextResponse.json({ error: 'Cloud Recovery Kit requires ATLAS Pro' }, { status: 403 })
  }

  const body = await req.json().catch(() => ({}))
  const {
    kit_id,
    atlaskit_path,
    txt_path,
    generated_at,
    atlas_version,
    kit_version,
    record_count,
    archived_count,
    atlaskit_size,
    txt_size,
    device_name,
    hardware_uuid,
  } = body

  if (!kit_id || !atlaskit_path || !txt_path || !generated_at || typeof record_count !== 'number') {
    return NextResponse.json({ error: 'kit_id, atlaskit_path, txt_path, generated_at, and record_count are required' }, { status: 400 })
  }

  // Validate storage paths belong to this user's namespace — never trust client-supplied paths
  const expectedPrefix = `${user.id}/`
  if (!atlaskit_path.startsWith(expectedPrefix) || !txt_path.startsWith(expectedPrefix)) {
    return NextResponse.json({ error: 'Invalid storage path' }, { status: 403 })
  }

  // Also validate paths end with expected suffixes for this kit_id
  if (!atlaskit_path.endsWith(`${kit_id}-atlaskit.enc`) || !txt_path.endsWith(`${kit_id}-txt.enc`)) {
    return NextResponse.json({ error: 'Storage path does not match kit_id' }, { status: 403 })
  }

  // INSERT — creates a new independent kit row; no upsert, no conflict, no deletion of previous kits
  const { error: insertErr } = await supabase.from('recovery_kits').insert({
    id:             kit_id,
    user_id:        user.id,
    atlaskit_path,
    txt_path,
    generated_at,
    atlas_version:  atlas_version  ?? '',
    kit_version:    kit_version    ?? 1,
    record_count:   record_count,
    archived_count: archived_count ?? 0,
    atlaskit_size:  atlaskit_size  ?? null,
    txt_size:       txt_size       ?? null,
    device_name:    device_name    ?? null,
    hardware_uuid:  hardware_uuid  ?? null,
    is_deleted:     false,
  })

  if (insertErr) {
    return NextResponse.json({ error: insertErr.message }, { status: 500 })
  }

  return NextResponse.json({ ok: true, kit_id })
}
