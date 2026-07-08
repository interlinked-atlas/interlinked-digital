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

        <div style={{ display: 'flex', flexDirection: 'column', gap: 40 }}>

          <Section title="1. Agreement">
            By creating an account or using ATLAS, you agree to these Terms of Service ("Terms").
            If you do not agree, do not use ATLAS.
          </Section>

          <Section title="2. The Service">
            ATLAS is a macOS and Windows application that automates software installation.
            Access to ATLAS requires an active paid subscription. Features available to you
            depend on your subscription plan (Standard or Pro).
          </Section>

          <Section title="3. Subscriptions and Billing">
            <ul style={{ marginTop: 16, paddingLeft: 20, lineHeight: 2, color: '#B0B8D0' }}>
              <li>Subscriptions are billed monthly or annually depending on the plan you select.</li>
              <li>Billing is processed by Stripe. By subscribing, you authorize Stripe to charge
              your payment method on a recurring basis.</li>
              <li>Your subscription renews automatically on your billing date unless cancelled.</li>
            </ul>
            <div style={{
              marginTop: 20, padding: '18px 22px',
              background: 'rgba(224,85,85,0.08)',
              border: '1px solid rgba(224,85,85,0.2)',
              borderRadius: 10,
              color: '#E8A0A0', fontSize: 15, lineHeight: 1.7,
            }}>
              <strong style={{ color: '#E05555' }}>All payments are final and non-refundable.</strong>
              {' '}We do not issue refunds or credits for any reason, including unused subscription
              time, accidental purchases, or dissatisfaction with the service.
            </div>
          </Section>

          <Section title="4. Cancellation">
            You may cancel your subscription at any time through your account settings at{' '}
            <a href="/atlas/account" style={{ color: '#7A9BC0' }}>interlinked.digital/atlas/account</a>{' '}
            or by contacting us. Upon cancellation, your access to ATLAS is terminated{' '}
            <strong style={{ color: '#C8D8E8' }}>immediately</strong>. You will not be charged
            again after cancellation. No refund is issued for the remaining period.
          </Section>

          <Section title="5. Payment Failure">
            If your payment method fails, your access to ATLAS will be suspended immediately.
            You must update your billing information to restore access. We do not offer grace periods.
          </Section>

          <Section title="6. Device Limits">
            <ul style={{ marginTop: 16, paddingLeft: 20, lineHeight: 2, color: '#B0B8D0' }}>
              <li><strong style={{ color: '#C8D8E8' }}>Standard plan:</strong> 1 device</li>
              <li><strong style={{ color: '#C8D8E8' }}>Pro plan:</strong> 3 devices</li>
            </ul>
            Attempting to use ATLAS on more devices than your plan allows will result in a login
            block. You may remove devices from your account settings.
          </Section>

          <Section title="7. Acceptable Use">
            You agree not to:
            <ul style={{ marginTop: 16, paddingLeft: 20, lineHeight: 2, color: '#B0B8D0' }}>
              <li>Reverse engineer, decompile, or disassemble ATLAS</li>
              <li>Share your account credentials with others</li>
              <li>Use ATLAS for any unlawful purpose</li>
              <li>Circumvent device limits or subscription enforcement</li>
            </ul>
          </Section>

          <Section title="8. Intellectual Property">
            ATLAS, its name, logo, TITAN MEMORY™, and TITAN CORE™ are proprietary to
            Interlinked Digital. You are granted a limited, non-exclusive, non-transferable
            license to use ATLAS while your subscription is active.
          </Section>

          <Section title="9. Disclaimer of Warranties">
            ATLAS is provided "as is." We make no warranties, express or implied, including
            warranties of merchantability or fitness for a particular purpose. We do not
            guarantee that ATLAS will be error-free or uninterrupted.
          </Section>

          <Section title="10. Limitation of Liability">
            To the maximum extent permitted by law, Interlinked Digital shall not be liable
            for any indirect, incidental, special, consequential, or punitive damages. Our
            total liability to you shall not exceed the amount you paid in the 3 months
            prior to the claim.
          </Section>

          <Section title="11. Termination">
            We reserve the right to suspend or terminate your account at any time for
            violation of these Terms, with or without notice.
          </Section>

          <Section title="12. Governing Law">
            These Terms are governed by the laws of the United States. Any disputes shall be
            resolved in the jurisdiction where Interlinked Digital operates.
          </Section>

          <Section title="13. Changes">
            We may modify these Terms at any time. We will notify you by email or in-app
            notice at least 7 days before material changes take effect. Continued use after
            the effective date constitutes acceptance.
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
