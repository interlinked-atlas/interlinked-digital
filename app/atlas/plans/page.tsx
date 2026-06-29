'use client'

import { useState } from 'react'
import Link from 'next/link'

const MONTHLY = {
  standard: { price: '$14.99', period: '/mo', priceId: 'atlas-standard' },
  pro:      { price: '$29.99', period: '/mo', priceId: 'atlas-pro' },
}

const ANNUAL = {
  standard: { price: '$12.50', period: '/mo', billed: '$150 billed annually', save: 'Save $30', priceId: 'atlas-standard-annual' },
  pro:      { price: '$25.00', period: '/mo', billed: '$300 billed annually', save: 'Save $60', priceId: 'atlas-pro-annual' },
}

const FEATURES = [
  { label: 'Devices',              standard: '1 device',          pro: 'Up to 3 devices' },
  { label: 'Monthly installs',     standard: '10 / month',        pro: '25 / month' },
  { label: 'TITAN CORE™',          standard: true,                pro: true },
  { label: 'Storage Manager',      standard: true,                pro: true },
  { label: 'Install history',      standard: 'Last 5',            pro: 'Full history' },
  { label: 'Bulk installation',    standard: false,               pro: true },
  { label: 'Uninstall & Rollback', standard: false,               pro: true },
  { label: 'Trash install file',   standard: false,               pro: true },
  { label: 'Widget mode',          standard: false,               pro: true },
  { label: 'Virus Scanner',        standard: false,               pro: true },
  { label: 'File Sharing',         standard: false,               pro: 'Coming Soon' },
]

const BG       = '#07080F'
const CARD     = '#0A0D1C'
const BORDER   = '#1A1D2E'
const TEAL     = '#3ECFB2'
const GOLD     = '#F0A030'
const SUBTLE   = '#8890B0'
const MUTED    = '#4A5070'
const WHITE    = '#E8ECFF'

function Check({ size = 14 }: { size?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 14 14" fill="none">
      <circle cx="7" cy="7" r="7" fill={TEAL} opacity={0.15} />
      <path d="M4 7l2 2 4-4" stroke={TEAL} strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  )
}

function Cross({ size = 14 }: { size?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 14 14" fill="none">
      <circle cx="7" cy="7" r="7" fill={MUTED} opacity={0.1} />
      <path d="M5 5l4 4M9 5l-4 4" stroke={MUTED} strokeWidth="1.5" strokeLinecap="round" />
    </svg>
  )
}

function FeatureValue({ val }: { val: boolean | string }) {
  if (val === true)  return <Check />
  if (val === false) return <Cross />
  return <span style={{ fontSize: 12, color: val === 'Coming Soon' ? GOLD : SUBTLE }}>{val}</span>
}

export default function PlansPage() {
  const [annual, setAnnual] = useState(false)

  const std = annual ? ANNUAL.standard : MONTHLY.standard
  const pro = annual ? ANNUAL.pro      : MONTHLY.pro

  return (
    <div style={{ minHeight: '100vh', background: BG, color: WHITE, fontFamily: "-apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif" }}>

      {/* Nav */}
      <div style={{ padding: '20px 32px', display: 'flex', alignItems: 'center', justifyContent: 'space-between', borderBottom: `1px solid ${BORDER}` }}>
        <Link href="/atlas" style={{ textDecoration: 'none', display: 'flex', alignItems: 'center', gap: 8 }}>
          <span style={{ fontSize: 15, fontWeight: 700, letterSpacing: 4, color: WHITE }}>ATLAS</span>
          <span style={{ fontSize: 10, color: MUTED, letterSpacing: 2 }}>by InterLinked®</span>
        </Link>
        <Link href="/atlas/account" style={{ fontSize: 12, color: SUBTLE, textDecoration: 'none' }}>My Account →</Link>
      </div>

      <div style={{ maxWidth: 900, margin: '0 auto', padding: '60px 24px 80px' }}>

        {/* Header */}
        <div style={{ textAlign: 'center', marginBottom: 48 }}>
          <p style={{ fontSize: 11, letterSpacing: 3, color: TEAL, textTransform: 'uppercase', marginBottom: 12 }}>Pricing</p>
          <h1 style={{ fontSize: 36, fontWeight: 700, letterSpacing: -0.5, marginBottom: 12 }}>Simple, transparent pricing.</h1>
          <p style={{ fontSize: 14, color: SUBTLE, maxWidth: 420, margin: '0 auto' }}>
            Both plans include TITAN CORE™. No hidden fees. Cancel anytime.
          </p>

          {/* Billing toggle */}
          <div style={{ display: 'inline-flex', alignItems: 'center', gap: 12, marginTop: 28, background: CARD, border: `1px solid ${BORDER}`, borderRadius: 50, padding: '6px 8px' }}>
            <button
              onClick={() => setAnnual(false)}
              style={{
                padding: '7px 20px', borderRadius: 50, border: 'none', cursor: 'pointer',
                background: !annual ? WHITE : 'transparent',
                color: !annual ? '#07080F' : SUBTLE,
                fontSize: 12, fontWeight: !annual ? 700 : 400, transition: 'all 0.2s',
              }}
            >Monthly</button>
            <button
              onClick={() => setAnnual(true)}
              style={{
                padding: '7px 20px', borderRadius: 50, border: 'none', cursor: 'pointer',
                background: annual ? WHITE : 'transparent',
                color: annual ? '#07080F' : SUBTLE,
                fontSize: 12, fontWeight: annual ? 700 : 400, transition: 'all 0.2s',
                display: 'flex', alignItems: 'center', gap: 8,
              }}
            >
              Annual
              <span style={{ background: GOLD, color: '#07080F', fontSize: 9, fontWeight: 800, padding: '2px 7px', borderRadius: 50, letterSpacing: 0.5 }}>
                SAVE
              </span>
            </button>
          </div>
        </div>

        {/* Plan cards */}
        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 16, marginBottom: 48 }}>

          {/* Standard */}
          <div style={{ background: CARD, border: `1px solid ${BORDER}`, borderRadius: 16, padding: 28 }}>
            <div style={{ marginBottom: 24 }}>
              <p style={{ fontSize: 11, letterSpacing: 3, color: SUBTLE, textTransform: 'uppercase', marginBottom: 8 }}>Standard</p>
              <div style={{ display: 'flex', alignItems: 'flex-end', gap: 4, marginBottom: 4 }}>
                <span style={{ fontSize: 36, fontWeight: 700, letterSpacing: -1 }}>{std.price}</span>
                <span style={{ fontSize: 13, color: SUBTLE, paddingBottom: 6 }}>{std.period}</span>
              </div>
              {annual && (
                <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                  <p style={{ fontSize: 11, color: SUBTLE }}>{(std as typeof ANNUAL.standard).billed}</p>
                  <span style={{ fontSize: 9, fontWeight: 700, color: GOLD, background: `${GOLD}18`, padding: '2px 7px', borderRadius: 50 }}>
                    {(std as typeof ANNUAL.standard).save}
                  </span>
                </div>
              )}
            </div>

            <Link
              href={`/atlas/checkout?plan=${std.priceId}`}
              style={{
                display: 'block', textAlign: 'center', padding: '11px 0', borderRadius: 10,
                background: 'transparent', border: `1px solid ${BORDER}`,
                color: WHITE, fontSize: 13, fontWeight: 600, textDecoration: 'none',
                marginBottom: 24, transition: 'border-color 0.2s',
              }}
            >
              Get Standard
            </Link>

            <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
              {FEATURES.map(f => (
                <div key={f.label} style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
                  <span style={{ fontSize: 12, color: SUBTLE }}>{f.label}</span>
                  <FeatureValue val={f.standard} />
                </div>
              ))}
            </div>
          </div>

          {/* Pro */}
          <div style={{ background: CARD, border: `1px solid ${TEAL}40`, borderRadius: 16, padding: 28, position: 'relative', overflow: 'hidden' }}>
            <div style={{ position: 'absolute', top: 0, left: 0, right: 0, height: 2, background: `linear-gradient(90deg, ${TEAL}, #2ABEAA)` }} />
            <div style={{ position: 'absolute', top: 14, right: 14 }}>
              <span style={{ fontSize: 9, fontWeight: 800, letterSpacing: 1, color: '#07080F', background: TEAL, padding: '3px 9px', borderRadius: 50, textTransform: 'uppercase' }}>
                Most Popular
              </span>
            </div>

            <div style={{ marginBottom: 24 }}>
              <p style={{ fontSize: 11, letterSpacing: 3, color: TEAL, textTransform: 'uppercase', marginBottom: 8 }}>Pro</p>
              <div style={{ display: 'flex', alignItems: 'flex-end', gap: 4, marginBottom: 4 }}>
                <span style={{ fontSize: 36, fontWeight: 700, letterSpacing: -1 }}>{pro.price}</span>
                <span style={{ fontSize: 13, color: SUBTLE, paddingBottom: 6 }}>{pro.period}</span>
              </div>
              {annual && (
                <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                  <p style={{ fontSize: 11, color: SUBTLE }}>{(pro as typeof ANNUAL.pro).billed}</p>
                  <span style={{ fontSize: 9, fontWeight: 700, color: GOLD, background: `${GOLD}18`, padding: '2px 7px', borderRadius: 50 }}>
                    {(pro as typeof ANNUAL.pro).save}
                  </span>
                </div>
              )}
            </div>

            <Link
              href={`/atlas/checkout?plan=${pro.priceId}`}
              style={{
                display: 'block', textAlign: 'center', padding: '11px 0', borderRadius: 10,
                background: `linear-gradient(135deg, ${TEAL}, #2ABEAA)`,
                color: '#07080F', fontSize: 13, fontWeight: 700, textDecoration: 'none',
                marginBottom: 24,
              }}
            >
              Get Pro
            </Link>

            <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
              {FEATURES.map(f => (
                <div key={f.label} style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
                  <span style={{ fontSize: 12, color: SUBTLE }}>{f.label}</span>
                  <FeatureValue val={f.pro} />
                </div>
              ))}
            </div>
          </div>
        </div>

        {/* Footer note */}
        <div style={{ textAlign: 'center', borderTop: `1px solid ${BORDER}`, paddingTop: 32 }}>
          <p style={{ fontSize: 12, color: MUTED, lineHeight: 1.7 }}>
            Subscriptions renew automatically. Cancel anytime from your account — access ends immediately upon cancellation.
            <br />Annual plans are billed as a single payment. No refunds for unused periods.
          </p>
          <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 24, marginTop: 20 }}>
            <Link href="/atlas/account" style={{ fontSize: 12, color: SUBTLE, textDecoration: 'none' }}>My Account</Link>
            <span style={{ color: BORDER }}>·</span>
            <Link href="/atlas" style={{ fontSize: 12, color: SUBTLE, textDecoration: 'none' }}>Back to ATLAS</Link>
          </div>
        </div>

      </div>
    </div>
  )
}
