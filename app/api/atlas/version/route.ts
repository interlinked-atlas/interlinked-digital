import { NextRequest, NextResponse } from 'next/server'

// Current release versions — update these when a new build ships
const LATEST: Record<string, string> = {
  mac:     '1.0.0',
  windows: '1.0.0',
}

// Download URLs — update when new builds are published
const DOWNLOAD_URLS: Record<string, string> = {
  mac:     'https://www.interlinked.digital/atlas',
  windows: 'https://www.interlinked.digital/atlas',
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
  const updateAvailable = semverGreater(latest, current)

  return NextResponse.json({
    update_available: updateAvailable,
    version:          latest,
    download_url:     downloadUrl,
    release_notes:    updateAvailable ? `ATLAS ${latest} is available.` : '',
  })
}
