import { NextRequest, NextResponse } from 'next/server'

// Current release versions — update these when a new build ships
const LATEST: Record<string, string> = {
  mac:     '1.6.8',
  windows: '1.0.0',
}

// Download URLs — update when new builds are published
const DOWNLOAD_URLS: Record<string, string> = {
  mac:     'https://www.interlinked.digital/atlas',
  windows: 'https://www.interlinked.digital/atlas',
}

// Minimum version still allowed to sign in. Stays at '0.0.0' (every real
// version satisfies it, so update_required is always false) until a future
// V2 release is ready to force V1 out — raising this later is the only
// change needed on this side. Client-side enforcement lives in
// AuthManager.swift and is strictly fail-open: it only ever blocks login on
// an explicit, successfully-received update_required: true from this
// endpoint — never on a network failure or unreachable server.
const MINIMUM_SUPPORTED: Record<string, string> = {
  mac:     '1.6.6',
  windows: '0.0.0',
}

function semverGreater(a: string, b: string): boolean {
  const pa = a.split('.').map(Number)
  const pb = b.split('.').map(Number)
  for (let i = 0; i < 3; i++) {
    if ((pa[i] ?? 0) > (pb[i] ?? 0)) return true
    if ((pa[i] ?? 0) < (pb[i] ?? 0)) return false
  }
  return false
}

export async function GET(req: NextRequest) {
  const { searchParams } = new URL(req.url)
  const platform = searchParams.get('platform') ?? 'mac'
  const current  = searchParams.get('current')  ?? '0.0.0'

  const latest      = LATEST[platform]      ?? LATEST.mac
  const downloadUrl = DOWNLOAD_URLS[platform] ?? DOWNLOAD_URLS.mac
  const minimum     = MINIMUM_SUPPORTED[platform] ?? MINIMUM_SUPPORTED.mac
  const updateAvailable = semverGreater(latest, current)
  const updateRequired  = semverGreater(minimum, current)

  return NextResponse.json({
    update_available: updateAvailable,
    update_required:  updateRequired,
    version:          latest,
    minimum_version:  minimum,
    download_url:     downloadUrl,
    release_notes:    updateAvailable ? `ATLAS ${latest} is available.` : '',
  })
}
