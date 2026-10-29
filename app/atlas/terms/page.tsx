import { TermsBody } from '@/components/terms-content'

export const metadata = {
  title: 'Terms of Service — ATLAS',
  description: 'ATLAS Terms of Service',
}

export default function TermsPage() {
  return (
    <main style={{
      minHeight: '100vh',
      background: '#08080F',
      color: '#E8E8F0',
      fontFamily: "'SF Pro Display', -apple-system, BlinkMacSystemFont, sans-serif",
      padding: '0 20px',
    }}>
      <div style={{ maxWidth: 760, margin: '0 auto', padding: '80px 0 120px' }}>

        {/* Header */}
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
            Terms of Service
          </h1>
          <p style={{ color: '#6B7399', fontSize: 15, margin: 0 }}>
            Effective Date: August 15, 2026 &nbsp;·&nbsp; Last Updated: August 15, 2026
          </p>
        </div>

        <TermsBody />
      </div>
    </main>
  )
}
