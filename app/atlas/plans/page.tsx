'use client'

import { useState, useEffect, useRef } from 'react'
import Link from 'next/link'

// ─── Data ───────────────────────────────────────────────────────────────────

const MONTHLY = {
  standard: {
    price: '$14.99', period: '/mo', priceId: 'atlas-standard',
    features: ['1 device', '10 installs / month', 'TITAN CORE™', 'Storage Manager', 'Install history (last 5)', 'Notifications'],
    excluded: ['Bulk installation', 'Uninstall & Rollback', 'Trash install file', 'Widget mode', 'Virus Scanner', 'File Sharing'],
  },
  pro: {
    price: '$29.99', period: '/mo', priceId: 'atlas-pro',
    features: ['Up to 3 devices', '25 installs / month', 'TITAN CORE™', 'Storage Manager', 'Full install history', 'Bulk installation', 'Uninstall & Rollback', 'Trash install file', 'Widget mode', 'Virus Scanner', 'File Sharing (Coming Soon)'],
    excluded: [],
  },
}

const ANNUAL = {
  standard: {
    price: '$12.50', period: '/mo', billed: '$150 billed annually', save: 'Save $30', priceId: 'atlas-standard-annual',
    features: MONTHLY.standard.features,
    excluded: MONTHLY.standard.excluded,
  },
  pro: {
    price: '$25.00', period: '/mo', billed: '$300 billed annually', save: 'Save $60', priceId: 'atlas-pro-annual',
    features: MONTHLY.pro.features,
    excluded: MONTHLY.pro.excluded,
  },
}

// ─── Scroll-animate hook ─────────────────────────────────────────────────────

function useInView(ref: React.RefObject<Element | null>, once = true) {
  const [visible, setVisible] = useState(false)
  useEffect(() => {
    if (!ref.current) return
    const obs = new IntersectionObserver(
      ([entry]) => {
        if (entry.isIntersecting) { setVisible(true); if (once) obs.disconnect() }
        else if (!once) setVisible(false)
      },
      { threshold: 0.12, rootMargin: '0px 0px -32px 0px' }
    )
    obs.observe(ref.current)
    return () => obs.disconnect()
  }, [ref, once])
  return visible
}

function FadeUp({ children, delay = 0, style = {} }: { children: React.ReactNode; delay?: number; style?: React.CSSProperties }) {
  const ref = useRef<HTMLDivElement>(null)
  const visible = useInView(ref)
  return (
    <div ref={ref} style={{
      opacity: visible ? 1 : 0,
      transform: visible ? 'translateY(0)' : 'translateY(28px)',
      transition: `opacity 0.65s cubic-bezier(0.16,1,0.3,1) ${delay}ms, transform 0.65s cubic-bezier(0.16,1,0.3,1) ${delay}ms`,
      ...style,
    }}>
      {children}
    </div>
  )
}

// ─── Main page ───────────────────────────────────────────────────────────────

export default function PlansPage() {
  const [annual, setAnnual] = useState(false)
  const [heroIn, setHeroIn] = useState(false)

  useEffect(() => {
    const t = setTimeout(() => setHeroIn(true), 80)
    return () => clearTimeout(t)
  }, [])

  const std = annual ? ANNUAL.standard : MONTHLY.standard
  const pro = annual ? ANNUAL.pro      : MONTHLY.pro

  return (
    <>
      <style>{`
        @font-face {
          font-family: 'SF-Intellivised';
          src: url('/fonts/SF-Intellivised.ttf') format('truetype');
          font-weight: normal; font-style: normal; font-display: swap;
        }
        *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
        html { scroll-behavior: smooth; }
        body { background: #080809; color: #FFFFFF; }
        ::selection { background: rgba(62,207,178,0.25); }
        ::-webkit-scrollbar { width: 6px; }
        ::-webkit-scrollbar-track { background: transparent; }
        ::-webkit-scrollbar-thumb { background: rgba(255,255,255,0.10); border-radius: 3px; }
        .plan-card { transition: border-color 0.2s ease, transform 0.2s cubic-bezier(0.16,1,0.3,1), box-shadow 0.2s ease; }
        .plan-card:hover { transform: translateY(-3px); }
        .cta-btn { transition: opacity 0.15s, transform 0.15s cubic-bezier(0.16,1,0.3,1); }
        .cta-btn:hover { opacity: 0.88; transform: translateY(-1px); }
        .cta-btn:active { transform: scale(0.98); }
        .toggle-btn { transition: background 0.2s, color 0.2s; }
        .nav-link { transition: color 0.12s; }
        .nav-link:hover { color: #FFFFFF !important; }
      `}</style>

      <main style={{
        minHeight: '100vh',
        background: '#080809',
        fontFamily: '"Inter", -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif',
        WebkitFontSmoothing: 'antialiased',
      }}>

        {/* Nav */}
        <nav style={{
          position: 'sticky', top: 0, zIndex: 50,
          background: 'rgba(8,8,9,0.85)',
          backdropFilter: 'blur(20px)',
          borderBottom: '1px solid rgba(255,255,255,0.06)',
          padding: '0 24px',
          display: 'flex', alignItems: 'center', justifyContent: 'space-between',
          height: '52px',
        }}>
          <a
            href="/atlas"
            className="nav-link"
            style={{ display: 'flex', alignItems: 'center', gap: '7px', color: '#8A8A96', fontSize: '13px', fontWeight: 500, textDecoration: 'none' }}
          >
            <svg width="14" height="14" viewBox="0 0 14 14" fill="none" style={{ flexShrink: 0 }}>
              <path d="M9 2L4 7L9 12" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" />
            </svg>
            Back to ATLAS
          </a>
          <a
            href="/atlas/account"
            className="nav-link"
            style={{ color: '#8A8A96', fontSize: '13px', fontWeight: 500, textDecoration: 'none' }}
          >
            My Account
          </a>
        </nav>

        {/* Hero */}
        <section style={{ maxWidth: '860px', margin: '0 auto', padding: '80px 24px 60px', textAlign: 'center' }}>
          <div style={{
            opacity: heroIn ? 1 : 0,
            transform: heroIn ? 'translateY(0)' : 'translateY(32px)',
            transition: 'opacity 0.8s cubic-bezier(0.16,1,0.3,1), transform 0.8s cubic-bezier(0.16,1,0.3,1)',
          }}>
            <div style={{ marginBottom: '20px', display: 'flex', justifyContent: 'center' }}>
              <img
                src="/atlas-logo.png"
                alt="ATLAS"
                style={{ width: 56, height: 56, objectFit: 'contain', filter: 'drop-shadow(0 0 20px rgba(62,207,178,0.22))' }}
              />
            </div>

            <p style={{ fontSize: '11px', fontWeight: 600, letterSpacing: '3px', textTransform: 'uppercase', color: '#3ECFB2', marginBottom: '16px' }}>
              Pricing
            </p>

            <h1 style={{
              fontFamily: "'SF-Intellivised', -apple-system, sans-serif",
              fontSize: 'clamp(48px, 8vw, 80px)',
              fontWeight: 'normal',
              letterSpacing: 'clamp(10px, 2vw, 20px)',
              textIndent: 'clamp(10px, 2vw, 20px)',
              lineHeight: 1,
              marginBottom: '24px',
              background: 'linear-gradient(160deg, #FFFFFF 30%, rgba(255,255,255,0.55) 100%)',
              WebkitBackgroundClip: 'text',
              WebkitTextFillColor: 'transparent',
              backgroundClip: 'text',
            }}>
              ATLAS
            </h1>

            <p style={{ fontSize: '15px', color: 'rgba(255,255,255,0.45)', letterSpacing: '-0.01em', lineHeight: 1.6, maxWidth: '400px', margin: '0 auto 14px' }}>
              Pick a plan. Start installing.
            </p>
            <p style={{ fontSize: '12px', color: 'rgba(255,255,255,0.20)', letterSpacing: '2px', textTransform: 'uppercase', marginBottom: '40px' }}>
              by InterLinked®
            </p>

            {/* Billing toggle */}
            <div style={{
              display: 'inline-flex', alignItems: 'center',
              background: 'rgba(255,255,255,0.04)',
              border: '1px solid rgba(255,255,255,0.08)',
              borderRadius: '50px', padding: '4px',
            }}>
              <button
                className="toggle-btn"
                onClick={() => setAnnual(false)}
                style={{
                  padding: '8px 22px', borderRadius: '50px', border: 'none', cursor: 'pointer',
                  background: !annual ? 'rgba(255,255,255,0.10)' : 'transparent',
                  color: !annual ? '#FFFFFF' : '#8A8A96',
                  fontSize: '13px', fontWeight: !annual ? 600 : 400,
                }}
              >Monthly</button>
              <button
                className="toggle-btn"
                onClick={() => setAnnual(true)}
                style={{
                  padding: '8px 22px', borderRadius: '50px', border: 'none', cursor: 'pointer',
                  background: annual ? 'rgba(255,255,255,0.10)' : 'transparent',
                  color: annual ? '#FFFFFF' : '#8A8A96',
                  fontSize: '13px', fontWeight: annual ? 600 : 400,
                  display: 'flex', alignItems: 'center', gap: '8px',
                }}
              >
                Annual
                <span style={{
                  background: '#F0A030', color: '#080809',
                  fontSize: '8px', fontWeight: 800, letterSpacing: '1px',
                  padding: '2px 7px', borderRadius: '50px',
                }}>SAVE</span>
              </button>
            </div>
          </div>
        </section>

        {/* Plan cards */}
        <div style={{ maxWidth: '780px', margin: '0 auto', padding: '0 24px 80px' }}>
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '14px', marginBottom: '24px' }}>

            {/* Standard */}
            <FadeUp delay={0}>
              <div className="plan-card" style={{
                background: '#0E0E10',
                borderRadius: '16px',
                border: '1px solid rgba(255,255,255,0.07)',
                overflow: 'hidden',
                display: 'flex', flexDirection: 'column',
                height: '100%',
              }}>
                <div style={{ padding: '20px 20px 16px', borderBottom: '1px solid rgba(255,255,255,0.06)' }}>
                  <div style={{ color: '#5E6AD2', fontSize: '9px', fontWeight: 800, letterSpacing: '2px', marginBottom: '12px', textTransform: 'uppercase' }}>
                    Standard
                  </div>
                  <div style={{ display: 'flex', alignItems: 'baseline', gap: '4px', marginBottom: annual ? '6px' : '0' }}>
                    <span style={{ color: '#FFFFFF', fontSize: '30px', fontWeight: 700, letterSpacing: '-0.02em', lineHeight: 1 }}>{std.price}</span>
                    <span style={{ color: '#525260', fontSize: '12px' }}>{std.period}</span>
                  </div>
                  {annual && (
                    <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                      <span style={{ color: '#525260', fontSize: '11px' }}>{(std as typeof ANNUAL.standard).billed}</span>
                      <span style={{ background: 'rgba(240,160,48,0.15)', color: '#F0A030', fontSize: '9px', fontWeight: 700, padding: '2px 7px', borderRadius: '50px' }}>
                        {(std as typeof ANNUAL.standard).save}
                      </span>
                    </div>
                  )}
                </div>

                <div style={{ padding: '16px 20px', flex: 1, display: 'flex', flexDirection: 'column', gap: '9px' }}>
                  {std.features.map(f => (
                    <div key={f} style={{ display: 'flex', gap: '10px', alignItems: 'flex-start' }}>
                      <span style={{ color: '#5E6AD2', fontSize: '10px', fontWeight: 700, marginTop: '2px', flexShrink: 0 }}>✓</span>
                      <span style={{ color: '#CCCCCC', fontSize: '12px', lineHeight: 1.45 }}>{f}</span>
                    </div>
                  ))}
                  {std.excluded.map(f => (
                    <div key={f} style={{ display: 'flex', gap: '10px', alignItems: 'flex-start' }}>
                      <span style={{ color: 'rgba(255,255,255,0.12)', fontSize: '10px', fontWeight: 700, marginTop: '2px', flexShrink: 0 }}>·</span>
                      <span style={{ color: 'rgba(255,255,255,0.18)', fontSize: '12px', lineHeight: 1.45 }}>{f}</span>
                    </div>
                  ))}
                </div>

                <div style={{ padding: '0 16px 16px' }}>
                  <Link
                    href={`/atlas/checkout?plan=${std.priceId}`}
                    className="cta-btn"
                    style={{
                      display: 'block', textAlign: 'center', width: '100%', padding: '10px',
                      borderRadius: '10px',
                      border: '1px solid rgba(94,106,210,0.35)',
                      background: 'rgba(94,106,210,0.10)',
                      color: '#5E6AD2', fontSize: '12px', fontWeight: 700,
                      textDecoration: 'none', letterSpacing: '-0.01em',
                    }}
                  >
                    Get Standard →
                  </Link>
                </div>
              </div>
            </FadeUp>

            {/* Pro */}
            <FadeUp delay={80}>
              <div className="plan-card" style={{
                background: '#0E0E10',
                borderRadius: '16px',
                border: '1px solid rgba(62,207,178,0.25)',
                overflow: 'hidden',
                display: 'flex', flexDirection: 'column',
                height: '100%',
                boxShadow: '0 0 40px rgba(62,207,178,0.06)',
              }}>
                <div style={{ background: 'rgba(62,207,178,0.08)', borderBottom: '1px solid rgba(62,207,178,0.15)', padding: '6px 0', textAlign: 'center', color: '#3ECFB2', fontSize: '9px', fontWeight: 800, letterSpacing: '2.5px' }}>
                  MOST POPULAR
                </div>

                <div style={{ padding: '20px 20px 16px', borderBottom: '1px solid rgba(255,255,255,0.06)' }}>
                  <div style={{ color: '#3ECFB2', fontSize: '9px', fontWeight: 800, letterSpacing: '2px', marginBottom: '12px', textTransform: 'uppercase' }}>
                    Pro
                  </div>
                  <div style={{ display: 'flex', alignItems: 'baseline', gap: '4px', marginBottom: annual ? '6px' : '0' }}>
                    <span style={{ color: '#FFFFFF', fontSize: '30px', fontWeight: 700, letterSpacing: '-0.02em', lineHeight: 1 }}>{pro.price}</span>
                    <span style={{ color: '#525260', fontSize: '12px' }}>{pro.period}</span>
                  </div>
                  {annual && (
                    <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                      <span style={{ color: '#525260', fontSize: '11px' }}>{(pro as typeof ANNUAL.pro).billed}</span>
                      <span style={{ background: 'rgba(240,160,48,0.15)', color: '#F0A030', fontSize: '9px', fontWeight: 700, padding: '2px 7px', borderRadius: '50px' }}>
                        {(pro as typeof ANNUAL.pro).save}
                      </span>
                    </div>
                  )}
                </div>

                <div style={{ padding: '16px 20px', flex: 1, display: 'flex', flexDirection: 'column', gap: '9px' }}>
                  {pro.features.map(f => (
                    <div key={f} style={{ display: 'flex', gap: '10px', alignItems: 'flex-start' }}>
                      <span style={{ color: '#3ECFB2', fontSize: '10px', fontWeight: 700, marginTop: '2px', flexShrink: 0 }}>✓</span>
                      <span style={{ color: '#CCCCCC', fontSize: '12px', lineHeight: 1.45 }}>
                        {f.includes('Coming Soon') ? (
                          <>{f.replace(' (Coming Soon)', '')} <span style={{ color: '#F0A030', fontSize: '10px' }}>Coming Soon</span></>
                        ) : f}
                      </span>
                    </div>
                  ))}
                </div>

                <div style={{ padding: '0 16px 16px' }}>
                  <Link
                    href={`/atlas/checkout?plan=${pro.priceId}`}
                    className="cta-btn"
                    style={{
                      display: 'block', textAlign: 'center', width: '100%', padding: '10px',
                      borderRadius: '10px', border: 'none',
                      background: '#3ECFB2',
                      color: '#080809', fontSize: '12px', fontWeight: 700,
                      textDecoration: 'none', letterSpacing: '-0.01em',
                      boxShadow: '0 0 24px rgba(62,207,178,0.25)',
                    }}
                  >
                    Get Pro →
                  </Link>
                </div>
              </div>
            </FadeUp>
          </div>

          {/* Footer note */}
          <FadeUp delay={160}>
            <div style={{ textAlign: 'center' }}>
              <p style={{ color: 'rgba(255,255,255,0.20)', fontSize: '12px', marginBottom: '6px' }}>
                Secure payment via Stripe · Cancel anytime · Access ends immediately on cancellation
              </p>
              <p style={{ color: 'rgba(255,255,255,0.20)', fontSize: '12px' }}>
                Annual plans are billed as a single payment · No refunds for unused periods
              </p>
              <p style={{ color: 'rgba(255,255,255,0.20)', fontSize: '12px', marginTop: '6px' }}>
                Already subscribed?{' '}
                <a href="/atlas/account" style={{ color: '#3ECFB2', textDecoration: 'none' }}>Manage your account →</a>
              </p>
            </div>
          </FadeUp>
        </div>

        <footer style={{ borderTop: '1px solid rgba(255,255,255,0.05)', padding: '24px', textAlign: 'center' }}>
          <p style={{ color: 'rgba(255,255,255,0.15)', fontSize: '11px', letterSpacing: '0.02em' }}>
            InterLinked® · All rights reserved
          </p>
        </footer>

      </main>
    </>
  )
}
