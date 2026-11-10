import { NextResponse } from 'next/server'

// Sparkle appcast feed — update CURRENT_VERSION and DMG_URL when releasing a new build.
// Sparkle compares the app's CFBundleVersion against sparkle:version here.
// If they match, no update notification fires. Bump this only when a new build is ready.

// ─── UPDATE THESE WITH EACH RELEASE ────────────────────────────────────────
// CFBundleVersion in Info.plist must match CURRENT_VERSION (e.g. "300" → "3.0.0")
// Run: .build/artifacts/sparkle/bin/sign_update ATLAS.dmg  → paste signature below
// ────────────────────────────────────────────────────────────────────────────
const CURRENT_VERSION  = '162'
const SHORT_VERSION    = '1.6.2'
const RELEASE_DATE     = 'Tue, 10 Nov 2026 00:05:00 +0000'
const DMG_URL          = 'https://www.interlinked.digital/downloads/ATLAS.dmg'
const DMG_LENGTH       = '19664172'
const ED_SIGNATURE     = 'Vp9eLjWWw1Vk8SMTHgNCQ2A+RguXUyZ5x/V4Z5NKYEHXfjKXhP0B0KTn+jZ4WomCOv4ml1cqreu2gNDZAgr8Dg=='

const RELEASE_NOTES = `
<ul>
  <li>ATLAS now updates itself fully in the background, like most modern apps — no more "Update Available" banner to click through; updates simply apply the next time you quit and reopen</li>
  <li>Fixed: Settings could show a stale "25 remaining" figure in one place while correctly showing a support-adjusted limit elsewhere — both now always agree</li>
  <li>Updates now install automatically in the background — no more clicking through the update dialog, it just applies the next time you quit and reopen ATLAS</li>
  <li>Support can now push a required update to a specific client or everyone, which takes effect within seconds via the app's existing live sync</li>
  <li>A support-granted install-limit change now takes effect within seconds instead of requiring a later install attempt to notice — the app checks periodically, on launch, and whenever it's brought to the foreground or Settings is opened</li>
  <li>Settings now shows your current monthly install usage and limit</li>
  <li>Fixed: a support-granted install-limit change or usage reset could fail to clear the "limit reached" screen until a later install attempt — it now checks automatically when that screen appears, and a "Check Again" button was added</li>
  <li>The app now correctly reflects any custom install-limit changes made by support, instead of always assuming 25/month</li>
  <li>Fixed: the monthly install-limit screen now actually appears when you reach your cap, with a notification and a Support button</li>
  <li>Fixed: newly installed products now show up in the Library immediately instead of after a delay</li>
  <li>Fixed: quitting ATLAS or checking for updates while Settings was open could get stuck — Settings is now its own window</li>
  <li>Fixed: an issue that could silently sign you out after quitting and relaunching</li>
  <li>The Library panel now closes automatically after being idle, or as soon as you start a new install</li>
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
