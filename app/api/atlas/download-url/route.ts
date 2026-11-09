import { NextRequest, NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'
import { hasActiveAtlasSubscription } from '@/lib/entitlement'

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
)

// GET /api/atlas/download-url?platform=mac|win
//
// P0-3: entitlement-gated, time-limited signed installer download, reading
// from the Supabase Storage bucket 'atlas-installers'. Filenames are stable
// (ATLAS.dmg, not versioned) — a new release replaces the file's contents
// in place, so nothing here needs updating per release, only the appcast
// route's version/signature and this bucket's object.
const STORAGE_PATHS: Record<string, string> = {
  mac: 'ATLAS.dmg',
  win: 'ATLAS-win.exe',
}

export async function GET(req: NextRequest) {
  const token = req.headers.get('authorization')?.replace('Bearer ', '').trim()
  if (!token) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

  const { data: { user }, error: authErr } = await supabase.auth.getUser(token)
  if (authErr || !user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

  if (!(await hasActiveAtlasSubscription(supabase, user.id))) {
    return NextResponse.json({ error: 'ATLAS download requires an active ATLAS subscription' }, { status: 403 })
  }

  const platform = req.nextUrl.searchParams.get('platform')
  const path = platform ? STORAGE_PATHS[platform] : undefined
  if (!path) {
    return NextResponse.json({ error: 'platform must be "mac" or "win"' }, { status: 400 })
  }

  const signed = await supabase.storage.from('atlas-installers').createSignedUrl(path, 3600)
  if (signed.error || !signed.data) {
    return NextResponse.json({ error: 'Could not create download URL' }, { status: 500 })
  }

  return NextResponse.json({ download_url: signed.data.signedUrl, expires_in: 3600 })
}
