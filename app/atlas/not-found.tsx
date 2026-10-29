export default function AtlasNotFound() {
  return (
    <main style={{
      minHeight: '100vh', background: '#080809', display: 'flex',
      alignItems: 'center', justifyContent: 'center', padding: '32px 20px',
      fontFamily: '"Inter", -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif',
      WebkitFontSmoothing: 'antialiased',
    }}>
      <style>{`
        @font-face {
          font-family: 'SF-Intellivised';
          src: url('/fonts/SF-Intellivised.ttf') format('truetype');
          font-weight: normal; font-style: normal; font-display: swap;
        }
      `}</style>
      <div style={{ width: '100%', maxWidth: 360, textAlign: 'center' }}>
        <a href="/atlas" style={{ display: 'inline-block', textDecoration: 'none' }}>
          <h1 style={{
            fontFamily: "'SF-Intellivised', -apple-system, sans-serif",
            fontSize: 52, fontWeight: 'normal', letterSpacing: 14, textIndent: 14, lineHeight: 1, marginBottom: 10,
            background: 'linear-gradient(160deg, #FFFFFF 30%, rgba(255,255,255,0.55) 100%)',
            WebkitBackgroundClip: 'text', WebkitTextFillColor: 'transparent', backgroundClip: 'text',
          }}>ATLAS</h1>
        </a>
        <p style={{ color: '#44444E', fontSize: 11, letterSpacing: 3, textTransform: 'uppercase', marginBottom: 40 }}>by InterLinked©</p>

        <p style={{ color: '#3ECFB2', fontSize: 12, letterSpacing: 3, textTransform: 'uppercase', marginBottom: 12 }}>404</p>
        <p style={{ color: '#8A8A96', fontSize: 15, marginBottom: 32 }}>This page doesn&apos;t exist.</p>

        <a
          href="/atlas"
          style={{
            display: 'inline-block',
            padding: '11px 24px',
            borderRadius: 9,
            background: 'linear-gradient(135deg, #3ECFB2, #2ABEAA)',
            color: '#080809', fontSize: 13, fontWeight: 700,
            textDecoration: 'none',
          }}
        >
          Back to ATLAS →
        </a>
      </div>
    </main>
  )
}
