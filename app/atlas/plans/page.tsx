'use client'

import { useState, useEffect, useRef } from 'react'
import { useRouter } from 'next/navigation'
import { createClient } from '@/lib/supabase/client'
import { ThemeToggle } from '@/components/theme-toggle'

// ─── Data ────────────────────────────────────────────────────────────────────

const MONTHLY = {
  price: '$30', period: '/mo', priceId: 'atlas',
  features: [
    'Up to 3 devices',
    '25 installs / month, per device',
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
  ],
}

const COMPARE_ROWS = [
  { label: 'Cost per file installed',   titan: '$30–$80+ per file',   atlas: 'Flat monthly rate' },
  { label: 'Annual cost estimate',       titan: '$1,440+ / year',      atlas: '$360 / year' },
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
  const [heroIn, setHeroIn] = useState(false)
  const [loggedIn, setLoggedIn] = useState(false)
  const [hintVisible, setHintVisible] = useState(false)
  const [compatOpen, setCompatOpen] = useState(false)
  const [compatWarning, setCompatWarning] = useState(false)
  const [pendingPriceId, setPendingPriceId] = useState<string | null>(null)
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
    setPendingPriceId(priceId)
    setCompatWarning(false)
    setCompatOpen(true)
  }

  function proceedToCheckout() {
    if (!pendingPriceId) return
    const dest = `/atlas/checkout?plan=${pendingPriceId}`
    setCompatOpen(false)
    if (loggedIn) {
      router.push(dest)
    } else {
      router.push(`/auth/login?redirect=${encodeURIComponent(dest)}`)
    }
  }

  function scrollToCompare() {
    compareRef.current?.scrollIntoView({ behavior: 'smooth', block: 'start' })
  }

  const plan = MONTHLY

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
        body { background: var(--atlas-bg); color: var(--atlas-fg); }
        ::selection { background: rgba(62,207,178,0.25); }
        ::-webkit-scrollbar { width: 6px; }
        ::-webkit-scrollbar-track { background: transparent; }
        ::-webkit-scrollbar-thumb { background: rgba(128,128,128,0.25); border-radius: 3px; }
        .plan-card { transition: border-color 0.2s ease, transform 0.2s cubic-bezier(0.16,1,0.3,1), box-shadow 0.2s ease; }
        .plan-card:hover { transform: translateY(-3px); }
        .cta-btn { transition: opacity 0.15s, transform 0.15s cubic-bezier(0.16,1,0.3,1); }
        .cta-btn:hover { opacity: 0.88; transform: translateY(-1px); }
        .cta-btn:active { transform: scale(0.98); }
        .toggle-btn { transition: background 0.2s, color 0.2s; }
        .nav-link { transition: color 0.12s; }
        .nav-link:hover { color: var(--atlas-nav-hover) !important; }
        .compare-row:nth-child(odd) { background: var(--atlas-row-footer-bg); }
        .compare-row:hover { background: rgba(62,207,178,0.04); }

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

        .scroll-hint-bar {
          transition: opacity 0.4s ease, transform 0.4s cubic-bezier(0.16,1,0.3,1);
        }
        .scroll-hint-bar:hover { opacity: 0.85 !important; }
        html.light .plans-atlas-title {
          background: none !important;
          -webkit-text-fill-color: #0D1035 !important;
          color: #0D1035;
        }
        .plans-interlinked-logo-light { display: none; }
        html.light .plans-interlinked-logo-dark { display: none !important; }
        html.light .plans-interlinked-logo-light { display: inline-block !important; }

        /* Same app-window -> Mac-screen file-flow animation from the launch
           page, rotated 90°: app window left, Mac screen right, icons
           travel a horizontal curved path behind the plan card (z-index
           below it) so they appear to pass through it on the way across. */
        @keyframes plansFlowFileAcross {
          0% { offset-distance: 0%; opacity: 0; }
          6% { opacity: 1; }
          92% { opacity: 1; }
          100% { offset-distance: 100%; opacity: 0; }
        }
        .plans-flow-file {
          position: absolute; width: 18px; height: 18px; border-radius: 5px;
          display: flex; align-items: center; justify-content: center;
          offset-path: path('M 10,110 C 70,60 150,160 210,110 C 270,60 350,160 410,110');
          animation: plansFlowFileAcross 5.2s cubic-bezier(0.37,0,0.63,1) infinite;
        }
        @keyframes plansScreenArrivalGlow { 0%, 100% { opacity: 0.4; } 50% { opacity: 1; } }
        @keyframes plansScreenArrivalFlash { 0%, 100% { opacity: 0.5; } 50% { opacity: 1; } }
        .plans-screen-glow { animation: plansScreenArrivalGlow 0.87s ease-in-out infinite; }
        .plans-screen-glow-fill { animation: plansScreenArrivalFlash 0.87s ease-in-out infinite; }
        @media (max-width: 860px) {
          .plans-flow-visual { display: none !important; }
        }
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
          background: 'var(--atlas-scroll-hint-bg)',
          backdropFilter: 'blur(16px)',
          border: '1px solid rgba(62,207,178,0.22)',
          borderRadius: '50px',
          padding: '10px 20px',
          cursor: 'pointer',
          display: 'flex', alignItems: 'center', gap: '10px',
          boxShadow: '0 4px 24px rgba(0,0,0,0.5), 0 0 0 1px rgba(62,207,178,0.08)',
        }}
      >
        <span style={{ color: 'var(--atlas-scroll-hint-text)', fontSize: '13px', fontWeight: 500, fontFamily: '"Inter", sans-serif', whiteSpace: 'nowrap' }}>
          Why not just hire someone?
        </span>
        <span style={{ color: 'var(--atlas-scroll-hint-sub)', fontSize: '12px', fontFamily: '"Inter", sans-serif', whiteSpace: 'nowrap' }}>
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
        background: 'var(--atlas-bg)',
        fontFamily: '"Inter", -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif',
        WebkitFontSmoothing: 'antialiased',
      }}>

        {/* Nav */}
        <nav style={{
          position: 'sticky', top: 0, zIndex: 50,
          background: 'var(--atlas-nav-bg)',
          backdropFilter: 'blur(20px)',
          borderBottom: '1px solid var(--atlas-border-faint)',
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
          <div style={{ display: 'flex', alignItems: 'center', gap: '14px' }}>
            <ThemeToggle />
            <a
              href="/atlas/account"
              className="nav-link"
              style={{ color: '#8A8A96', fontSize: '14px', fontWeight: 500, textDecoration: 'none' }}
            >
              My Account
            </a>
          </div>
        </nav>

        {/* Hero */}
        <section style={{ maxWidth: '600px', margin: '0 auto', padding: '32px 24px 20px', textAlign: 'center' }}>
          <div style={{
            opacity: heroIn ? 1 : 0,
            transform: heroIn ? 'translateY(0)' : 'translateY(20px)',
            transition: 'opacity 0.6s cubic-bezier(0.16,1,0.3,1), transform 0.6s cubic-bezier(0.16,1,0.3,1)',
          }}>
            <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 12, marginBottom: '20px' }}>
              <img
                src="/atlas-logo.png"
                alt="ATLAS"
                style={{ width: 56, height: 56, objectFit: 'contain' }}
              />
              <h1 className="plans-atlas-title" style={{
                fontFamily: "'SF-Intellivised', -apple-system, sans-serif",
                fontSize: '34px',
                fontWeight: 'normal',
                letterSpacing: '12px',
                textIndent: '12px',
                lineHeight: 1,
                margin: 0,
                color: 'var(--atlas-fg)',
              }}>
                ATLAS
              </h1>
              <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginTop: 2 }}>
                <span style={{ fontStyle: 'italic', fontSize: 13, color: 'var(--atlas-text-dim)' }}>by</span>
                <img src="/plans-assets/interlinked-logo-dark.png" alt="InterLinked" className="plans-interlinked-logo plans-interlinked-logo-dark" style={{ width: 90, height: 'auto', display: 'block', opacity: 0.85 }} />
                <img src="/plans-assets/interlinked-logo-light.png" alt="InterLinked" className="plans-interlinked-logo plans-interlinked-logo-light" style={{ width: 90, height: 'auto', display: 'none', opacity: 0.85 }} />
              </div>
            </div>

            <p style={{ fontSize: '14px', color: 'var(--atlas-text-sub)', marginBottom: '20px' }}>
              One plan. Everything included.
            </p>
          </div>
        </section>

        {/* Plan card */}
        <div style={{ maxWidth: '480px', margin: '0 auto', padding: '0 24px 80px' }}>
          <div style={{ position: 'relative' }}>
            {/* App window (left) -> Mac screen (right), icons flowing behind the card */}
            <div className="plans-flow-visual" style={{ position: 'absolute', left: '50%', top: '50%', transform: 'translate(-50%, -50%)', width: 420, height: 220, pointerEvents: 'none', zIndex: 0 }}>
              {/* ATLAS app window (left) — files leave from here */}
              <div style={{ position: 'absolute', left: 0, top: '50%', transform: 'translateY(-50%)', width: 110, height: 76, borderRadius: 9, border: '1px solid var(--atlas-border-faint)', background: 'var(--atlas-plans-card)', boxShadow: '0 16px 36px rgba(0,0,0,0.25)' }}>
                <div style={{ position: 'absolute', top: 0, left: 0, right: 0, height: 18, borderBottom: '1px solid var(--atlas-border-faint)', display: 'flex', alignItems: 'center', gap: 4, padding: '0 7px', boxSizing: 'border-box' }}>
                  <div style={{ width: 5, height: 5, borderRadius: '50%', background: '#E05555' }} />
                  <div style={{ width: 5, height: 5, borderRadius: '50%', background: '#E0B155' }} />
                  <div style={{ width: 5, height: 5, borderRadius: '50%', background: '#55C27A' }} />
                </div>
                <img src="/atlas-logo.png" alt="" style={{ position: 'absolute', top: 30, left: '50%', transform: 'translateX(-50%)', width: 26, height: 26, objectFit: 'contain', opacity: 0.9 }} />
              </div>

              {/* Mac screen (right) — glows on each file arrival */}
              <div style={{ position: 'absolute', right: 0, top: '50%', transform: 'translateY(-50%)', width: 128, height: 92 }}>
                <div className="plans-screen-glow" style={{ position: 'absolute', inset: -36, borderRadius: '50%', background: 'radial-gradient(circle, rgba(62,207,178,0.75) 0%, rgba(62,207,178,0.25) 45%, transparent 72%)', filter: 'blur(16px)' }} />
                <div style={{ position: 'absolute', top: 0, left: 0, width: 128, height: 82, borderRadius: 9, border: '2px solid var(--atlas-text-dim)', background: '#0C0C12' }}>
                  <div className="plans-screen-glow-fill" style={{ position: 'absolute', inset: 3, borderRadius: 4, background: 'radial-gradient(circle at 50% 60%, rgba(62,207,178,0.5), rgba(62,207,178,0.05) 70%)' }} />
                </div>
                <div style={{ position: 'absolute', top: 82, left: '50%', transform: 'translateX(-50%)', width: 38, height: 8, background: 'var(--atlas-text-dim)', borderRadius: '0 0 3px 3px' }} />
                <div style={{ position: 'absolute', top: 90, left: '50%', transform: 'translateX(-50%)', width: 58, height: 3, background: 'var(--atlas-text-dim)', borderRadius: 2, opacity: 0.8 }} />
              </div>

              {/* Files leaving the app, flowing across to the screen */}
              <div className="plans-flow-file" style={{ animationDelay: '0s', background: '#3ECFB2' }}>
                <svg viewBox="0 0 20 20"><path d="M4 13V9 M8 15V5 M12 16V4 M16 12V10" stroke="#06211D" strokeWidth={2} strokeLinecap="round" /></svg>
              </div>
              <div className="plans-flow-file" style={{ animationDelay: '-0.87s', background: '#5E6AD2' }}>
                <svg viewBox="0 0 20 20"><circle cx="7" cy="14" r="2.4" fill="#fff" /><circle cx="15" cy="11" r="2.4" fill="#fff" /><path d="M9.4 14V5.5L17.4 4V11" stroke="#fff" strokeWidth={1.6} fill="none" strokeLinecap="round" /></svg>
              </div>
              <div className="plans-flow-file" style={{ animationDelay: '-1.73s', background: '#F0A030' }}>
                <svg viewBox="0 0 20 20"><circle cx="10" cy="10" r="6.5" fill="none" stroke="#3A2600" strokeWidth={1.8} /><line x1="10" y1="10" x2="10" y2="5" stroke="#3A2600" strokeWidth={1.8} strokeLinecap="round" /></svg>
              </div>
              <div className="plans-flow-file" style={{ animationDelay: '-2.6s', background: '#E8ECFF' }}>
                <svg viewBox="0 0 20 20"><path d="M5 2.5h7l3 3V17.5H5z" fill="none" stroke="#20244A" strokeWidth={1.6} strokeLinejoin="round" /><path d="M12 2.5v3h3" fill="none" stroke="#20244A" strokeWidth={1.6} strokeLinejoin="round" /></svg>
              </div>
              <div className="plans-flow-file" style={{ animationDelay: '-3.47s', background: '#E05555' }}>
                <svg viewBox="0 0 20 20"><circle cx="10" cy="5.5" r="2.4" fill="#fff" /><path d="M10 8v5 M6.5 17l2-4h3l2 4" stroke="#fff" strokeWidth={1.7} strokeLinecap="round" fill="none" /></svg>
              </div>
              <div className="plans-flow-file" style={{ animationDelay: '-4.33s', background: '#3ECFB2' }}>
                <svg viewBox="0 0 20 20"><rect x="3" y="5" width="14" height="10" rx="1.5" fill="none" stroke="#06211D" strokeWidth={1.6} /><path d="M3 8h14" stroke="#06211D" strokeWidth={1.6} /></svg>
              </div>
            </div>

          <FadeUp delay={0}>
            <div className="plan-card" style={{
              position: 'relative', zIndex: 1,
              background: 'var(--atlas-plans-card)',
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

              <div style={{ padding: '14px 16px 12px', borderBottom: '1px solid var(--atlas-border-faint)' }}>
                <div style={{ fontSize: '10px', fontWeight: 800, letterSpacing: '2px', marginBottom: '8px', textTransform: 'uppercase' }}>
                  <span className="atlas-chrome-text">ATLAS</span>
                </div>
                <div style={{ display: 'flex', alignItems: 'baseline', gap: '4px' }}>
                  <span style={{ color: 'var(--atlas-plans-card-text)', fontSize: '26px', fontWeight: 700, letterSpacing: '-0.02em', lineHeight: 1 }}>{plan.price}</span>
                  <span style={{ color: 'var(--atlas-plans-sub)', fontSize: '12px' }}>{plan.period}</span>
                </div>
              </div>

              <div style={{ padding: '12px 16px', flex: 1, display: 'flex', flexDirection: 'column', gap: '8px' }}>
                {plan.features.map(f => (
                  <div key={f} style={{ display: 'flex', gap: '8px', alignItems: 'flex-start' }}>
                    <span style={{ color: '#3ECFB2', fontSize: '10px', fontWeight: 700, marginTop: '2px', flexShrink: 0 }}>✓</span>
                    <span style={{ color: 'var(--atlas-plans-card-dim)', fontSize: '13px', lineHeight: 1.4 }}>
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
                    width: '100%', padding: '12px',
                    borderRadius: '999px', border: 'none',
                    background: '#3ECFB2',
                    color: '#080809', fontSize: '14px', fontWeight: 800,
                    cursor: 'pointer', letterSpacing: '-0.01em',
                    boxShadow: '0 0 20px rgba(62,207,178,0.22)',
                    display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8,
                  }}
                >
                  <img src="/email-assets/apple-logo.png" alt="" style={{ width: 16, height: 16, objectFit: 'contain' }} />
                  Get ATLAS V1
                </button>
              </div>
            </div>
          </FadeUp>
          </div>

          {/* Footer note */}
          <FadeUp delay={80}>
            <div style={{ textAlign: 'center', marginTop: '16px' }}>
              <p style={{ color: 'var(--atlas-text-dim)', fontSize: '12px', marginBottom: '4px' }}>
                Secure payment via Stripe · Cancel anytime
              </p>
              <p style={{ color: 'var(--atlas-text-dim)', fontSize: '12px', marginBottom: '4px' }}>
                Requires macOS 12 Monterey or later (Apple Silicon or Intel).
              </p>
              <p style={{ color: 'var(--atlas-text-dim)', fontSize: '12px' }}>
                Already subscribed?{' '}
                <a href="/atlas/account" style={{ color: '#3ECFB2', textDecoration: 'none' }}>Manage your account →</a>
              </p>
            </div>
          </FadeUp>

          {/* ── Comparison Section ─────────────────────────────────────────── */}
          <div ref={compareRef} style={{ scrollMarginTop: '72px', paddingTop: '64px' }}>
            <FadeUp delay={0}>
              <div style={{ textAlign: 'center', marginBottom: '32px' }}>
                <p style={{ color: 'var(--atlas-text-dim)', fontSize: '11px', fontWeight: 700, letterSpacing: '3px', textTransform: 'uppercase', marginBottom: '12px' }}>
                  Why ATLAS?
                </p>
                <h2 style={{ fontSize: '26px', fontWeight: 700, letterSpacing: '-0.02em', marginBottom: '10px', color: 'var(--atlas-fg)' }}>
                  Remote Installation vs{' '}
                  <span className="atlas-chrome-text" style={{ fontSize: '26px', fontWeight: 700 }}>ATLAS</span>
                </h2>
                <p style={{ color: 'var(--atlas-text-sub)', fontSize: '14px', maxWidth: '500px', margin: '0 auto', lineHeight: 1.6 }}>
                  Remote install services charge per file and require handing over access to your machine. ATLAS handles everything — privately, instantly, for one flat rate.
                </p>
              </div>
            </FadeUp>

            <FadeUp delay={80}>
              <div style={{
                borderRadius: '16px',
                border: '1px solid var(--atlas-border-subtle)',
                background: 'var(--atlas-plans-card)',
                overflow: 'hidden',
                maxWidth: '860px',
                margin: '0 auto',
              }}>
                {/* Table header */}
                <div style={{
                  display: 'grid',
                  gridTemplateColumns: '1fr 1fr 1fr',
                  background: 'var(--atlas-plans-card)',
                  borderBottom: '1px solid var(--atlas-input-border)',
                }}>
                  <div style={{ padding: '16px 20px', color: 'var(--atlas-table-label)', fontSize: '11px', fontWeight: 700, letterSpacing: '1.5px', textTransform: 'uppercase' }}>
                    Feature
                  </div>
                  <div style={{ padding: '16px 20px', textAlign: 'center', borderLeft: '1px solid var(--atlas-border-faint)' }}>
                    <div style={{ color: '#E05555', fontSize: '11px', fontWeight: 800, letterSpacing: '1.5px', textTransform: 'uppercase', marginBottom: '3px' }}>
                      ⚠ Remote Installation
                    </div>
                    <div style={{ color: 'var(--atlas-table-remote)', fontSize: '11px' }}>AnyDesk / Hired Tech</div>
                  </div>
                  <div style={{ padding: '16px 20px', textAlign: 'center', borderLeft: '1px solid rgba(62,207,178,0.15)', background: 'rgba(62,207,178,0.04)' }}>
                    <div style={{ fontSize: '11px', fontWeight: 800, letterSpacing: '1.5px', textTransform: 'uppercase', marginBottom: '3px' }}>
                      <span className="atlas-chrome-text">✦ ATLAS</span>
                    </div>
                    <div style={{ color: 'var(--atlas-table-remote)', fontSize: '11px' }}>Intelligent Installer</div>
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
                    <div style={{ padding: '13px 20px', color: 'var(--atlas-table-row)', fontSize: '13px', fontWeight: 500 }}>
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
                <p style={{ color: 'var(--atlas-text-sub)', fontSize: '13px', marginBottom: '16px' }}>
                  Stop paying per file. One plan, everything included.
                </p>
                <button
                  onClick={() => handleSelectPlan('atlas')}
                  className="cta-btn"
                  style={{
                    padding: '14px 32px',
                    borderRadius: '999px', border: 'none',
                    background: '#3ECFB2',
                    color: '#080809', fontSize: '15px', fontWeight: 800,
                    cursor: 'pointer',
                    boxShadow: '0 0 28px rgba(62,207,178,0.28)',
                    letterSpacing: '-0.01em',
                    display: 'inline-flex', alignItems: 'center', gap: 8,
                  }}
                >
                  <img src="/email-assets/apple-logo.png" alt="" style={{ width: 17, height: 17, objectFit: 'contain' }} />
                  Get ATLAS V1
                </button>
              </div>
            </FadeUp>
          </div>
        </div>

        <footer style={{ borderTop: '1px solid var(--atlas-border-faint)', padding: '24px', textAlign: 'center' }}>
          <p style={{ color: 'var(--atlas-text-dim)', fontSize: '11px', letterSpacing: '0.01em', maxWidth: '520px', margin: '0 auto 10px', lineHeight: 1.6 }}>
            By subscribing you agree to the <a href="/atlas/terms" style={{ color: 'inherit', textDecoration: 'underline' }}>Terms of Service</a>.
            Subscriptions are generally non-refundable (exceptions may apply where required by law or payment-network rules).
            Cancelling stops future renewal — you keep access through the period you've already paid for.
          </p>
          <p style={{ color: 'var(--atlas-text-dim)', fontSize: '12px', letterSpacing: '0.02em' }}>
            InterLinked® · All rights reserved
          </p>
        </footer>

      </main>

      {/* ── macOS compatibility check ── */}
      {compatOpen && (
        <div
          onClick={() => setCompatOpen(false)}
          style={{
            position: 'fixed', inset: 0, zIndex: 9999,
            background: 'rgba(8,8,9,0.82)',
            display: 'flex', alignItems: 'center', justifyContent: 'center',
            padding: '20px',
          }}
        >
          <div
            onClick={e => e.stopPropagation()}
            style={{
              background: '#0E0E10',
              border: '1px solid rgba(255,255,255,0.09)',
              borderRadius: 16,
              padding: '28px 28px 24px',
              width: '100%', maxWidth: 400,
              fontFamily: '"Inter", -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif',
            }}
          >
            {!compatWarning ? (
              <>
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: 16 }}>
                  <div>
                    <p style={{ color: '#FFFFFF', fontSize: 15, fontWeight: 600, letterSpacing: '-0.01em', marginBottom: 6 }}>
                      Before you continue
                    </p>
                    <p style={{ color: '#8A8A96', fontSize: 13, lineHeight: 1.5 }}>
                      Are you running <strong style={{ color: '#C8C8D0' }}>macOS 12 Monterey or later</strong>?
                    </p>
                  </div>
                  <button
                    onClick={() => setCompatOpen(false)}
                    style={{ background: 'none', border: 'none', color: '#44444E', cursor: 'pointer', fontSize: 18, lineHeight: 1, padding: '0 0 0 12px' }}
                  >×</button>
                </div>

                <p style={{ color: '#6A6A76', fontSize: 11, marginBottom: 18, lineHeight: 1.5 }}>
                  Click the Apple menu → About This Mac to check your version if you&apos;re not sure.
                </p>

                <div style={{ display: 'flex', gap: 10 }}>
                  <button
                    onClick={() => setCompatWarning(true)}
                    style={{
                      flex: 1, padding: '11px', border: '1px solid rgba(255,255,255,0.12)', borderRadius: 9,
                      background: 'none', color: '#8A8A96', fontSize: 13, fontWeight: 600, cursor: 'pointer',
                    }}
                  >
                    No
                  </button>
                  <button
                    onClick={proceedToCheckout}
                    style={{
                      flex: 1, padding: '11px', border: 'none', borderRadius: 9,
                      background: 'linear-gradient(135deg, #3ECFB2, #2ABEAA)',
                      color: '#080809', fontSize: 13, fontWeight: 700, cursor: 'pointer',
                    }}
                  >
                    Yes, continue →
                  </button>
                </div>
              </>
            ) : (
              <>
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: 14 }}>
                  <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
                    <span style={{ color: '#F0A030', fontSize: 20 }}>⚠</span>
                    <p style={{ color: '#FFFFFF', fontSize: 15, fontWeight: 600, letterSpacing: '-0.01em' }}>
                      ATLAS won&apos;t run on your Mac
                    </p>
                  </div>
                  <button
                    onClick={() => setCompatOpen(false)}
                    style={{ background: 'none', border: 'none', color: '#44444E', cursor: 'pointer', fontSize: 18, lineHeight: 1, padding: '0 0 0 12px' }}
                  >×</button>
                </div>
                <p style={{ color: '#8A8A96', fontSize: 13, lineHeight: 1.6, marginBottom: 20 }}>
                  ATLAS requires <strong style={{ color: '#C8C8D0' }}>macOS 12 Monterey or later</strong>. Subscribing now would
                  give you access you can&apos;t currently use — we&apos;d rather you upgrade macOS first (or wait for a future ATLAS
                  update) than pay for something that won&apos;t run.
                </p>
                <button
                  onClick={() => setCompatOpen(false)}
                  style={{
                    width: '100%', padding: '11px', border: 'none', borderRadius: 9,
                    background: 'rgba(255,255,255,0.08)',
                    color: '#C8C8D0', fontSize: 13, fontWeight: 600, cursor: 'pointer',
                  }}
                >
                  Got it
                </button>
              </>
            )}
          </div>
        </div>
      )}
    </>
  )
}
