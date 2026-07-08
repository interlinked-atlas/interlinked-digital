import { NextRequest, NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
)

// ── Types ────────────────────────────────────────────────────────────────────

interface InstallIntel {
  found: boolean
  source?: string
  sourceUrl?: string
  steps?: string[]
  hostsEntries?: string[]
  mentionsRosetta?: boolean
  requiresAdmin?: boolean
  mentionsSelectAll?: boolean
  appToLaunch?: string
  knownIssues?: string[]
  notes?: string
  confidence?: number
  cached?: boolean
}

// ── Normalise product name for cache keying ──────────────────────────────────

function normaliseKey(name: string): string {
  return name
    .toLowerCase()
    .replace(/v\d[\d.]+/g, '')        // strip version numbers
    .replace(/[^a-z0-9\s]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim()
}

// ── Cache helpers ─────────────────────────────────────────────────────────────

async function getCached(key: string): Promise<InstallIntel | null> {
  const { data } = await supabase
    .from('install_knowledge')
    .select('*')
    .eq('product_key', key)
    .gt('expires_at', new Date().toISOString())
    .maybeSingle()

  if (!data) return null
  return {
    found:              true,
    source:             data.source_name   ?? undefined,
    sourceUrl:          data.source_url    ?? undefined,
    steps:              data.steps         ?? undefined,
    hostsEntries:       data.hosts_entries ?? undefined,
    mentionsRosetta:    data.mentions_rosetta    || undefined,
    requiresAdmin:      data.requires_admin      || undefined,
    mentionsSelectAll:  data.mentions_select_all || undefined,
    appToLaunch:        data.app_to_launch ?? undefined,
    knownIssues:        data.known_issues  ?? undefined,
    notes:              data.notes         ?? undefined,
    confidence:         data.confidence    ?? undefined,
    cached:             true,
  }
}

// ── Log unknown product for admin review ─────────────────────────────────────

async function logUnknownProduct(productName: string, fileNames: string[]): Promise<void> {
  try {
    // Try upsert by product_name; increment seen_count if already exists
    const { data: existing } = await supabase
      .from('install_failures')
      .select('id, steps_attempted')
      .eq('product_name', productName)
      .eq('failure_type', 'unknown_product')
      .maybeSingle()

    if (existing) {
      // Already logged — just update the filename list and bump a note
      const existingFiles: string[] = existing.steps_attempted ?? []
      const merged = Array.from(new Set([...existingFiles, ...fileNames]))
      await supabase
        .from('install_failures')
        .update({ steps_attempted: merged })
        .eq('id', existing.id)
    } else {
      await supabase.from('install_failures').insert({
        product_name:    productName,
        source_filename: fileNames[0] ?? productName,
        failure_reason:  'No install pattern found — needs admin review',
        failure_step:    'pattern_lookup',
        failure_type:    'unknown_product',
        steps_attempted: fileNames,
        error_output:    null,
        install_log:     null,
        device_name:     null,
        hardware_uuid:   null,
        macos_version:   null,
        user_id:         null,
      })
    }
  } catch (err) {
    // Non-fatal — don't block the response
    console.error('[install-intel] failed to log unknown product:', err)
  }
}

// ── Route handler ─────────────────────────────────────────────────────────────

export async function POST(req: NextRequest) {
  let body: { productName?: string; fileNames?: string[] }
  try {
    body = await req.json()
  } catch {
    return NextResponse.json({ error: 'Invalid JSON' }, { status: 400 })
  }

  const productName = (body.productName ?? '').trim()
  if (!productName || productName.length < 2) {
    return NextResponse.json({ error: 'productName required' }, { status: 400 })
  }

  const fileNames = body.fileNames ?? []
  const cacheKey  = normaliseKey(productName)

  // 1. Cache hit — return stored intel
  const cached = await getCached(cacheKey)
  if (cached) {
    return NextResponse.json(cached)
  }

  // 2. No cache — log the unknown product for the admin to review, then let
  //    the app fall through to its own heuristics.
  await logUnknownProduct(productName, fileNames)

  return NextResponse.json({ found: false })
}
