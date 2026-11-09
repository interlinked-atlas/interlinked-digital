import { NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
)

// GET /downloads/ATLAS.dmg
//
// Redirects to a freshly signed Supabase Storage URL for the real file,
// rather than serving it as a static Next.js /public asset. The static
// path (public/downloads/ATLAS.dmg) was returning 404 in production for
// reasons unrelated to the file itself — even a brand-new, tiny, correctly
// committed .txt file placed in that same public/downloads/ directory
// also 404'd, which rules out .vercelignore, file size, and the .dmg
// extension as the cause. Rather than keep guessing at Vercel's static-
// asset internals, this serves the same file from Supabase Storage
// (atlas-installers/ATLAS.dmg — already the source of truth for the
// gated account-page download) via a redirect, keeping this clean public
// URL stable for the Sparkle appcast and anyone linking to it directly.
export async function GET() {
  const { data, error } = await supabase.storage.from('atlas-installers').createSignedUrl('ATLAS.dmg', 3600)
  if (error || !data) {
    return NextResponse.json({ error: 'Could not generate download URL' }, { status: 500 })
  }
  return NextResponse.redirect(data.signedUrl, { status: 302 })
}
