'use client'

import { useState, useEffect, useRef } from 'react'
import { useRouter } from 'next/navigation'
import { createClient } from '@/lib/supabase/client'

// ─── Data ────────────────────────────────────────────────────────────────────

const MONTHLY = {
  price: '$30', period: '/mo', priceId: 'atlas',
  features: [
    'Up to 3 devices',
    '25 installs / month',
    'TITAN CORE™',
    'Smart Storage',
    'Full install history',
    'Bulk installation',
    'Uninstall & Rollback',
    'Trash install file',
    'ATLAS CLEANER™',
    'ATLAS RECOVERY KIT™',
    'Cloud Backup',
    'Built-In Virus Scanner',
    'File Sharing (Coming Soon)',
  ],
}

const ANNUAL = {
  price: '$25', period: '/mo', billed: '$300 billed annually', save: 'Save $60', priceId: 'atlas-annual',
  features: MONTHLY.features,
}

const COMPARE_ROWS = [
  { label: 'Cost per file installed',   titan: '$30–$80+ per file',   atlas: 'Flat monthly rate' },
  { label: 'Annual cost estimate',       titan: '$1,440+ / year',      atlas: '$300 / year' },
  { label: 'Wait time',                  titan: 'Long queue — hours',  atlas: 'Instant, on your schedule' },
  { label: 'Installation speed',         titan: 'Slow & manual',       atlas: 'Automated & intelligent' },
  { label: 'Remote access required',     titan: 'Yes — AnyDesk',       atlas: 'Never' },
  { label: 'Privacy',                    titan: 'Stranger on your PC', atlas: 'Fully local & private' },
  { label: 'Uninstall & Rollback',       titan: 'Not included',        atlas: 'Built-in' },
  { label: 'Virus scanning',             titan: 'Not included',        atlas: 'Included (VirusTotal)' },
  { label: 'Install history',            titan: 'None',                atlas: 'Full audit trail' },
  { label: 'Bulk installation',          titan: 'Charged per file',    atlas: 'Included' },
  { label: 'Works 24/7',                 titan: 'Depends on tech',     atlas: 'Always available' },
  { label: 'Scales with your library',   titan: 'Cost grows fast',     atlas: 'Same price always' },
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
  const [hintVisible, setHintVisible] = useState(false)
  const compareRef = useRef<HTMLDivElement>(null)
  const router = useRouter()

  useEffect(() => {
    const t = setTimeout(() => setHeroIn(true), 80)
    const hintTimer = setTimeout(() => setHintVisible(true), 900)

    const supabase = createClient()
    supabase.auth.getSession().then(({ data }) => {
      setLoggedIn(!!data.session)
    })

    const obs = new IntersectionObserver(
      ([entry]) => { if (entry.isIntersecting) setHintVisible(false) },
      { threshold: 0.1 }
    )
    if (compareRef.current) obs.observe(compareRef.current)

    return () => {
      clearTimeout(t)
      clearTimeout(hintTimer)
      obs.disconnect()
    }
  }, [])

  function handleSelectPlan(priceId: string) {
    const dest = `/atlas/checkout?plan=${priceId}`
    if (loggedIn) {
      router.push(dest)
    } else {
      router.push(`/auth/login?redirect=${encodeURIComponent(dest)}`)
    }
  }

  function scrollToCompare() {
    compareRef.current?.scrollIntoView({ behavior: 'smooth', block: 'start' })
  }

  const plan = annual ? ANNUAL : MONTHLY

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
        .atlas-chrome-text {
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

        @keyframes bounce-down {
          0%, 100% { transform: translateY(0); }
          50%       { transform: translateY(5px); }
        }
        .bounce-arrow { animation: bounce-down 1.5s ease-in-out infinite; display: inline-block; }

        .compare-row:nth-child(odd) { background: rgba(255,255,255,0.015); }
        .compare-row:hover { background: rgba(62,207,178,0.04); }

        .scroll-hint-bar {
          transition: opacity 0.4s ease, transform 0.4s cubic-bezier(0.16,1,0.3,1);
        }
        .scroll-hint-bar:hover { opacity: 0.85 !important; }
      `}</style>

      {/* ── Fixed bottom scroll hint ── */}
      <button
        onClick={scrollToCompare}
        className="scroll-hint-bar"
        style={{
          position: 'fixed',
          bottom: '24px',
          left: '50%',
          transform: hintVisible ? 'translateX(-50%) translateY(0)' : 'translateX(-50%) translateY(16px)',
          zIndex: 100,
          opacity: hintVisible ? 1 : 0,
          pointerEvents: hintVisible ? 'auto' : 'none',
          background: 'rgba(14,14,16,0.92)',
          backdropFilter: 'blur(16px)',
          border: '1px solid rgba(62,207,178,0.22)',
          borderRadius: '50px',
          padding: '10px 20px',
          cursor: 'pointer',
          display: 'flex', alignItems: 'center', gap: '10px',
          boxShadow: '0 4px 24px rgba(0,0,0,0.5), 0 0 0 1px rgba(62,207,178,0.08)',
        }}
      >
        <span style={{ color: 'rgba(255,255,255,0.55)', fontSize: '13px', fontWeight: 500, fontFamily: '"Inter", sans-serif', whiteSpace: 'nowrap' }}>
          Why not just hire someone?
        </span>
        <span style={{ color: 'rgba(255,255,255,0.25)', fontSize: '12px', fontFamily: '"Inter", sans-serif', whiteSpace: 'nowrap' }}>
          See the breakdown
        </span>
        <span className="bounce-arrow">
          <svg width="14" height="14" viewBox="0 0 14 14" fill="none">
            <path d="M2 5L7 10L12 5" stroke="rgba(62,207,178,0.8)" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round"/>
          </svg>
        </span>
      </button>

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
            style={{ display: 'flex', alignItems: 'center', gap: '7px', color: '#8A8A96', fontSize: '14px', fontWeight: 500, textDecoration: 'none' }}
          >
            <svg width="14" height="14" viewBox="0 0 14 14" fill="none" style={{ flexShrink: 0 }}>
              <path d="M9 2L4 7L9 12" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" />
            </svg>
            Back to ATLAS
          </a>
          <a
            href="/atlas/account"
            className="nav-link"
            style={{ color: '#8A8A96', fontSize: '14px', fontWeight: 500, textDecoration: 'none' }}
          >
            My Account
          </a>
        </nav>

        {/* Hero */}
        <section style={{ maxWidth: '600px', margin: '0 auto', padding: '32px 24px 20px', textAlign: 'center' }}>
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

            <p style={{ fontSize: '14px', color: 'rgba(255,255,255,0.40)', marginBottom: '20px' }}>
              One plan. Everything included.
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
                  fontSize: '13px', fontWeight: !annual ? 600 : 400,
                }}
              >Monthly</button>
              <button
                className="toggle-btn"
                onClick={() => setAnnual(true)}
                style={{
                  padding: '6px 18px', borderRadius: '50px', border: 'none', cursor: 'pointer',
                  background: annual ? 'rgba(255,255,255,0.10)' : 'transparent',
                  color: annual ? '#FFFFFF' : '#8A8A96',
                  fontSize: '13px', fontWeight: annual ? 600 : 400,
                  display: 'flex', alignItems: 'center', gap: '6px',
                }}
              >
                Annual
                <span style={{
                  background: '#F0A030', color: '#080809',
                  fontSize: '8px', fontWeight: 800, letterSpacing: '1px',
                  padding: '2px 6px', borderRadius: '50px',
                }}>SAVE $60</span>
              </button>
            </div>
          </div>
        </section>

        {/* Plan card */}
        <div style={{ maxWidth: '480px', margin: '0 auto', padding: '0 24px 80px' }}>
          <FadeUp delay={0}>
            <div className="plan-card" style={{
              background: '#0E0E10',
              borderRadius: '16px',
              border: '1px solid rgba(62,207,178,0.25)',
              overflow: 'hidden',
              display: 'flex', flexDirection: 'column',
              boxShadow: '0 0 40px rgba(62,207,178,0.06)',
            }}>
              {/* Most popular banner */}
              <div style={{ background: 'rgba(62,207,178,0.08)', borderBottom: '1px solid rgba(62,207,178,0.15)', padding: '5px 0', textAlign: 'center', color: '#3ECFB2', fontSize: '10px', fontWeight: 800, letterSpacing: '2.5px' }}>
                EVERYTHING INCLUDED
              </div>

              <div style={{ padding: '14px 16px 12px', borderBottom: '1px solid rgba(255,255,255,0.06)' }}>
                <div style={{ fontSize: '10px', fontWeight: 800, letterSpacing: '2px', marginBottom: '8px', textTransform: 'uppercase' }}>
                  <span className="atlas-chrome-text">ATLAS</span>
                </div>
                <div style={{ display: 'flex', alignItems: 'baseline', gap: '4px', marginBottom: annual ? '4px' : '0' }}>
                  <span style={{ color: '#FFFFFF', fontSize: '26px', fontWeight: 700, letterSpacing: '-0.02em', lineHeight: 1 }}>{plan.price}</span>
                  <span style={{ color: '#525260', fontSize: '12px' }}>{plan.period}</span>
                </div>
                {annual && (
                  <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                    <span style={{ color: '#525260', fontSize: '12px' }}>{(plan as typeof ANNUAL).billed}</span>
                    <span style={{ background: 'rgba(240,160,48,0.15)', color: '#F0A030', fontSize: '10px', fontWeight: 700, padding: '2px 7px', borderRadius: '50px' }}>
                      {(plan as typeof ANNUAL).save}
                    </span>
                  </div>
                )}
              </div>

              <div style={{ padding: '12px 16px', flex: 1, display: 'flex', flexDirection: 'column', gap: '8px' }}>
                {plan.features.map(f => (
                  <div key={f} style={{ display: 'flex', gap: '8px', alignItems: 'flex-start' }}>
                    <span style={{ color: '#3ECFB2', fontSize: '10px', fontWeight: 700, marginTop: '2px', flexShrink: 0 }}>✓</span>
                    <span style={{ color: '#CCCCCC', fontSize: '13px', lineHeight: 1.4 }}>
                      {f.includes('Coming Soon') ? (
                        <>{f.replace(' (Coming Soon)', '')} <span style={{ color: '#F0A030', fontSize: '11px' }}>Coming Soon</span></>
                      ) : f}
                    </span>
                  </div>
                ))}
              </div>

              <div style={{ padding: '0 12px 12px' }}>
                <button
                  onClick={() => handleSelectPlan(plan.priceId)}
                  className="cta-btn"
                  style={{
                    width: '100%', padding: '10px',
                    borderRadius: '9px', border: 'none',
                    background: '#3ECFB2',
                    color: '#080809', fontSize: '13px', fontWeight: 700,
                    cursor: 'pointer', letterSpacing: '-0.01em',
                    boxShadow: '0 0 20px rgba(62,207,178,0.22)',
                  }}
                >
                  {annual ? 'Get ATLAS Annual →' : 'Get ATLAS →'}
                </button>
              </div>
            </div>
          </FadeUp>

          {/* Footer note */}
          <FadeUp delay={80}>
            <div style={{ textAlign: 'center', marginTop: '16px' }}>
              <p style={{ color: 'rgba(255,255,255,0.18)', fontSize: '12px', marginBottom: '4px' }}>
                Secure payment via Stripe · Cancel anytime · Annual plans billed as a single payment
              </p>
              <p style={{ color: 'rgba(255,255,255,0.18)', fontSize: '12px' }}>
                Already subscribed?{' '}
                <a href="/atlas/account" style={{ color: '#3ECFB2', textDecoration: 'none' }}>Manage your account →</a>
              </p>
            </div>
          </FadeUp>

          {/* ── Comparison Section ─────────────────────────────────────────── */}
          <div ref={compareRef} style={{ scrollMarginTop: '72px', paddingTop: '64px' }}>
            <FadeUp delay={0}>
              <div style={{ textAlign: 'center', marginBottom: '32px' }}>
                <p style={{ color: 'rgba(255,255,255,0.25)', fontSize: '11px', fontWeight: 700, letterSpacing: '3px', textTransform: 'uppercase', marginBottom: '12px' }}>
                  Why ATLAS?
                </p>
                <h2 style={{ fontSize: '26px', fontWeight: 700, letterSpacing: '-0.02em', marginBottom: '10px' }}>
                  Remote Installation vs{' '}
                  <span className="atlas-chrome-text" style={{ fontSize: '26px', fontWeight: 700 }}>ATLAS</span>
                </h2>
                <p style={{ color: 'rgba(255,255,255,0.35)', fontSize: '14px', maxWidth: '500px', margin: '0 auto', lineHeight: 1.6 }}>
                  Remote install services charge per file and require handing over access to your machine. ATLAS handles everything — privately, instantly, for one flat rate.
                </p>
              </div>
            </FadeUp>

            <FadeUp delay={80}>
              <div style={{
                borderRadius: '16px',
                border: '1px solid rgba(255,255,255,0.07)',
                overflow: 'hidden',
                maxWidth: '860px',
                margin: '0 auto',
              }}>
                {/* Table header */}
                <div style={{
                  display: 'grid',
                  gridTemplateColumns: '1fr 1fr 1fr',
                  background: '#0E0E10',
                  borderBottom: '1px solid rgba(255,255,255,0.08)',
                }}>
                  <div style={{ padding: '16px 20px', color: 'rgba(255,255,255,0.30)', fontSize: '11px', fontWeight: 700, letterSpacing: '1.5px', textTransform: 'uppercase' }}>
                    Feature
                  </div>
                  <div style={{ padding: '16px 20px', textAlign: 'center', borderLeft: '1px solid rgba(255,255,255,0.06)' }}>
                    <div style={{ color: '#E05555', fontSize: '11px', fontWeight: 800, letterSpacing: '1.5px', textTransform: 'uppercase', marginBottom: '3px' }}>
                      ⚠ Remote Installation
                    </div>
                    <div style={{ color: 'rgba(255,255,255,0.25)', fontSize: '11px' }}>AnyDesk / Hired Tech</div>
                  </div>
                  <div style={{ padding: '16px 20px', textAlign: 'center', borderLeft: '1px solid rgba(62,207,178,0.15)', background: 'rgba(62,207,178,0.04)' }}>
                    <div style={{ fontSize: '11px', fontWeight: 800, letterSpacing: '1.5px', textTransform: 'uppercase', marginBottom: '3px' }}>
                      <span className="atlas-chrome-text">✦ ATLAS</span>
                    </div>
                    <div style={{ color: 'rgba(255,255,255,0.25)', fontSize: '11px' }}>Intelligent Installer</div>
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
                    <div style={{ padding: '13px 20px', color: 'rgba(255,255,255,0.60)', fontSize: '13px', fontWeight: 500 }}>
                      {row.label}
                    </div>
                    <div style={{
                      padding: '13px 20px', textAlign: 'center',
                      borderLeft: '1px solid rgba(255,255,255,0.04)',
                      color: '#E05555', fontSize: '13px', fontWeight: 500,
                      display: 'flex', alignItems: 'center', justifyContent: 'center', gap: '6px',
                    }}>
                      <span style={{ color: '#E05555', fontSize: '11px', opacity: 0.6 }}>✕</span>
                      {row.titan}
                    </div>
                    <div style={{
                      padding: '13px 20px', textAlign: 'center',
                      borderLeft: '1px solid rgba(62,207,178,0.10)',
                      background: 'rgba(62,207,178,0.03)',
                      color: '#3ECFB2', fontSize: '13px', fontWeight: 600,
                      display: 'flex', alignItems: 'center', justifyContent: 'center', gap: '6px',
                    }}>
                      <span style={{ fontSize: '11px' }}>✓</span>
                      {row.atlas}
                    </div>
                  </div>
                ))}
              </div>
            </FadeUp>

            {/* CTA after table */}
            <FadeUp delay={120}>
              <div style={{ textAlign: 'center', marginTop: '32px', marginBottom: '16px' }}>
                <p style={{ color: 'rgba(255,255,255,0.30)', fontSize: '13px', marginBottom: '16px' }}>
                  Stop paying per file. One plan, everything included.
                </p>
                <button
                  onClick={() => handleSelectPlan(annual ? 'atlas-annual' : 'atlas')}
                  className="cta-btn"
                  style={{
                    padding: '13px 32px',
                    borderRadius: '12px', border: 'none',
                    background: '#3ECFB2',
                    color: '#080809', fontSize: '14px', fontWeight: 700,
                    cursor: 'pointer',
                    boxShadow: '0 0 28px rgba(62,207,178,0.28)',
                    letterSpacing: '-0.01em',
                  }}
                >
                  Get ATLAS →
                </button>
              </div>
            </FadeUp>
          </div>
        </div>

        <footer style={{ borderTop: '1px solid rgba(255,255,255,0.05)', padding: '24px', textAlign: 'center' }}>
          <p style={{ color: 'rgba(255,255,255,0.15)', fontSize: '12px', letterSpacing: '0.02em' }}>
            InterLinked® · All rights reserved
          </p>
        </footer>

      </main>
    </>
  )
}
