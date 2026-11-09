import { NextRequest, NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'
import { hasActiveAtlasSubscription } from '@/lib/entitlement'

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
)

// GET /api/atlas/download-url?platform=mac|win
//
// P0-3: entitlement-gated, time-limited signed installer download. Built
// alongside the existing public/downloads/ATLAS-latest.dmg (untouched, not
// removed) — this is a new, additive path, not a cutover yet.
//
// Storage bucket 'atlas-installers' is currently empty; the actual installer
// file(s) have not been uploaded into it in this pass (explicitly deferred —
// migrating/moving the existing artifact was out of scope for this change).
// Until a file exists at the expected path, this route will return a signing
// error from Supabase Storage rather than a broken/incorrect URL — it fails
// closed, consistent with the rest of this pass, rather than silently
// succeeding with an unusable link.
const STORAGE_PATHS: Record<string, string> = {
  mac: 'ATLAS-latest.dmg',
  win: 'ATLAS-latest-win.exe',
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
