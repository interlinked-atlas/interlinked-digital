'use client'

import { useState, useEffect, useRef } from 'react'
import { useRouter } from 'next/navigation'
import { createClient } from '@/lib/supabase/client'

// ─── Data ────────────────────────────────────────────────────────────────────

const MONTHLY = {
  standard: {
    price: '$14.99', period: '/mo', priceId: 'atlas-standard',
    features: ['1 device', '10 installs / month', 'TITAN CORE™', 'Storage Manager', '3 Daily Installations', 'Notifications'],
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

const COMPARE_ROWS = [
  { label: 'Cost per file installed',   titan: '$30–$80+ per file',   pro: 'Flat monthly rate' },
  { label: 'Annual cost estimate',       titan: '$1,440+ / year',      pro: '$359.88 / year' },
  { label: 'Wait time',                  titan: 'Long queue — hours',  pro: 'Instant, on your schedule' },
  { label: 'Installation speed',         titan: 'Slow & manual',       pro: 'Automated & intelligent' },
  { label: 'Remote access required',     titan: 'Yes — AnyDesk',       pro: 'Never' },
  { label: 'Privacy',                    titan: 'Stranger on your PC', pro: 'Fully local & private' },
  { label: 'Uninstall & Rollback',       titan: 'Not included',        pro: 'Built-in' },
  { label: 'Virus scanning',             titan: 'Not included',        pro: 'Included (VirusTotal)' },
  { label: 'Install history',            titan: 'None',                pro: 'Full audit trail' },
  { label: 'Bulk installation',          titan: 'Charged per file',    pro: 'Included' },
  { label: 'Works 24/7',                 titan: 'Depends on tech',     pro: 'Always available' },
  { label: 'Scales with your library',   titan: 'Cost grows fast',     pro: 'Same price always' },
]

// ─── Scroll-animate hook ──────────────────────────────────────────────────────

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

// ─── Main page ────────────────────────────────────────────────────────────────

export default function PlansPage() {
  const [annual, setAnnual] = useState(false)
  const [heroIn, setHeroIn] = useState(false)
  const [loggedIn, setLoggedIn] = useState(false)
  const router = useRouter()

  useEffect(() => {
    const t = setTimeout(() => setHeroIn(true), 80)
    const supabase = createClient()
    supabase.auth.getSession().then(({ data }) => {
      setLoggedIn(!!data.session)
    })
    return () => clearTimeout(t)
  }, [])

  function handleSelectPlan(priceId: string) {
    const dest = `/atlas/checkout?plan=${priceId}`
    if (loggedIn) {
      router.push(dest)
    } else {
      router.push(`/auth/login?redirect=${encodeURIComponent(dest)}`)
    }
  }

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

        @keyframes chrome-shift {
          0%   { background-position: 0% 50%; }
          50%  { background-position: 100% 50%; }
          100% { background-position: 0% 50%; }
        }
        .pro-chrome-text {
          background: linear-gradient(90deg,
            #C0C0C0, #FFFFFF, #A8A8A8, #E8E8E8,
            #3ECFB2, #FFFFFF, #B0B0B0, #F0F0F0, #C0C0C0
          );
          background-size: 220% 100%;
          -webkit-background-clip: text;
          -webkit-text-fill-color: transparent;
          background-clip: text;
          animation: chrome-shift 3.2s ease-in-out infinite;
          filter: drop-shadow(0 0 8px rgba(62,207,178,0.45));
        }

        .compare-row:nth-child(odd) { background: rgba(255,255,255,0.015); }
        .compare-row:hover { background: rgba(62,207,178,0.04); }
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
        <section style={{ maxWidth: '860px', margin: '0 auto', padding: '32px 24px 20px', textAlign: 'center' }}>
          <div style={{
            opacity: heroIn ? 1 : 0,
            transform: heroIn ? 'translateY(0)' : 'translateY(20px)',
            transition: 'opacity 0.6s cubic-bezier(0.16,1,0.3,1), transform 0.6s cubic-bezier(0.16,1,0.3,1)',
          }}>
            <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', gap: '12px', marginBottom: '16px' }}>
              <img
                src="/atlas-logo.png"
                alt="ATLAS"
                style={{ width: 28, height: 28, objectFit: 'contain', filter: 'drop-shadow(0 0 10px rgba(62,207,178,0.25))' }}
              />
              <h1 style={{
                fontFamily: "'SF-Intellivised', -apple-system, sans-serif",
                fontSize: '32px',
                fontWeight: 'normal',
                letterSpacing: '10px',
                textIndent: '10px',
                lineHeight: 1,
                margin: 0,
                background: 'linear-gradient(160deg, #FFFFFF 30%, rgba(255,255,255,0.55) 100%)',
                WebkitBackgroundClip: 'text',
                WebkitTextFillColor: 'transparent',
                backgroundClip: 'text',
              }}>
                ATLAS
              </h1>
              <span style={{ fontSize: '10px', color: 'rgba(255,255,255,0.20)', letterSpacing: '2px', textTransform: 'uppercase' }}>
                by InterLinked®
              </span>
            </div>

            <p style={{ fontSize: '13px', color: 'rgba(255,255,255,0.40)', marginBottom: '20px' }}>
              Pick a plan. Start installing.
            </p>

            {/* Billing toggle */}
            <div style={{
              display: 'inline-flex', alignItems: 'center',
              background: 'rgba(255,255,255,0.04)',
              border: '1px solid rgba(255,255,255,0.08)',
              borderRadius: '50px', padding: '3px',
            }}>
              <button
                className="toggle-btn"
                onClick={() => setAnnual(false)}
                style={{
                  padding: '6px 18px', borderRadius: '50px', border: 'none', cursor: 'pointer',
                  background: !annual ? 'rgba(255,255,255,0.10)' : 'transparent',
                  color: !annual ? '#FFFFFF' : '#8A8A96',
                  fontSize: '12px', fontWeight: !annual ? 600 : 400,
                }}
              >Monthly</button>
              <button
                className="toggle-btn"
                onClick={() => setAnnual(true)}
                style={{
                  padding: '6px 18px', borderRadius: '50px', border: 'none', cursor: 'pointer',
                  background: annual ? 'rgba(255,255,255,0.10)' : 'transparent',
                  color: annual ? '#FFFFFF' : '#8A8A96',
                  fontSize: '12px', fontWeight: annual ? 600 : 400,
                  display: 'flex', alignItems: 'center', gap: '6px',
                }}
              >
                Annual
                <span style={{
                  background: '#F0A030', color: '#080809',
                  fontSize: '8px', fontWeight: 800, letterSpacing: '1px',
                  padding: '2px 6px', borderRadius: '50px',
                }}>SAVE</span>
              </button>
            </div>
          </div>
        </section>

        {/* Plan cards */}
        <div style={{ maxWidth: '860px', margin: '0 auto', padding: '0 24px 48px' }}>
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '12px', marginBottom: '16px' }}>

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
                <div style={{ padding: '14px 16px 12px', borderBottom: '1px solid rgba(255,255,255,0.06)' }}>
                  <div style={{ color: '#5E6AD2', fontSize: '9px', fontWeight: 800, letterSpacing: '2px', marginBottom: '8px', textTransform: 'uppercase' }}>
                    Standard
                  </div>
                  <div style={{ display: 'flex', alignItems: 'baseline', gap: '4px', marginBottom: annual ? '4px' : '0' }}>
                    <span style={{ color: '#FFFFFF', fontSize: '24px', fontWeight: 700, letterSpacing: '-0.02em', lineHeight: 1 }}>{std.price}</span>
                    <span style={{ color: '#525260', fontSize: '11px' }}>{std.period}</span>
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

                <div style={{ padding: '12px 16px', flex: 1, display: 'flex', flexDirection: 'column', gap: '7px' }}>
                  {std.features.map(f => (
                    <div key={f} style={{ display: 'flex', gap: '8px', alignItems: 'flex-start' }}>
                      <span style={{ color: '#5E6AD2', fontSize: '9px', fontWeight: 700, marginTop: '2px', flexShrink: 0 }}>✓</span>
                      <span style={{ color: '#CCCCCC', fontSize: '11px', lineHeight: 1.4 }}>{f}</span>
                    </div>
                  ))}
                  {std.excluded.map(f => (
                    <div key={f} style={{ display: 'flex', gap: '8px', alignItems: 'flex-start' }}>
                      <span style={{ color: 'rgba(255,255,255,0.12)', fontSize: '9px', fontWeight: 700, marginTop: '2px', flexShrink: 0 }}>·</span>
                      <span style={{ color: 'rgba(255,255,255,0.18)', fontSize: '11px', lineHeight: 1.4 }}>{f}</span>
                    </div>
                  ))}
                </div>

                <div style={{ padding: '0 12px 12px' }}>
                  <button
                    onClick={() => handleSelectPlan(std.priceId)}
                    className="cta-btn"
                    style={{
                      width: '100%', padding: '9px',
                      borderRadius: '9px',
                      border: '1px solid rgba(94,106,210,0.35)',
                      background: 'rgba(94,106,210,0.10)',
                      color: '#5E6AD2', fontSize: '11px', fontWeight: 700,
                      cursor: 'pointer', letterSpacing: '-0.01em',
                    }}
                  >
                    Get Standard →
                  </button>
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
                <div style={{ background: 'rgba(62,207,178,0.08)', borderBottom: '1px solid rgba(62,207,178,0.15)', padding: '5px 0', textAlign: 'center', color: '#3ECFB2', fontSize: '9px', fontWeight: 800, letterSpacing: '2.5px' }}>
                  MOST POPULAR
                </div>

                <div style={{ padding: '14px 16px 12px', borderBottom: '1px solid rgba(255,255,255,0.06)' }}>
                  <div style={{ fontSize: '9px', fontWeight: 800, letterSpacing: '2px', marginBottom: '8px', textTransform: 'uppercase' }}>
                    <span className="pro-chrome-text">Pro</span>
                  </div>
                  <div style={{ display: 'flex', alignItems: 'baseline', gap: '4px', marginBottom: annual ? '4px' : '0' }}>
                    <span style={{ color: '#FFFFFF', fontSize: '24px', fontWeight: 700, letterSpacing: '-0.02em', lineHeight: 1 }}>{pro.price}</span>
                    <span style={{ color: '#525260', fontSize: '11px' }}>{pro.period}</span>
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

                <div style={{ padding: '12px 16px', flex: 1, display: 'flex', flexDirection: 'column', gap: '7px' }}>
                  {pro.features.map(f => (
                    <div key={f} style={{ display: 'flex', gap: '8px', alignItems: 'flex-start' }}>
                      <span style={{ color: '#3ECFB2', fontSize: '9px', fontWeight: 700, marginTop: '2px', flexShrink: 0 }}>✓</span>
                      <span style={{ color: '#CCCCCC', fontSize: '11px', lineHeight: 1.4 }}>
                        {f.includes('Coming Soon') ? (
                          <>{f.replace(' (Coming Soon)', '')} <span style={{ color: '#F0A030', fontSize: '10px' }}>Coming Soon</span></>
                        ) : f}
                      </span>
                    </div>
                  ))}
                </div>

                <div style={{ padding: '0 12px 12px' }}>
                  <button
                    onClick={() => handleSelectPlan(pro.priceId)}
                    className="cta-btn"
                    style={{
                      width: '100%', padding: '9px',
                      borderRadius: '9px', border: 'none',
                      background: '#3ECFB2',
                      color: '#080809', fontSize: '11px', fontWeight: 700,
                      cursor: 'pointer', letterSpacing: '-0.01em',
                      boxShadow: '0 0 20px rgba(62,207,178,0.22)',
                    }}
                  >
                    Get Pro →
                  </button>
                </div>
              </div>
            </FadeUp>
          </div>

          {/* Footer note under plan cards */}
          <FadeUp delay={160}>
            <div style={{ textAlign: 'center', marginBottom: '64px' }}>
              <p style={{ color: 'rgba(255,255,255,0.18)', fontSize: '11px', marginBottom: '4px' }}>
                Secure payment via Stripe · Cancel anytime · Annual plans billed as a single payment
              </p>
              <p style={{ color: 'rgba(255,255,255,0.18)', fontSize: '11px' }}>
                Already subscribed?{' '}
                <a href="/atlas/account" style={{ color: '#3ECFB2', textDecoration: 'none' }}>Manage your account →</a>
              </p>
            </div>
          </FadeUp>

          {/* ── Comparison Section ─────────────────────────────────────────── */}
          <FadeUp delay={0}>
            <div style={{ textAlign: 'center', marginBottom: '32px' }}>
              <p style={{ color: 'rgba(255,255,255,0.25)', fontSize: '10px', fontWeight: 700, letterSpacing: '3px', textTransform: 'uppercase', marginBottom: '10px' }}>
                Why ATLAS?
              </p>
              <h2 style={{ fontSize: '22px', fontWeight: 700, letterSpacing: '-0.02em', marginBottom: '8px' }}>
                Remote Installation vs{' '}
                <span className="pro-chrome-text" style={{ fontSize: '22px', fontWeight: 700 }}>ATLAS Pro</span>
              </h2>
              <p style={{ color: 'rgba(255,255,255,0.35)', fontSize: '12px', maxWidth: '480px', margin: '0 auto' }}>
                Titan Installation services charge per file and require handing over remote access. ATLAS Pro does it all — privately, instantly, for a flat rate.
              </p>
            </div>
          </FadeUp>

          <FadeUp delay={80}>
            <div style={{
              borderRadius: '16px',
              border: '1px solid rgba(255,255,255,0.07)',
              overflow: 'hidden',
            }}>
              {/* Table header */}
              <div style={{
                display: 'grid',
                gridTemplateColumns: '1fr 1fr 1fr',
                background: '#0E0E10',
                borderBottom: '1px solid rgba(255,255,255,0.08)',
              }}>
                <div style={{ padding: '14px 18px', color: 'rgba(255,255,255,0.30)', fontSize: '10px', fontWeight: 700, letterSpacing: '1.5px', textTransform: 'uppercase' }}>
                  Feature
                </div>
                <div style={{ padding: '14px 18px', textAlign: 'center', borderLeft: '1px solid rgba(255,255,255,0.06)' }}>
                  <div style={{ color: '#E05555', fontSize: '10px', fontWeight: 800, letterSpacing: '1.5px', textTransform: 'uppercase', marginBottom: '2px' }}>
                    ⚠ Titan Installation
                  </div>
                  <div style={{ color: 'rgba(255,255,255,0.25)', fontSize: '9px' }}>Remote / AnyDesk</div>
                </div>
                <div style={{ padding: '14px 18px', textAlign: 'center', borderLeft: '1px solid rgba(62,207,178,0.15)', background: 'rgba(62,207,178,0.04)' }}>
                  <div style={{ fontSize: '10px', fontWeight: 800, letterSpacing: '1.5px', textTransform: 'uppercase', marginBottom: '2px' }}>
                    <span className="pro-chrome-text">✦ ATLAS Pro</span>
                  </div>
                  <div style={{ color: 'rgba(255,255,255,0.25)', fontSize: '9px' }}>Intelligent Installer</div>
                </div>
              </div>

              {/* Rows */}
              {COMPARE_ROWS.map((row, i) => (
                <div
                  key={i}
                  className="compare-row"
                  style={{
                    display: 'grid',
                    gridTemplateColumns: '1fr 1fr 1fr',
                    borderBottom: i < COMPARE_ROWS.length - 1 ? '1px solid rgba(255,255,255,0.04)' : 'none',
                    transition: 'background 0.12s',
                  }}
                >
                  <div style={{ padding: '11px 18px', color: 'rgba(255,255,255,0.55)', fontSize: '11px', fontWeight: 500 }}>
                    {row.label}
                  </div>
                  <div style={{
                    padding: '11px 18px', textAlign: 'center',
                    borderLeft: '1px solid rgba(255,255,255,0.04)',
                    color: '#E05555', fontSize: '11px', fontWeight: 500,
                    display: 'flex', alignItems: 'center', justifyContent: 'center', gap: '5px',
                  }}>
                    <span style={{ color: '#E05555', fontSize: '10px', opacity: 0.6 }}>✕</span>
                    {row.titan}
                  </div>
                  <div style={{
                    padding: '11px 18px', textAlign: 'center',
                    borderLeft: '1px solid rgba(62,207,178,0.10)',
                    background: 'rgba(62,207,178,0.03)',
                    color: '#3ECFB2', fontSize: '11px', fontWeight: 600,
                    display: 'flex', alignItems: 'center', justifyContent: 'center', gap: '5px',
                  }}>
                    <span style={{ fontSize: '10px' }}>✓</span>
                    {row.pro}
                  </div>
                </div>
              ))}
            </div>
          </FadeUp>

          {/* Annual cost callout */}
          <FadeUp delay={120}>
            <div style={{
              marginTop: '16px',
              padding: '18px 24px',
              borderRadius: '14px',
              background: 'rgba(62,207,178,0.06)',
              border: '1px solid rgba(62,207,178,0.15)',
              display: 'flex', alignItems: 'center', justifyContent: 'space-between',
              flexWrap: 'wrap', gap: '12px',
            }}>
              <div>
                <div style={{ color: 'rgba(255,255,255,0.40)', fontSize: '10px', fontWeight: 700, letterSpacing: '2px', textTransform: 'uppercase', marginBottom: '4px' }}>
                  Annual cost comparison
                </div>
                <div style={{ display: 'flex', alignItems: 'baseline', gap: '16px' }}>
                  <span style={{ color: '#E05555', fontSize: '18px', fontWeight: 700 }}>$1,440+</span>
                  <span style={{ color: 'rgba(255,255,255,0.25)', fontSize: '12px' }}>Titan Installation</span>
                  <span style={{ color: 'rgba(255,255,255,0.20)', fontSize: '14px' }}>vs</span>
                  <span style={{ fontSize: '18px', fontWeight: 700 }}>
                    <span className="pro-chrome-text" style={{ fontSize: '18px', fontWeight: 700 }}>$359.88</span>
                  </span>
                  <span style={{ color: 'rgba(255,255,255,0.25)', fontSize: '12px' }}>ATLAS Pro (annual)</span>
                </div>
              </div>
              <button
                onClick={() => handleSelectPlan(annual ? 'atlas-pro-annual' : 'atlas-pro')}
                className="cta-btn"
                style={{
                  padding: '10px 22px',
                  borderRadius: '10px', border: 'none',
                  background: '#3ECFB2',
                  color: '#080809', fontSize: '12px', fontWeight: 700,
                  cursor: 'pointer', whiteSpace: 'nowrap',
                  boxShadow: '0 0 24px rgba(62,207,178,0.25)',
                }}
              >
                Get ATLAS Pro →
              </button>
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
