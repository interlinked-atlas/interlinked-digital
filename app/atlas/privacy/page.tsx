export const metadata = {
  title: 'Privacy Policy — ATLAS',
  description: 'ATLAS Privacy Policy',
}

export default function PrivacyPage() {
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
            Privacy Policy
          </h1>
          <p style={{ color: '#6B7399', fontSize: 15, margin: 0 }}>
            Effective Date: August 15, 2026 &nbsp;·&nbsp; Last Updated: August 15, 2026
          </p>
        </div>

        <div style={{ display: 'flex', flexDirection: 'column', gap: 40 }}>

          <Section title="1. Who We Are">
            ATLAS is a software product developed and operated by Interlinked Digital. Our website is{' '}
            <a href="https://interlinked.digital" style={{ color: '#7A9BC0' }}>interlinked.digital</a>.
            You can contact us at{' '}
            <a href="mailto:interlinked.digital@gmail.com" style={{ color: '#7A9BC0' }}>
              interlinked.digital@gmail.com
            </a>.
          </Section>

          <Section title="2. What Information We Collect">
            When you create an account or subscribe to ATLAS, we collect:
            <ul style={{ marginTop: 16, paddingLeft: 20, lineHeight: 2, color: '#B0B8D0' }}>
              <li>Your email address and password (stored securely via Supabase)</li>
              <li>Payment information — processed and stored by Stripe. We never see or store your full card number.</li>
              <li>Device information — your device name, hardware UUID, and macOS/Windows version, used to enforce device limits</li>
              <li>Installation logs — files you install using ATLAS, timestamps, and outcomes. These are used to improve ATLAS's intelligence (TITAN MEMORY™)</li>
              <li>Usage data — plan type, subscription status, install counts</li>
            </ul>
          </Section>

          <Section title="3. How We Use Your Information">
            <ul style={{ marginTop: 16, paddingLeft: 20, lineHeight: 2, color: '#B0B8D0' }}>
              <li>To provide and manage your ATLAS subscription</li>
              <li>To enforce plan limits (install counts, device limits)</li>
              <li>To improve ATLAS's installation intelligence via TITAN MEMORY™</li>
              <li>To send you account-related emails (welcome, billing confirmations, cancellation notices)</li>
              <li>To notify you of new ATLAS versions and updates</li>
              <li>To respond to support requests</li>
            </ul>
          </Section>

          <Section title="4. Data Sharing">
            We do not sell your personal data. We share data only with:
            <ul style={{ marginTop: 16, paddingLeft: 20, lineHeight: 2, color: '#B0B8D0' }}>
              <li><strong style={{ color: '#C8D8E8' }}>Stripe</strong> — for payment processing</li>
              <li><strong style={{ color: '#C8D8E8' }}>Supabase</strong> — for database and authentication</li>
              <li><strong style={{ color: '#C8D8E8' }}>Resend</strong> — for transactional email delivery</li>
            </ul>
          </Section>

          <Section title="5. Data Retention">
            We retain your account data for as long as your account exists. If you delete your account or
            your subscription ends, we retain billing records as required by law. Installation logs are
            retained to improve ATLAS's performance.
          </Section>

          <Section title="6. Your Rights">
            You may request access to, correction of, or deletion of your personal data at any time by
            emailing{' '}
            <a href="mailto:interlinked.digital@gmail.com" style={{ color: '#7A9BC0' }}>
              interlinked.digital@gmail.com
            </a>. We will respond within 30 days.
          </Section>

          <Section title="7. Security">
            We use industry-standard encryption for data in transit (HTTPS/TLS) and at rest.
            Authentication tokens are stored in your device's secure keychain.
          </Section>

          <Section title="8. Cookies">
            Our website uses only functional cookies necessary to keep you logged in. We do not use
            advertising or tracking cookies.
          </Section>

          <Section title="9. Children">
            ATLAS is not directed at children under 13. We do not knowingly collect data from
            anyone under 13.
          </Section>

          <Section title="10. Changes to This Policy">
            We may update this policy. We will notify you by email or in-app notice. Continued use
            after changes constitutes acceptance.
          </Section>

          <div style={{
            marginTop: 16, padding: '24px 28px',
            background: 'rgba(122,155,192,0.08)',
            border: '1px solid rgba(122,155,192,0.15)',
            borderRadius: 12,
          }}>
            <p style={{ margin: 0, color: '#7A9BC0', fontSize: 15 }}>
              Questions? Email us at{' '}
              <a href="mailto:interlinked.digital@gmail.com" style={{ color: '#8AAAC8' }}>
                interlinked.digital@gmail.com
              </a>
            </p>
          </div>
        </div>
      </div>
    </main>
  )
}

function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div>
      <h2 style={{
        fontSize: 18, fontWeight: 600, color: '#C8D8E8',
        marginBottom: 12, marginTop: 0, letterSpacing: '-0.01em',
      }}>
        {title}
      </h2>
      <div style={{ color: '#8890AA', lineHeight: 1.8, fontSize: 15 }}>
        {children}
      </div>
    </div>
  )
}
