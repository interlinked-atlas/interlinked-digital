import { NextRequest, NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
)

// Only these exact filenames may be requested — this is a redirect to
// Supabase Storage, not a general-purpose file proxy.
const ALLOWED_FILES = new Set(['ATLAS.dmg'])

// GET /downloads/ATLAS.dmg  (and any other name added to ALLOWED_FILES)
//
// Redirects to a freshly signed Supabase Storage URL for the real file,
// rather than serving it as a static Next.js /public asset. The static
// path (public/downloads/ATLAS.dmg) returned 404 in production for a
// reason that turned out to be self-inflicted twice over: .vercelignore's
// blanket *.dmg rule matches any path *component* ending in ".dmg", not
// just file extensions — it was dropping the static file, and then (after
// being briefly removed) it also dropped this very route's directory when
// that directory was itself literally named "ATLAS.dmg". Using a dynamic
// [filename] segment here instead keeps no literal ".dmg" path component
// for that glob to ever match again, independent of whatever's in
// .vercelignore.
export async function GET(req: NextRequest, { params }: { params: Promise<{ filename: string }> }) {
  const { filename } = await params
  if (!ALLOWED_FILES.has(filename)) {
    return NextResponse.json({ error: 'not_found' }, { status: 404 })
  }

  const { data, error } = await supabase.storage.from('atlas-installers').createSignedUrl(filename, 3600)
  if (error || !data) {
    return NextResponse.json({ error: 'Could not generate download URL' }, { status: 500 })
  }
  return NextResponse.redirect(data.signedUrl, { status: 302 })
}
