// Records one ATLAS Browser download event for the authenticated user.
// Fire-and-forget from the Mac app (Core/AtlasBrowserDownloadReporter.swift)
// — same auth shape as app/api/atlas/logs/route.ts, but a plain one-shot
// event row rather than a log upload: no idempotency key, since a user
// re-downloading the same product later is a second legitimate row.
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

  const { error: insertError } = await supabase.from('atlas_browser_downloads').insert({
    user_id: user.id, // derived from the verified token — never from client-supplied data
    catalog_item_id: catalog_item_id ?? null,
    product_name,
    brand: brand ?? null,
    link_url: link_url ?? null,
    hardware_uuid: hardware_uuid ?? null,
    device_name: device_name ?? null,
  })

  if (insertError) {
    console.error('[ATLAS] atlas_browser_downloads insert failed:', insertError.message)
    return NextResponse.json({ error: 'Failed to save download event' }, { status: 500 })
  }

  return NextResponse.json({ ok: true })
}
