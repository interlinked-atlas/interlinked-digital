'use client'

import { useState, useEffect, useRef } from 'react'

function useInView(ref: React.RefObject<Element | null>, once = true) {
  const [visible, setVisible] = useState(false)
  useEffect(() => {
    if (!ref.current) return
    const obs = new IntersectionObserver(
      ([entry]) => {
        if (entry.isIntersecting) { setVisible(true); if (once) obs.disconnect() }
        else if (!once) setVisible(false)
      },
      { threshold: 0.08, rootMargin: '0px 0px -24px 0px' }
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
      transform: visible ? 'translateY(0)' : 'translateY(26px)',
      transition: `opacity 0.65s cubic-bezier(0.16,1,0.3,1) ${delay}ms, transform 0.65s cubic-bezier(0.16,1,0.3,1) ${delay}ms`,
      ...style,
    }}>
      {children}
    </div>
  )
}

const TITAN_ROWS = [
  { label: 'Cost per install', titan: '$30–$80+ per file', atlas: 'Unlimited installs included', pro: true },
  { label: 'Wait time', titan: 'Long queue — 24–72 hrs', atlas: 'Instant — starts in seconds', pro: false },
  { label: 'Process', titan: 'Remote operator via AnyDesk', atlas: 'Fully autonomous — no human needed', pro: false },
  { label: 'Privacy', titan: 'Operator has full screen access', atlas: 'Local — no one sees your screen', pro: false },
  { label: 'Availability', titan: 'Business hours only', atlas: '24/7 — install at any time', pro: false },
  { label: 'Bulk installs', titan: 'Charged per file, every time', atlas: 'Drop a folder — done', pro: true },
  { label: 'Uninstall & rollback', titan: 'Not included — manual process', atlas: 'One click, full file tracking', pro: true },
  { label: 'TITAN CORE™ verify', titan: 'Not available', atlas: 'Pre-flight validation built in', pro: true },
  { label: 'Smart storage', titan: 'Not available', atlas: 'Auto-optimises install footprint', pro: true },
  { label: 'Install history', titan: 'None — no records kept', atlas: 'Full log with timestamps', pro: false },
  { label: 'Device support', titan: 'One session at a time', atlas: 'Up to 3 devices simultaneously', pro: true },
  { label: 'Monthly cost', titan: '$120–$400+ / month (avg)', atlas: '$29.99 / month flat', pro: true },
]

const PLAN_FEATURES = {
  standard: [
    '1 device',
    '3 installs per day',
    'Install history',
    'Notifications',
  ],
  standardExcluded: [
    'Bulk installation',
    'Uninstall & Rollback',
    'TITAN CORE™',
    'Smart Storage',
  ],
  pro: [
    'Up to 3 devices',
    'Unlimited installs',
    'Bulk installation',
    'Uninstall & Rollback',
    'TITAN CORE™',
    'Smart Storage',
    'Full install history',
    'Virus Scanner',
    'File Sharing',
  ],
}

export default function PlansPage() {
  const [heroIn, setHeroIn] = useState(false)
  useEffect(() => { const t = setTimeout(() => setHeroIn(true), 60); return () => clearTimeout(t) }, [])

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
        ::selection { background: rgba(62,207,178,0.22); }
        ::-webkit-scrollbar { width: 6px; }
        ::-webkit-scrollbar-track { background: transparent; }
        ::-webkit-scrollbar-thumb { background: rgba(255,255,255,0.10); border-radius: 3px; }

        .cta-btn { transition: opacity 0.15s, transform 0.15s cubic-bezier(0.16,1,0.3,1); }
        .cta-btn:hover:not(:disabled) { opacity: 0.88; transform: translateY(-1px); }
        .cta-btn:active { transform: scale(0.97) !important; }

        .plan-card { transition: border-color 0.2s, transform 0.2s cubic-bezier(0.16,1,0.3,1), box-shadow 0.2s; }
        .plan-card:hover { transform: translateY(-3px); }

        .compare-row:hover td { background: rgba(255,255,255,0.018) !important; }

        /* ── Pro liquid-chrome animation on "PRO" label ── */
        @keyframes chrome-shift {
          0%   { background-position: 0% 50%; }
          50%  { background-position: 100% 50%; }
          100% { background-position: 0% 50%; }
        }
        .pro-chrome-text {
          background: linear-gradient(
            90deg,
            #C0C0C0 0%,
            #FFFFFF 18%,
            #A8A8A8 32%,
            #E8E8E8 42%,
            #3ECFB2 52%,
            #FFFFFF 62%,
            #B0B0B0 75%,
            #F0F0F0 85%,
            #C0C0C0 100%
          );
          background-size: 220% 100%;
          -webkit-background-clip: text;
          -webkit-text-fill-color: transparent;
          background-clip: text;
          animation: chrome-shift 3.2s ease-in-out infinite;
          font-weight: 800;
          letter-spacing: 2px;
          font-size: 9px;
          text-transform: uppercase;
          filter: drop-shadow(0 0 8px rgba(62,207,178,0.4));
        }

        @media (max-width: 680px) {
          .compare-table-wrap { overflow-x: auto; }
          .compare-table { min-width: 560px; }
          .plans-grid { grid-template-columns: 1fr !important; }
        }
      `}</style>

      <main style={{
        minHeight: '100vh',
        background: '#080809',
        fontFamily: '"Inter", -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif',
        WebkitFontSmoothing: 'antialiased',
      }}>

        {/* ── Nav ── */}
        <nav style={{
          position: 'sticky', top: 0, zIndex: 50,
          background: 'rgba(8,8,9,0.88)',
          backdropFilter: 'blur(20px)',
          borderBottom: '1px solid rgba(255,255,255,0.06)',
          padding: '0 24px',
          display: 'flex', alignItems: 'center', justifyContent: 'space-between',
          height: '52px',
        }}>
          <a href="/atlas" style={{
            display: 'flex', alignItems: 'center', gap: '7px',
            color: '#8A8A96', fontSize: '13px', fontWeight: 500,
            textDecoration: 'none', transition: 'color 0.12s',
          }}
            onMouseEnter={e => (e.currentTarget.style.color = '#FFFFFF')}
            onMouseLeave={e => (e.currentTarget.style.color = '#8A8A96')}
          >
            <svg width="14" height="14" viewBox="0 0 14 14" fill="none" style={{ flexShrink: 0 }}>
              <path d="M9 2L4 7L9 12" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round"/>
            </svg>
            ATLAS
          </a>
          <a href="/auth/login" style={{
            color: '#8A8A96', fontSize: '13px', fontWeight: 500,
            textDecoration: 'none', transition: 'color 0.12s',
          }}
            onMouseEnter={e => (e.currentTarget.style.color = '#FFFFFF')}
            onMouseLeave={e => (e.currentTarget.style.color = '#8A8A96')}
          >
            Sign in
          </a>
        </nav>

        {/* ── Hero ── */}
        <section style={{ maxWidth: '860px', margin: '0 auto', padding: '80px 24px 60px', textAlign: 'center' }}>
          <div style={{
            opacity: heroIn ? 1 : 0,
            transform: heroIn ? 'translateY(0)' : 'translateY(28px)',
            transition: 'opacity 0.75s cubic-bezier(0.16,1,0.3,1), transform 0.75s cubic-bezier(0.16,1,0.3,1)',
          }}>
            <p style={{
              fontSize: '10px', fontWeight: 700, letterSpacing: '3.5px',
              textTransform: 'uppercase', color: '#3ECFB2', marginBottom: '18px',
            }}>
              ATLAS Plans
            </p>
            <h1 style={{
              fontFamily: "'SF-Intellivised', -apple-system, sans-serif",
              fontSize: 'clamp(38px, 7vw, 72px)',
              fontWeight: 'normal',
              letterSpacing: 'clamp(8px, 1.5vw, 18px)',
              textIndent: 'clamp(8px, 1.5vw, 18px)',
              lineHeight: 1.05,
              marginBottom: '22px',
              background: 'linear-gradient(160deg, #FFFFFF 30%, rgba(255,255,255,0.5) 100%)',
              WebkitBackgroundClip: 'text',
              WebkitTextFillColor: 'transparent',
              backgroundClip: 'text',
            }}>
              ATLAS
            </h1>
            <p style={{
              fontSize: '17px', color: 'rgba(255,255,255,0.5)',
              lineHeight: 1.55, maxWidth: '520px', margin: '0 auto 10px',
            }}>
              Stop paying $30–$80 per file for remote installation services.<br/>
              ATLAS does it faster, smarter, and for a flat monthly rate.
            </p>
          </div>
        </section>

        {/* ── Comparison table: Titan Installation vs ATLAS ── */}
        <section style={{ maxWidth: '920px', margin: '0 auto', padding: '0 20px 80px' }}>
          <FadeUp>
            <p style={{
              fontSize: '10px', fontWeight: 700, letterSpacing: '3px',
              textTransform: 'uppercase', color: '#525260',
              textAlign: 'center', marginBottom: '28px',
            }}>
              Why ATLAS beats remote installation services
            </p>
          </FadeUp>

          <FadeUp delay={80}>
            <div className="compare-table-wrap">
              <table className="compare-table" style={{
                width: '100%', borderCollapse: 'collapse',
                background: '#0C0C0E',
                border: '1px solid rgba(255,255,255,0.07)',
                borderRadius: '16px',
                overflow: 'hidden',
                tableLayout: 'fixed',
              }}>
                <colgroup>
                  <col style={{ width: '30%' }} />
                  <col style={{ width: '35%' }} />
                  <col style={{ width: '35%' }} />
                </colgroup>
                <thead>
                  <tr>
                    <th style={{
                      padding: '14px 20px',
                      background: '#0A0A0C',
                      borderBottom: '1px solid rgba(255,255,255,0.07)',
                      textAlign: 'left',
                      fontSize: '11px', fontWeight: 600,
                      color: '#44444E', letterSpacing: '-0.01em',
                    }}>
                      Feature
                    </th>
                    <th style={{
                      padding: '14px 20px',
                      background: 'rgba(224,85,85,0.04)',
                      borderBottom: '1px solid rgba(255,255,255,0.07)',
                      borderLeft: '1px solid rgba(255,255,255,0.05)',
                      textAlign: 'left',
                    }}>
                      <div style={{ fontSize: '9px', fontWeight: 800, letterSpacing: '2.5px', textTransform: 'uppercase', color: '#E05555', marginBottom: '3px' }}>
                        ✕ &nbsp;Titan Installation
                      </div>
                      <div style={{ fontSize: '11px', color: 'rgba(255,255,255,0.25)', fontWeight: 400 }}>
                        Remote via AnyDesk
                      </div>
                    </th>
                    <th style={{
                      padding: '14px 20px',
                      background: 'rgba(62,207,178,0.04)',
                      borderBottom: '1px solid rgba(62,207,178,0.15)',
                      borderLeft: '1px solid rgba(255,255,255,0.05)',
                      textAlign: 'left',
                    }}>
                      <div style={{ fontSize: '9px', fontWeight: 800, letterSpacing: '2.5px', textTransform: 'uppercase', color: '#3ECFB2', marginBottom: '3px' }}>
                        ✓ &nbsp;ATLAS Pro
                      </div>
                      <div style={{ fontSize: '11px', color: 'rgba(255,255,255,0.35)', fontWeight: 400 }}>
                        $29.99 / month flat
                      </div>
                    </th>
                  </tr>
                </thead>
                <tbody>
                  {TITAN_ROWS.map((row, i) => (
                    <tr key={row.label} className="compare-row" style={{ borderTop: '1px solid rgba(255,255,255,0.04)' }}>
                      <td style={{
                        padding: '13px 20px',
                        fontSize: '12px', fontWeight: 500,
                        color: 'rgba(255,255,255,0.55)',
                        background: i % 2 === 0 ? 'transparent' : 'rgba(255,255,255,0.01)',
                        transition: 'background 0.15s',
                      }}>
                        {row.label}
                      </td>
                      <td style={{
                        padding: '13px 20px',
                        borderLeft: '1px solid rgba(255,255,255,0.04)',
                        background: i % 2 === 0 ? 'rgba(224,85,85,0.025)' : 'rgba(224,85,85,0.04)',
                        transition: 'background 0.15s',
                      }}>
                        <div style={{ display: 'flex', alignItems: 'flex-start', gap: '8px' }}>
                          <span style={{ color: '#E05555', fontSize: '10px', fontWeight: 700, flexShrink: 0, marginTop: '1px' }}>✕</span>
                          <span style={{ fontSize: '12px', color: '#E05555', lineHeight: 1.45, opacity: 0.85 }}>{row.titan}</span>
                        </div>
                      </td>
                      <td style={{
                        padding: '13px 20px',
                        borderLeft: '1px solid rgba(255,255,255,0.04)',
                        background: i % 2 === 0 ? 'rgba(62,207,178,0.03)' : 'rgba(62,207,178,0.05)',
                        transition: 'background 0.15s',
                      }}>
                        <div style={{ display: 'flex', alignItems: 'flex-start', gap: '8px' }}>
                          <span style={{ color: '#3ECFB2', fontSize: '10px', fontWeight: 700, flexShrink: 0, marginTop: '1px' }}>✓</span>
                          <span style={{ fontSize: '12px', color: row.pro ? '#FFFFFF' : '#A0A0B0', lineHeight: 1.45, fontWeight: row.pro ? 500 : 400 }}>{row.atlas}</span>
                        </div>
                      </td>
                    </tr>
                  ))}
                </tbody>
                {/* Bottom cost callout */}
                <tfoot>
                  <tr>
                    <td colSpan={3} style={{ padding: 0 }}>
                      <div style={{
                        display: 'grid', gridTemplateColumns: '30% 35% 35%',
                        borderTop: '1px solid rgba(255,255,255,0.08)',
                      }}>
                        <div style={{ padding: '18px 20px', display: 'flex', alignItems: 'center' }}>
                          <span style={{ fontSize: '11px', fontWeight: 600, color: '#44444E', letterSpacing: '-0.01em' }}>
                            Annual cost estimate
                          </span>
                        </div>
                        <div style={{
                          padding: '18px 20px',
                          background: 'rgba(224,85,85,0.06)',
                          borderLeft: '1px solid rgba(255,255,255,0.04)',
                        }}>
                          <div style={{ fontSize: '22px', fontWeight: 700, color: '#E05555', letterSpacing: '-0.02em', lineHeight: 1 }}>$1,440+</div>
                          <div style={{ fontSize: '10px', color: '#E05555', opacity: 0.6, marginTop: '4px' }}>at $30/file avg — just 4 files/month</div>
                        </div>
                        <div style={{
                          padding: '18px 20px',
                          background: 'rgba(62,207,178,0.06)',
                          borderLeft: '1px solid rgba(255,255,255,0.04)',
                        }}>
                          <div style={{ fontSize: '22px', fontWeight: 700, color: '#3ECFB2', letterSpacing: '-0.02em', lineHeight: 1 }}>$359.88</div>
                          <div style={{ fontSize: '10px', color: '#3ECFB2', opacity: 0.6, marginTop: '4px' }}>flat rate — unlimited installs all year</div>
                        </div>
                      </div>
                    </td>
                  </tr>
                </tfoot>
              </table>
            </div>
          </FadeUp>
        </section>

        {/* ── Divider ── */}
        <div style={{
          width: '100%', height: '1px',
          background: 'linear-gradient(90deg, transparent, rgba(255,255,255,0.07) 30%, rgba(255,255,255,0.07) 70%, transparent)',
        }} />

        {/* ── Plans ── */}
        <section style={{ maxWidth: '780px', margin: '0 auto', padding: '80px 24px 100px' }}>
          <FadeUp>
            <div style={{ textAlign: 'center', marginBottom: '48px' }}>
              <p style={{ fontSize: '10px', fontWeight: 700, letterSpacing: '3.5px', textTransform: 'uppercase', color: '#525260', marginBottom: '14px' }}>
                Pricing
              </p>
              <h2 style={{
                fontSize: 'clamp(26px, 5vw, 38px)', fontWeight: 700,
                color: '#FFFFFF', letterSpacing: '-0.03em', lineHeight: 1.15, marginBottom: '12px',
              }}>
                Pick a plan. Start installing.
              </h2>
              <p style={{ fontSize: '14px', color: '#525260', lineHeight: 1.6, maxWidth: '420px', margin: '0 auto' }}>
                Both plans include the full ATLAS engine. Pro unlocks unlimited installs, bulk mode, and TITAN CORE™.
              </p>
            </div>
          </FadeUp>

          <div className="plans-grid" style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '16px' }}>

            {/* ── Standard ── */}
            <FadeUp delay={60}>
              <div className="plan-card" style={{
                background: '#0E0E10',
                borderRadius: '18px',
                border: '1px solid rgba(255,255,255,0.08)',
                overflow: 'hidden',
                display: 'flex', flexDirection: 'column',
                height: '100%',
              }}>
                <div style={{ padding: '22px 22px 18px', borderBottom: '1px solid rgba(255,255,255,0.06)' }}>
                  <div style={{
                    fontSize: '9px', fontWeight: 800, letterSpacing: '2px',
                    color: '#5E6AD2', textTransform: 'uppercase', marginBottom: '14px',
                  }}>
                    Standard
                  </div>
                  <div style={{ display: 'flex', alignItems: 'baseline', gap: '4px' }}>
                    <span style={{ fontSize: '32px', fontWeight: 700, color: '#FFFFFF', letterSpacing: '-0.02em', lineHeight: 1 }}>$14.99</span>
                    <span style={{ fontSize: '12px', color: '#525260' }}>/mo</span>
                  </div>
                  <p style={{ fontSize: '12px', color: '#525260', marginTop: '8px', lineHeight: 1.5 }}>
                    Essential autonomous installs for everyday use.
                  </p>
                </div>

                <div style={{ padding: '18px 22px', flex: 1, display: 'flex', flexDirection: 'column', gap: '9px' }}>
                  {PLAN_FEATURES.standard.map(f => (
                    <div key={f} style={{ display: 'flex', gap: '10px', alignItems: 'flex-start' }}>
                      <span style={{ color: '#5E6AD2', fontSize: '10px', fontWeight: 700, marginTop: '2px', flexShrink: 0 }}>✓</span>
                      <span style={{ color: '#CCCCCC', fontSize: '12px', lineHeight: 1.45 }}>{f}</span>
                    </div>
                  ))}
                  {PLAN_FEATURES.standardExcluded.map(f => (
                    <div key={f} style={{ display: 'flex', gap: '10px', alignItems: 'flex-start' }}>
                      <span style={{ color: 'rgba(255,255,255,0.12)', fontSize: '10px', fontWeight: 700, marginTop: '2px', flexShrink: 0 }}>·</span>
                      <span style={{ color: 'rgba(255,255,255,0.18)', fontSize: '12px', lineHeight: 1.45 }}>{f}</span>
                    </div>
                  ))}
                </div>

                <div style={{ padding: '0 18px 18px' }}>
                  <a
                    href="/atlas"
                    className="cta-btn"
                    style={{
                      display: 'block', width: '100%', padding: '11px',
                      borderRadius: '10px', textAlign: 'center', textDecoration: 'none',
                      border: '1px solid rgba(94,106,210,0.35)',
                      background: 'rgba(94,106,210,0.10)',
                      color: '#5E6AD2', fontSize: '12px', fontWeight: 700,
                      letterSpacing: '-0.01em',
                    }}
                  >
                    Get started — Standard
                  </a>
                </div>
              </div>
            </FadeUp>

            {/* ── Pro ── */}
            <FadeUp delay={130}>
              <div className="plan-card" style={{
                background: '#0E0E10',
                borderRadius: '18px',
                border: '1px solid rgba(62,207,178,0.30)',
                overflow: 'hidden',
                display: 'flex', flexDirection: 'column',
                height: '100%',
                boxShadow: '0 0 50px rgba(62,207,178,0.10), 0 0 120px rgba(62,207,178,0.04)',
              }}>
                {/* Most popular banner */}
                <div style={{
                  background: 'rgba(62,207,178,0.10)',
                  borderBottom: '1px solid rgba(62,207,178,0.20)',
                  padding: '6px 0', textAlign: 'center',
                  color: '#3ECFB2', fontSize: '9px', fontWeight: 800, letterSpacing: '2.5px',
                }}>
                  MOST POPULAR
                </div>

                <div style={{ padding: '22px 22px 18px', borderBottom: '1px solid rgba(255,255,255,0.06)' }}>
                  {/* Chrome-animated PRO label */}
                  <div className="pro-chrome-text" style={{ marginBottom: '14px' }}>
                    Pro
                  </div>
                  <div style={{ display: 'flex', alignItems: 'baseline', gap: '4px' }}>
                    <span style={{ fontSize: '32px', fontWeight: 700, color: '#FFFFFF', letterSpacing: '-0.02em', lineHeight: 1 }}>$29.99</span>
                    <span style={{ fontSize: '12px', color: '#525260' }}>/mo</span>
                  </div>
                  <p style={{ fontSize: '12px', color: '#525260', marginTop: '8px', lineHeight: 1.5 }}>
                    Unlimited power — everything ATLAS is built to do.
                  </p>
                </div>

                <div style={{ padding: '18px 22px', flex: 1, display: 'flex', flexDirection: 'column', gap: '9px' }}>
                  {PLAN_FEATURES.pro.map(f => (
                    <div key={f} style={{ display: 'flex', gap: '10px', alignItems: 'flex-start' }}>
                      <span style={{ color: '#3ECFB2', fontSize: '10px', fontWeight: 700, marginTop: '2px', flexShrink: 0 }}>✓</span>
                      <span style={{ color: '#FFFFFF', fontSize: '12px', lineHeight: 1.45, fontWeight: 500 }}>{f}</span>
                    </div>
                  ))}
                </div>

                <div style={{ padding: '0 18px 18px' }}>
                  <a
                    href="/atlas"
                    className="cta-btn"
                    style={{
                      display: 'block', width: '100%', padding: '11px',
                      borderRadius: '10px', textAlign: 'center', textDecoration: 'none',
                      border: 'none',
                      background: '#3ECFB2',
                      color: '#080809', fontSize: '12px', fontWeight: 700,
                      letterSpacing: '-0.01em',
                      boxShadow: '0 0 28px rgba(62,207,178,0.30)',
                    }}
                  >
                    Get started — Pro
                  </a>
                </div>
              </div>
            </FadeUp>
          </div>

          <FadeUp delay={220}>
            <p style={{ textAlign: 'center', color: 'rgba(255,255,255,0.18)', fontSize: '12px', marginTop: '20px' }}>
              Secure payment via Stripe · Cancel anytime ·{' '}
              <a href="/auth/login" style={{ color: '#3ECFB2', textDecoration: 'none' }}>Already subscribed? Sign in →</a>
            </p>
          </FadeUp>
        </section>

        {/* ── Footer ── */}
        <footer style={{
          borderTop: '1px solid rgba(255,255,255,0.05)',
          padding: '24px', textAlign: 'center',
        }}>
          <p style={{ color: 'rgba(255,255,255,0.15)', fontSize: '11px', letterSpacing: '0.02em' }}>
            InterLinked® · All rights reserved
          </p>
        </footer>

      </main>
    </>
  )
}
