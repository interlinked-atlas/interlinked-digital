// Records one ATLAS Browser download event for the authenticated user,
// gated by that user's independent 25/month Browser download cap (separate
// from the regular install limit). Enforcement + the insert happen
// atomically in one Postgres function (report_browser_download) — unlike
// the install limit's reserve/confirm/release split, a Browser download is
// a single synchronous action so there's nothing to confirm later.
import { NextRequest, NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
)

const MAX_FIELD_LENGTH = 500

function isNonEmptyString(v: unknown): v is string {
  return typeof v === 'string' && v.length > 0 && v.length <= MAX_FIELD_LENGTH
}

export async function POST(req: NextRequest) {
  const token = req.headers.get('authorization')?.replace('Bearer ', '').trim()
  if (!token) {
    return NextResponse.json({ error: 'Missing authorization' }, { status: 401 })
  }

  const { data: { user }, error: authError } = await supabase.auth.getUser(token)
  if (authError || !user) {
    return NextResponse.json({ error: 'Invalid token' }, { status: 401 })
  }

  let rawBody: unknown
  try {
    rawBody = await req.json()
  } catch {
    return NextResponse.json({ error: 'Invalid JSON body' }, { status: 400 })
  }
  if (typeof rawBody !== 'object' || rawBody === null) {
    return NextResponse.json({ error: 'Invalid request body' }, { status: 400 })
  }
  const body = rawBody as Record<string, unknown>

  const { catalog_item_id, product_name, brand, link_url, hardware_uuid, device_name } = body

  if (!isNonEmptyString(product_name)) {
    return NextResponse.json({ error: 'Missing or invalid product_name' }, { status: 400 })
  }
  for (const [name, value] of Object.entries({ catalog_item_id, brand, link_url, hardware_uuid, device_name })) {
    if (value !== undefined && value !== null && (typeof value !== 'string' || value.length > MAX_FIELD_LENGTH)) {
      return NextResponse.json({ error: `Invalid ${name}` }, { status: 400 })
    }
  }

  const { data, error: rpcError } = await supabase.rpc('report_browser_download', {
    p_user_id: user.id, // derived from the verified token — never from client-supplied data
    p_catalog_item_id: catalog_item_id ?? null,
    p_product_name: product_name,
    p_brand: brand ?? null,
    p_link_url: link_url ?? null,
    p_hardware_uuid: hardware_uuid ?? null,
    p_device_name: device_name ?? null,
  })

  if (rpcError) {
    console.error('[ATLAS] report_browser_download failed:', rpcError.message)
    return NextResponse.json({ error: 'Failed to record download' }, { status: 500 })
  }

  // data is the function's jsonb result: { allowed, reason, used, limit, next_reset }
  return NextResponse.json(data)
}
