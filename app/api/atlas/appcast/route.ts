import { NextResponse } from 'next/server'

// Sparkle appcast feed — update CURRENT_VERSION and DMG_URL when releasing a new build.
// Sparkle compares the app's CFBundleVersion against sparkle:version here.
// If they match, no update notification fires. Bump this only when a new build is ready.

// ─── UPDATE THESE WITH EACH RELEASE ────────────────────────────────────────
// CFBundleVersion in Info.plist must match CURRENT_VERSION (e.g. "300" → "3.0.0")
// Run: .build/artifacts/sparkle/bin/sign_update ATLAS-latest.dmg  → paste signature below
// ────────────────────────────────────────────────────────────────────────────
const CURRENT_VERSION  = '3.0.0'   // must match CFBundleVersion (300)
const SHORT_VERSION    = '3.0'
const RELEASE_DATE     = 'Tue, 15 Aug 2026 12:00:00 +0000'
const DMG_URL          = 'https://www.interlinked.digital/downloads/ATLAS-latest.dmg'
const DMG_LENGTH       = '20971520' // bytes — update per release (run: stat -f%z ATLAS-latest.dmg)
// EdDSA signature — run sign_update on the DMG before each release
const ED_SIGNATURE     = 'PLACEHOLDER_SIGN_BEFORE_RELEASE'

const RELEASE_NOTES = `
<ul>
  <li>Initial public release</li>
  <li>TITAN MEMORY™ — AI-powered install intelligence</li>
  <li>TITAN CORE™ — Universal installer engine</li>
  <li>Pro and Standard plan support</li>
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
