// Admin-only CRUD for atlas_catalog ("ATLAS Browser" products) — same
// shape as app/api/atlas/admin/patterns/route.ts.
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

// GET — full catalog for the admin tab (includes rows with no image/link yet)
export async function GET(req: NextRequest) {
  const auth = await verifyAdmin(req)
  if (!auth.ok) return auth.error!

  const { data, error } = await supabase
    .from('atlas_catalog')
    .select('*')
    .order('category', { ascending: true })
    .order('sort_order', { ascending: true })

  if (error) return NextResponse.json({ error: error.message }, { status: 500 })
  return NextResponse.json(data ?? [])
}

// POST — add one product
export async function POST(req: NextRequest) {
  const auth = await verifyAdmin(req)
  if (!auth.ok) return auth.error!

  let body: Record<string, unknown>
  try { body = await req.json() }
  catch { return NextResponse.json({ error: 'Invalid JSON' }, { status: 400 }) }

  const { data, error } = await supabase.from('atlas_catalog').insert({
    name:         body.name,
    brand:        body.brand ?? null,
    category:     body.category,
    platform:     body.platform,
    image_url:    body.image_url ?? null,
    external_url: body.external_url ?? null,
    sort_order:   body.sort_order ?? 0,
  }).select('id').single()

  if (error) return NextResponse.json({ error: error.message }, { status: 500 })
  return NextResponse.json({ ok: true, id: data?.id })
}

// PATCH — update one product (e.g. filling in image_url/external_url later)
export async function PATCH(req: NextRequest) {
  const auth = await verifyAdmin(req)
  if (!auth.ok) return auth.error!

  let body: Record<string, unknown>
  try { body = await req.json() }
  catch { return NextResponse.json({ error: 'Invalid JSON' }, { status: 400 }) }

  const { id, ...fields } = body
  if (!id) return NextResponse.json({ error: 'Missing id' }, { status: 400 })

  const { error } = await supabase.from('atlas_catalog').update(fields).eq('id', id)

  if (error) return NextResponse.json({ error: error.message }, { status: 500 })
  return NextResponse.json({ ok: true })
}

// DELETE — remove a product
export async function DELETE(req: NextRequest) {
  const auth = await verifyAdmin(req)
  if (!auth.ok) return auth.error!

  const { id } = await req.json().catch(() => ({}))
  if (!id) return NextResponse.json({ error: 'Missing id' }, { status: 400 })

  const { error } = await supabase.from('atlas_catalog').delete().eq('id', id)
  if (error) return NextResponse.json({ error: error.message }, { status: 500 })
  return NextResponse.json({ ok: true })
}
