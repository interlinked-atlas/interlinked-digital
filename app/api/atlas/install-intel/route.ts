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

// ── HTML helpers ─────────────────────────────────────────────────────────────

function stripHtml(html: string): string {
  return html
    .replace(/<style[^>]*>[\s\S]*?<\/style>/gi, '')
    .replace(/<script[^>]*>[\s\S]*?<\/script>/gi, '')
    .replace(/<[^>]+>/g, ' ')
    .replace(/&nbsp;/g, ' ')
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/\s+/g, ' ')
    .trim()
}

function extractSnippets(html: string, maxChars = 12000): string {
  const patterns = [
    /<div[^>]*class="[^"]*(?:result|snippet|post|content|description|body|entry)[^"]*"[^>]*>([\s\S]{20,800}?)<\/div>/gi,
    /<p[^>]*>([\s\S]{30,600}?)<\/p>/gi,
    /<li[^>]*>([\s\S]{20,400}?)<\/li>/gi,
  ]
  let combined = ''
  for (const pattern of patterns) {
    let m: RegExpExecArray | null
    pattern.lastIndex = 0
    while ((m = pattern.exec(html)) !== null && combined.length < maxChars) {
      combined += ' ' + stripHtml(m[1])
    }
  }
  return combined.slice(0, maxChars)
}

// ── Structured intel parser ──────────────────────────────────────────────────

function parseIntelFromText(text: string, productName: string): Omit<InstallIntel, 'found' | 'cached'> {
  const lower = text.toLowerCase()

  const steps: string[] = []
  const stepPatterns = [
    /(?:step\s*\d+|^\s*\d+[\.):])[\s]+([^\n]{10,120})/gim,
    /(?:first|then|next|after that|finally)[,:]?\s*([^\n.]{10,100})/gi,
    /(?:install|run|open|launch|apply|drag|copy|replace)\s+([^\n.]{5,80})/gi,
  ]
  for (const pattern of stepPatterns) {
    let m: RegExpExecArray | null
    pattern.lastIndex = 0
    while ((m = pattern.exec(text)) !== null && steps.length < 10) {
      const step = m[1].trim()
      if (step.length > 8 && !steps.includes(step)) steps.push(step)
    }
  }

  const hostsEntries: string[] = []
  const hostsPattern = /127\.0\.0\.1\s+([\w.\-]+)|block[^a-z]+([\w.\-]+\.[a-z]{2,6})/gi
  let hm: RegExpExecArray | null
  while ((hm = hostsPattern.exec(text)) !== null) {
    const domain = (hm[1] || hm[2])?.trim()
    if (domain && !hostsEntries.includes(domain)) hostsEntries.push(domain)
  }

  const mentionsRosetta =
    lower.includes('rosetta') ||
    lower.includes('intel only') ||
    lower.includes('x86') ||
    lower.includes('arch -x86_64')

  const requiresAdmin =
    lower.includes('admin') ||
    lower.includes('sudo') ||
    lower.includes('administrator') ||
    lower.includes('password')

  const mentionsSelectAll =
    lower.includes('select all') ||
    lower.includes('cmd+a') ||
    lower.includes('command+a') ||
    lower.includes('command-a')

  let appToLaunch: string | undefined
  const appMatch = text.match(/(?:open|launch|run|start)\s+([A-Z][A-Za-z0-9\s\-]{2,30}?)(?:\.app|\s+app|\s+installer)/i)
  if (appMatch) appToLaunch = appMatch[1].trim()

  const knownIssues: string[] = []
  const issuePattern = /(?:note|warning|important|make sure|if you|problem|issue|error)[:\s]+([^\n.]{15,120})/gi
  let im: RegExpExecArray | null
  while ((im = issuePattern.exec(text)) !== null && knownIssues.length < 4) {
    const issue = im[1].trim()
    if (issue.length > 10) knownIssues.push(issue)
  }

  const nameWords = productName.toLowerCase().split(/\s+/).filter(w => w.length > 3)
  const nameHits  = nameWords.reduce((n, w) => n + (lower.split(w).length - 1), 0)
  const confidence = Math.min(0.95, 0.3 + nameHits * 0.08 + (steps.length > 0 ? 0.2 : 0))

  return {
    steps:              steps.length      > 0 ? steps        : undefined,
    hostsEntries:       hostsEntries.length > 0 ? hostsEntries : undefined,
    mentionsRosetta:    mentionsRosetta   || undefined,
    requiresAdmin:      requiresAdmin     || undefined,
    mentionsSelectAll:  mentionsSelectAll || undefined,
    appToLaunch,
    knownIssues:        knownIssues.length > 0 ? knownIssues : undefined,
    confidence,
  }
}

// ── Web fetchers ─────────────────────────────────────────────────────────────

const FETCH_TIMEOUT = 8000

async function fetchText(url: string): Promise<string | null> {
  try {
    const ctrl = new AbortController()
    const tid  = setTimeout(() => ctrl.abort(), FETCH_TIMEOUT)
    const res  = await fetch(url, {
      signal: ctrl.signal,
      headers: {
        'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36',
        'Accept': 'text/html,application/xhtml+xml',
        'Accept-Language': 'en-US,en;q=0.9',
      },
    })
    clearTimeout(tid)
    if (!res.ok) return null
    return await res.text()
  } catch {
    return null
  }
}

const SEARCH_SOURCES = [
  {
    name: 'audioz.download',
    url: (q: string) => `https://audioz.download/?s=${encodeURIComponent(q)}`,
  },
  {
    name: 'audiotools.in',
    url: (q: string) => `https://audiotools.in/?s=${encodeURIComponent(q)}`,
  },
  {
    name: 'torrentmac.net',
    url: (q: string) => `https://torrentmac.net/?s=${encodeURIComponent(q)}`,
  },
  {
    name: 'duckduckgo',
    url: (q: string) =>
      `https://html.duckduckgo.com/html/?q=${encodeURIComponent(q + ' mac install guide crack')}`,
  },
]

async function scrapeInstallIntel(productName: string): Promise<InstallIntel> {
  for (const source of SEARCH_SOURCES) {
    const html = await fetchText(source.url(productName))
    if (!html) continue

    const text = extractSnippets(html)
    if (text.length < 100) continue

    const intel = parseIntelFromText(text, productName)
    if ((intel.confidence ?? 0) < 0.35) continue

    const linkMatch = html.match(/href="(https?:\/\/[^"]+(?:install|how-to|guide)[^"]{0,80})"/i)
    const sourceUrl = linkMatch ? linkMatch[1] : source.url(productName)

    if (linkMatch) {
      const pageHtml = await fetchText(linkMatch[1])
      if (pageHtml) {
        const pageText = extractSnippets(pageHtml, 20000)
        const richer   = parseIntelFromText(pageText, productName)
        if ((richer.confidence ?? 0) > (intel.confidence ?? 0)) {
          return { found: true, source: source.name, sourceUrl, ...richer }
        }
      }
    }

    return { found: true, source: source.name, sourceUrl, ...intel }
  }

  return { found: false }
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

async function saveCache(key: string, intel: InstallIntel): Promise<void> {
  await supabase.from('install_knowledge').upsert({
    product_key:         key,
    source_name:         intel.source         ?? null,
    source_url:          intel.sourceUrl      ?? null,
    steps:               intel.steps          ?? null,
    hosts_entries:       intel.hostsEntries   ?? null,
    mentions_rosetta:    intel.mentionsRosetta    ?? false,
    requires_admin:      intel.requiresAdmin      ?? false,
    mentions_select_all: intel.mentionsSelectAll  ?? false,
    app_to_launch:       intel.appToLaunch    ?? null,
    known_issues:        intel.knownIssues    ?? null,
    notes:               intel.notes          ?? null,
    confidence:          intel.confidence     ?? 0.5,
    expires_at:          new Date(Date.now() + 7 * 24 * 60 * 60 * 1000).toISOString(),
  }, { onConflict: 'product_key' })
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

  const cacheKey = normaliseKey(productName)

  // 1. Cache hit
  const cached = await getCached(cacheKey)
  if (cached) {
    return NextResponse.json(cached)
  }

  // 2. Scrape
  const intel = await scrapeInstallIntel(productName)

  // 3. Persist
  if (intel.found) {
    await saveCache(cacheKey, intel)
  }

  return NextResponse.json(intel)
}
