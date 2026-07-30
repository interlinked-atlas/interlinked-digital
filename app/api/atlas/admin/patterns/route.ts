// Admin-only CRUD for install_patterns (live TITAN MEMORY™ editing — no rebuild needed)
import { NextRequest, NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'

const ADMIN_EMAIL = 'titantinstaller@gmail.com'

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
)

async function verifyAdmin(req: NextRequest): Promise<{ ok: boolean; error?: NextResponse }> {
  const token = req.headers.get('authorization')?.replace('Bearer ', '').trim()
  if (!token) return { ok: false, error: NextResponse.json({ error: 'Unauthorized' }, { status: 401 }) }
  const { data: { user }, error } = await supabase.auth.getUser(token)
  if (error || !user || user.email?.toLowerCase() !== ADMIN_EMAIL.toLowerCase())
    return { ok: false, error: NextResponse.json({ error: 'Forbidden' }, { status: 403 }) }
  return { ok: true }
}

// GET — pattern health report (includes failure counts, device diversity, titan_candidate flag)
export async function GET(req: NextRequest) {
  const auth = await verifyAdmin(req)
  if (!auth.ok) return auth.error!

  const { data: patterns, error: pErr } = await supabase
    .from('install_patterns')
    .select('id, product_name, success_count, device_uuids, last_confirmed_at, match_patterns, installed_paths')
    .order('success_count', { ascending: false })

  if (pErr) return NextResponse.json({ error: pErr.message }, { status: 500 })

  // Failure counts grouped by product_name
  const { data: failures } = await supabase
    .from('install_failures')
    .select('product_name, admin_fix_status')

  const failureIndex: Record<string, { total: number; unresolved: number }> = {}
  for (const f of failures ?? []) {
    const key = (f.product_name ?? '').toLowerCase().trim()
    if (!key) continue
    if (!failureIndex[key]) failureIndex[key] = { total: 0, unresolved: 0 }
    failureIndex[key].total++
    if (!f.admin_fix_status || f.admin_fix_status === 'open') failureIndex[key].unresolved++
  }

  // TITAN MEMORY product names (cloud DB rows)
  const { data: titanRows } = await supabase
    .from('titan_memory')
    .select('product_name')

  const titanNames = new Set(
    (titanRows ?? []).map((r: { product_name?: string }) => (r.product_name ?? '').toLowerCase().trim()).filter(Boolean)
  )

  const report = (patterns ?? []).map((p: {
    product_name: string
    success_count: number
    device_uuids: string[] | null
    last_confirmed_at: string | null
    match_patterns: string[] | null
    installed_paths: string[] | null
  }) => {
    const key = (p.product_name ?? '').toLowerCase().trim()
    const f = failureIndex[key] ?? { total: 0, unresolved: 0 }
    const uniqueDeviceCount = (p.device_uuids ?? []).length

    return {
      product_name:        p.product_name,
      success_count:       p.success_count,
      unique_device_count: uniqueDeviceCount,
      last_success:        p.last_confirmed_at,
      match_patterns:      p.match_patterns ?? [],
      installed_paths:     p.installed_paths ?? [],
      failure_count:       f.total,
      unresolved_failures: f.unresolved,
      titan_memory_match:  titanNames.has(key),
      titan_candidate:     p.success_count >= 5 && uniqueDeviceCount >= 2 && f.unresolved === 0,
    }
  })

  return NextResponse.json(report)
}

// POST — create a new pattern (admin writes a fix)
export async function POST(req: NextRequest) {
  const auth = await verifyAdmin(req)
  if (!auth.ok) return auth.error!

  let body: Record<string, unknown>
  try { body = await req.json() }
  catch { return NextResponse.json({ error: 'Invalid JSON' }, { status: 400 }) }

  const { data, error } = await supabase.from('install_patterns').insert({
    product_name:      body.product_name,
    match_patterns:    body.match_patterns   ?? [],
    pkg_receipt_ids:   body.pkg_receipt_ids  ?? [],
    installed_paths:   body.installed_paths  ?? [],
    hosts_entries:     body.hosts_entries    ?? [],
    install_steps:     body.install_steps    ?? null,
    success_count:     body.success_count    ?? 0,
    admin_verified:    true,
    last_confirmed_at: new Date().toISOString(),
  }).select('id').single()

  if (error) return NextResponse.json({ error: error.message }, { status: 500 })
  return NextResponse.json({ ok: true, id: data?.id })
}

// PATCH — update an existing pattern
export async function PATCH(req: NextRequest) {
  const auth = await verifyAdmin(req)
  if (!auth.ok) return auth.error!

  let body: Record<string, unknown>
  try { body = await req.json() }
  catch { return NextResponse.json({ error: 'Invalid JSON' }, { status: 400 }) }

  const { id, ...fields } = body
  if (!id) return NextResponse.json({ error: 'Missing id' }, { status: 400 })

  const { error } = await supabase
    .from('install_patterns')
    .update({ ...fields, last_confirmed_at: new Date().toISOString() })
    .eq('id', id)

  if (error) return NextResponse.json({ error: error.message }, { status: 500 })
  return NextResponse.json({ ok: true })
}

// DELETE — remove a bad/wrong pattern
export async function DELETE(req: NextRequest) {
  const auth = await verifyAdmin(req)
  if (!auth.ok) return auth.error!

  const { id } = await req.json().catch(() => ({}))
  if (!id) return NextResponse.json({ error: 'Missing id' }, { status: 400 })

  const { error } = await supabase.from('install_patterns').delete().eq('id', id)
  if (error) return NextResponse.json({ error: error.message }, { status: 500 })
  return NextResponse.json({ ok: true })
}
