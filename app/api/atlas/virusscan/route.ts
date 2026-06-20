import { NextRequest, NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
)

const VT_API_KEY = process.env.VIRUSTOTAL_API_KEY!
const VT_BASE    = 'https://www.virustotal.com/api/v3/files'

// Categories VirusTotal uses for crack/keygen/patcher tools — treat as warnings, not hard blocks
const PUA_CATEGORIES = ['riskware', 'pua', 'unwanted', 'tool', 'hacktool', 'keygen', 'crack', 'patcher']

export async function POST(req: NextRequest) {
  // Auth
  const token = req.headers.get('authorization')?.replace('Bearer ', '')
  if (!token) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

  const { data: { user }, error: authErr } = await supabase.auth.getUser(token)
  if (authErr || !user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

  // Pro only
  const { data: profile } = await supabase
    .from('profiles')
    .select('plan')
    .eq('id', user.id)
    .single()

  const plan = profile?.plan ?? 'standard'
  if (plan !== 'pro') {
    return NextResponse.json({ error: 'Virus Scanner is a Pro feature' }, { status: 403 })
  }

  const { hash } = await req.json()
  if (!hash || !/^[a-fA-F0-9]{64}$/.test(hash)) {
    return NextResponse.json({ error: 'Invalid SHA-256 hash' }, { status: 400 })
  }

  // VirusTotal lookup
  const vtRes = await fetch(`${VT_BASE}/${hash.toLowerCase()}`, {
    headers: { 'x-apikey': VT_API_KEY },
  })

  // File not in VT database yet
  if (vtRes.status === 404) {
    return NextResponse.json({
      verdict: 'unknown',
      malicious: 0, suspicious: 0, total: 0,
      engines: [],
      message: 'File not found in VirusTotal database',
    })
  }

  if (!vtRes.ok) {
    return NextResponse.json({ error: 'VirusTotal lookup failed' }, { status: 502 })
  }

  const vt = await vtRes.json()
  const stats: Record<string, number> = vt.data?.attributes?.last_analysis_stats ?? {}
  const results: Record<string, { category: string; result: string | null }> =
    vt.data?.attributes?.last_analysis_results ?? {}

  const malicious  = stats.malicious  ?? 0
  const suspicious = stats.suspicious ?? 0
  const total      = Object.values(stats).reduce((a, b) => a + b, 0)

  // Collect flagging engines, mark PUA separately
  const engines = Object.entries(results)
    .filter(([, v]) => v.category === 'malicious' || v.category === 'suspicious')
    .map(([name, v]) => ({
      name,
      result:   v.result ?? v.category,
      category: v.category,
      isPua:    PUA_CATEGORIES.some(p => (v.result ?? '').toLowerCase().includes(p)),
    }))

  // Verdict logic:
  // - All flags are PUA/riskware → 'pua' (warning, not block)
  // - 3+ malicious engines → 'malicious'
  // - 1-2 malicious or any suspicious → 'suspicious'
  // - Otherwise → 'clean'
  const realMalicious = engines.filter(e => e.category === 'malicious' && !e.isPua).length
  let verdict: 'clean' | 'pua' | 'suspicious' | 'malicious' | 'unknown'

  if (malicious === 0 && suspicious === 0) {
    verdict = 'clean'
  } else if (realMalicious === 0 && malicious > 0) {
    verdict = 'pua'
  } else if (realMalicious >= 3) {
    verdict = 'malicious'
  } else {
    verdict = 'suspicious'
  }

  return NextResponse.json({
    verdict,
    malicious,
    suspicious,
    total,
    engines: engines.slice(0, 10), // top 10 flagging engines
  })
}
