import { NextResponse } from 'next/server'

// Sparkle appcast feed — update CURRENT_VERSION and DMG_URL when releasing a new build.
// Sparkle compares the app's CFBundleVersion against sparkle:version here.
// If they match, no update notification fires. Bump this only when a new build is ready.

// ─── UPDATE THESE WITH EACH RELEASE ────────────────────────────────────────
// CFBundleVersion in Info.plist must match CURRENT_VERSION (e.g. "300" → "3.0.0")
// Run: .build/artifacts/sparkle/bin/sign_update ATLAS.dmg  → paste signature below
// ────────────────────────────────────────────────────────────────────────────
const CURRENT_VERSION  = '1713'
const SHORT_VERSION    = '1.7.13'
const RELEASE_DATE     = 'Wed, 18 Nov 2026 22:43:26 +0000'
const DMG_URL          = 'https://www.interlinked.digital/downloads/ATLAS.dmg'
const DMG_LENGTH       = '21330025'
const ED_SIGNATURE     = 'zbAnBwfnuT3QQMpvRqx5gBP5ZX1rPWYcAjT2MxRlFJETUqwXVZSqoEd8yXt+KmoZ6+TW8UP1Qs7bbVGLSRA1Cg=='

const RELEASE_NOTES = `
<ul>
  <li>Added customizable notification toggles for downloads, installs, and uninstalls</li>
  <li>Added "View in My Products" shortcut from a downloaded item in ATLAS Browser</li>
  <li>ATLAS Browser now warns before downloading an installer built only for Apple Silicon or only for Intel</li>
  <li>ATLAS now detects when an installer silently fails due to an architecture mismatch, instead of reporting a false success</li>
  <li>Added support for .img installer files</li>
  <li>Redesigned the install queue for a cleaner, more readable look in both light and dark mode</li>
  <li>Fixed ATLAS Browser occasionally failing to load on first open</li>
  <li>My Products now stays in sync when a product is uninstalled or cleared from your library</li>
</ul>
`.trim()

export async function GET() {
  const xml = `<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0"
     xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"
     xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>ATLAS Updates</title>
    <link>https://www.interlinked.digital/atlas</link>
    <description>ATLAS software update feed</description>
    <language>en</language>
    <item>
      <title>ATLAS ${SHORT_VERSION}</title>
      <sparkle:version>${CURRENT_VERSION}</sparkle:version>
      <sparkle:shortVersionString>${SHORT_VERSION}</sparkle:shortVersionString>
      <pubDate>${RELEASE_DATE}</pubDate>
      <sparkle:releaseNotesLink>https://www.interlinked.digital/atlas/release-notes</sparkle:releaseNotesLink>
      <description><![CDATA[${RELEASE_NOTES}]]></description>
      <enclosure
        url="${DMG_URL}"
        sparkle:version="${CURRENT_VERSION}"
        sparkle:shortVersionString="${SHORT_VERSION}"
        sparkle:edSignature="${ED_SIGNATURE}"
        length="${DMG_LENGTH}"
        type="application/octet-stream"/>
    </item>
  </channel>
</rss>`

  return new NextResponse(xml, {
    headers: {
      'Content-Type': 'application/xml; charset=utf-8',
      'Cache-Control': 'no-store',
    },
  })
}
