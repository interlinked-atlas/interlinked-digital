import { NextRequest, NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
)

// Build match patterns from a product name (same logic ATLASLearn uses)
function buildMatchPatterns(productName: string): string[] {
  const base = productName
    .toLowerCase()
    .replace(/v\d[\d.]+/g, '')        // strip version numbers
    .replace(/[^a-z0-9\s]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim()
  const patterns = new Set<string>([base])
  // also add individual words longer than 3 chars
  base.split(' ').filter(w => w.length > 3).forEach(w => patterns.add(w))
  return Array.from(patterns)
}

// Map file extension → install path prefix
function extensionToPath(filename: string): string | null {
  const lower = filename.toLowerCase()
  if (lower.endsWith('.component')) return '/Library/Audio/Plug-Ins/Components/'
  if (lower.endsWith('.vst3'))      return '/Library/Audio/Plug-Ins/VST3/'
  if (lower.endsWith('.vst'))       return '/Library/Audio/Plug-Ins/VST/'
  if (lower.endsWith('.aaxplugin')) return '/Library/Application Support/Avid/Audio/Plug-Ins/'
  if (lower.endsWith('.app'))       return '/Applications/'
  return null
}

export async function GET(req: NextRequest) {
  const token = req.headers.get('authorization')?.replace('Bearer ', '').trim()
  if (!token) return NextResponse.json({ error: 'Missing authorization' }, { status: 401 })

  const { data: { user }, error: authError } = await supabase.auth.getUser(token)
  if (authError || !user) return NextResponse.json({ error: 'Invalid token' }, { status: 401 })

  // 1. Crowd-sourced install patterns
  const { data: crowdData, error: crowdError } = await supabase
    .from('install_patterns')
    .select('id, product_name, match_patterns, pkg_receipt_ids, installed_paths, hosts_entries, success_count, last_confirmed_at')
    .gte('success_count', 1)
    .order('success_count', { ascending: false })
    .limit(500)

  if (crowdError) return NextResponse.json({ error: crowdError.message }, { status: 500 })

  // 2. Admin-confirmed titan_memory entries
  const { data: titanData } = await supabase
    .from('titan_memory')
    .select('id, product_name, steps, hosts_entries, confirmed_at, platform')
    .or('platform.eq.mac,platform.is.null')
    .not('steps', 'is', null)

  // Convert titan_memory entries to install_patterns shape
  const titanPatterns: any[] = []
  for (const entry of (titanData ?? [])) {
    const steps: any[] = Array.isArray(entry.steps) ? entry.steps : []
    if (steps.length === 0) continue

    const installedPaths: string[] = []
    for (const step of steps) {
      if (step.type === 'plugin' && step.file) {
        const dir = extensionToPath(step.file)
        if (dir) {
          installedPaths.push(dir + step.file)
        }
      }
    }

    titanPatterns.push({
      id:                `titan_${entry.id}`,
      product_name:      entry.product_name,
      match_patterns:    buildMatchPatterns(entry.product_name),
      pkg_receipt_ids:   [],
      installed_paths:   installedPaths,
      hosts_entries:     Array.isArray(entry.hosts_entries) ? entry.hosts_entries : [],
      success_count:     999,
      last_confirmed_at: entry.confirmed_at,
      admin_verified:    true,
      source:            'titan_memory',
    })
  }

  // 3. Deduplicate: titan_memory wins over crowd-sourced for same product_name
  const titanNames = new Set(titanPatterns.map(p => p.product_name.toLowerCase().trim()))
  const crowd = (crowdData ?? []).filter(
    p => !titanNames.has(p.product_name.toLowerCase().trim())
  )

  const combined = [...titanPatterns, ...crowd]

  return NextResponse.json(combined)
}
