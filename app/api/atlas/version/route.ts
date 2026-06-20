import { NextResponse } from 'next/server'

// Current shipping versions — bump these when a new build is released.
// Both Mac and Windows apps call this on startup to check for updates.
const VERSIONS = {
  mac:     { version: '1.0.0', download_url: 'https://www.interlinked.digital/atlas', release_notes: '' },
  windows: { version: '1.0.0', download_url: 'https://www.interlinked.digital/atlas', release_notes: '' },
}

export async function GET(req: Request) {
  const { searchParams } = new URL(req.url)
  const platform = searchParams.get('platform') ?? 'mac'
  const info = VERSIONS[platform as keyof typeof VERSIONS] ?? VERSIONS.mac
  return NextResponse.json(info)
}
