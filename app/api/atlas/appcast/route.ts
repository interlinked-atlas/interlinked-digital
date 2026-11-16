import { NextResponse } from 'next/server'

// Sparkle appcast feed — update CURRENT_VERSION and DMG_URL when releasing a new build.
// Sparkle compares the app's CFBundleVersion against sparkle:version here.
// If they match, no update notification fires. Bump this only when a new build is ready.

// ─── UPDATE THESE WITH EACH RELEASE ────────────────────────────────────────
// CFBundleVersion in Info.plist must match CURRENT_VERSION (e.g. "300" → "3.0.0")
// Run: .build/artifacts/sparkle/bin/sign_update ATLAS.dmg  → paste signature below
// ────────────────────────────────────────────────────────────────────────────
const CURRENT_VERSION  = '1711'
const SHORT_VERSION    = '1.7.11'
const RELEASE_DATE     = 'Mon, 16 Nov 2026 11:00:00 +0000'
const DMG_URL          = 'https://www.interlinked.digital/downloads/ATLAS.dmg'
const DMG_LENGTH       = '20842117'
const ED_SIGNATURE     = 'rBopdraWcP/AjR+OY/eFTiSOMCBbOIqZErtO+UeSCTEtkjvPt4H2kJF3+X130DNwtdADzvjfhw69/JmpXNh/Aw=='

const RELEASE_NOTES = `
<ul>
  <li>ATLAS Browser's enable/disable toggle in the admin panel now syncs to the app in real time, instead of only updating the next time Browser is reopened</li>
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
