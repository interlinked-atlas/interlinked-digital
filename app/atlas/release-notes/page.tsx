export const metadata = {
  title: 'Release Notes — ATLAS',
  description: 'ATLAS version history and release notes',
}

// Keep this in sync with CURRENT_VERSION / RELEASE_NOTES in
// app/api/atlas/appcast/route.ts when you ship a new release — add the new
// version to the TOP of this array in the same commit that ships the build.
const RELEASES = [
  {
    version: '1.6.3',
    date: 'November 9, 2026',
    notes: [
      'Fixed: the local virus/PUA check could flag normal, legitimate installers as "Crack / keygen detected" over generic filename words',
      'Fixed: a device removed by support could silently rejoin the account on next launch instead of actually staying removed',
      'A device removed by support is now detected and signed out faster on an already-running session',
    ],
  },
  {
    version: '1.6.2',
    date: 'November 9, 2026',
    notes: [
      'ATLAS now updates itself fully in the background — no more "Update Available" banner to click through; updates simply apply the next time you quit and reopen',
    ],
  },
  {
    version: '1.6.1',
    date: 'November 9, 2026',
    notes: [
      'Fixed: Settings could show a stale "25 remaining" figure in one place while correctly showing a support-adjusted limit elsewhere — both now always agree',
    ],
  },
  {
    version: '1.6',
    date: 'November 9, 2026',
    notes: [
      'Updates now install automatically in the background — no more clicking through the update dialog, it just applies the next time you quit and reopen ATLAS',
      'Support can now push a required update to a specific client or everyone, which takes effect within seconds via the app’s existing live sync',
      'A support-granted install-limit change now takes effect within seconds instead of requiring a later install attempt to notice',
      'Settings now shows your current monthly install usage and limit',
    ],
  },
  {
    version: '1.5',
    date: 'November 9, 2026',
    notes: [
      'A support-granted install-limit change now takes effect within seconds instead of requiring a later install attempt to notice — the app checks periodically, on launch, and whenever it’s brought to the foreground or Settings is opened',
      'Fixed: a support-granted install-limit change or usage reset could fail to clear the "limit reached" screen until a later install attempt — it now checks automatically, and a "Check Again" button was added',
      'The app now correctly reflects any custom install-limit changes made by support, instead of always assuming 25/month',
      'Fixed: quitting ATLAS or checking for updates while Settings was open could get stuck — Settings is now its own window',
      'Fixed: an issue that could silently sign you out after quitting and relaunching',
      'The Library panel now closes automatically after being idle, or as soon as you start a new install',
    ],
  },
  {
    version: '1.4',
    date: 'November 9, 2026',
    notes: [
      'Fixed: a support-granted install-limit change or usage reset by our team could fail to actually clear your "limit reached" screen until your next install attempt',
    ],
  },
  {
    version: '1.3',
    date: 'November 9, 2026',
    notes: [
      'Our support team can now grant an individual client a custom monthly install limit, or reset your current usage, when needed',
      'Fixed: a custom install limit granted by support was not always being reflected correctly',
    ],
  },
  {
    version: '1.2',
    date: 'November 9, 2026',
    notes: [
      'Fixed: the monthly install-limit screen could fail to appear, or fail to clear, correctly',
      'Library panel fixes',
      'Settings moved to its own window — fixes Quit and update checks getting stuck while Settings was open',
      'Fixed: an issue that could silently sign you out after quitting and relaunching',
    ],
  },
  {
    version: '1.0',
    date: 'August 15, 2026',
    notes: [
      'Initial public release',
      'TITAN MEMORY™ — AI-powered install intelligence',
      'TITAN CORE™ — Universal installer engine',
      'Full subscription support',
      'Improved Permissions Setup flow and automatic update checks',
    ],
  },
]

export default function ReleaseNotesPage() {
  return (
    <main style={{
      minHeight: '100vh',
      background: '#08080F',
      color: '#E8E8F0',
      fontFamily: "'SF Pro Display', -apple-system, BlinkMacSystemFont, sans-serif",
      padding: '0 20px',
    }}>
      <div style={{ maxWidth: 760, margin: '0 auto', padding: '80px 0 120px' }}>

        <div style={{ marginBottom: 56 }}>
          <a href="/atlas" style={{ color: '#7A9BC0', textDecoration: 'none', fontSize: 14, letterSpacing: '0.04em' }}>
            ← Back to ATLAS
          </a>
          <h1 style={{
            fontSize: 42, fontWeight: 700, marginTop: 32, marginBottom: 12,
            background: 'linear-gradient(135deg, #C8D8E8 0%, #8AAAC8 100%)',
            WebkitBackgroundClip: 'text', WebkitTextFillColor: 'transparent',
            letterSpacing: '-0.02em',
          }}>
            Release Notes
          </h1>
          <p style={{ color: '#6B7399', fontSize: 15, margin: 0 }}>
            What&apos;s new in ATLAS, version by version.
          </p>
        </div>

        <div style={{ display: 'flex', flexDirection: 'column', gap: 40 }}>
          {RELEASES.map((release) => (
            <div key={release.version}>
              <div style={{ display: 'flex', alignItems: 'baseline', gap: 12, marginBottom: 12 }}>
                <h2 style={{
                  fontSize: 20, fontWeight: 600, color: '#C8D8E8',
                  margin: 0, letterSpacing: '-0.01em',
                }}>
                  ATLAS {release.version}
                </h2>
                <span style={{ color: '#6B7399', fontSize: 14 }}>{release.date}</span>
              </div>
              <ul style={{ margin: 0, paddingLeft: 20, lineHeight: 2, color: '#B0B8D0', fontSize: 15 }}>
                {release.notes.map((note, i) => (
                  <li key={i}>{note}</li>
                ))}
              </ul>
            </div>
          ))}

          <div style={{
            marginTop: 16, padding: '24px 28px',
            background: 'rgba(122,155,192,0.08)',
            border: '1px solid rgba(122,155,192,0.15)',
            borderRadius: 12,
          }}>
            <p style={{ margin: 0, color: '#7A9BC0', fontSize: 15 }}>
              ATLAS checks for updates automatically. You can also check manually from{' '}
              <strong style={{ color: '#8AAAC8' }}>Settings → Check for Updates</strong>.
            </p>
          </div>
        </div>
      </div>
    </main>
  )
}
