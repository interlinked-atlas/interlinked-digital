export const metadata = {
  title: 'Release Notes — ATLAS',
  description: 'ATLAS version history and release notes',
}

// Keep this in sync with CURRENT_VERSION / RELEASE_NOTES in
// app/api/atlas/appcast/route.ts when you ship a new release.
const RELEASES = [
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
