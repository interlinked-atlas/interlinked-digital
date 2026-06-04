'use client'

import { useState, useEffect, useRef } from 'react'
import { createClient } from '@supabase/supabase-js'

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!
)

const PLANS = [
  {
    id: 'standard',
    name: 'Standard',
    price: '$14.99',
    period: '/mo',
    color: '#8A8A96',
    accentColor: '#5E6AD2',
    recommended: false,
    features: ['1 device', '3 installs per day', 'TITAN CORE™ engine', 'Install history', 'Notifications'],
    excluded: ['Bulk installation', 'Uninstall & Rollback', 'Smart Storage'],
    stripeUrl: 'https://buy.stripe.com/7sYcN4b66b0l3VJ1judjO00',
  },
  {
    id: 'pro',
    name: 'Pro',
    price: '$29.99',
    period: '/mo',
    color: '#3ECFB2',
    accentColor: '#3ECFB2',
    recommended: true,
    features: [
      'Up to 3 devices',
      'Unlimited installs',
      'Bulk installation',
      'Uninstall & Rollback',
      'Smart Storage',
      'Full install history',
    ],
    excluded: [],
    stripeUrl: 'https://buy.stripe.com/aFafZg7TUc4p0Jx7HSdjO01',
  },
]

const FEATURES = [
  {
    icon: '⚡',
    title: 'Automated installs',
    desc: 'Drop any DMG, ZIP, PKG, or plugin — ATLAS handles the rest autonomously.',
  },
  {
    icon: '↩',
    title: 'Uninstall & rollback',
    desc: 'Track every file placed. Undo any install cleanly, with full recovery support.',
  },
  {
    icon: '◈',
    title: 'TITAN CORE™',
    desc: 'Reads installation instructions and performs every step automatically — on every plan.',
  },
]

const TOS_TEXT = `ATLAS® — Terms of Service
© InterLinked®. All rights reserved.
Last updated: 2025

1. ACCEPTANCE
By using ATLAS®, you agree to these Terms in full. If you do not agree, do not use the application.

2. DESCRIPTION
ATLAS® is an autonomous installation and configuration utility developed by InterLinked®. It automates the installation of third-party software on macOS.

3. USER RESPONSIBILITY
All software installed through ATLAS is installed at your sole direction and risk. You are solely responsible for ensuring you have a valid license for every piece of software you install.

4. NO WARRANTY
ATLAS® is provided AS IS without warranties of any kind. InterLinked® is not liable for instability, data loss, software conflicts, or any other consequences arising from software you install using ATLAS.

5. DATA COLLECTION & LOGS
InterLinked® collects certain usage data to provide, improve, and support ATLAS services. This includes:
• Installation logs (app names, file types, timestamps, result status)
• Device identifiers (hardware UUID, device name, macOS version)
• Account activity associated with your InterLinked® account

This data is securely transmitted to InterLinked® servers and stored in your account dashboard. It is used solely for:
• Account support and troubleshooting
• Product improvements and future updates
• Installation history accessible through your account

Log data is stored securely and is never sold to third parties. You may request deletion by contacting interlinked.digital@gmail.com.

6. PROHIBITED USE
Piracy, license circumvention, keygen use, or any unlicensed use of software through ATLAS is strictly prohibited and is solely the user's legal responsibility.

7. SYSTEM ACCESS
ATLAS requests Full Disk Access, Accessibility, and Automation permissions solely to perform installations you initiate. Your admin password, if provided, is stored securely in the macOS Keychain and is never transmitted externally.

8. SUBSCRIPTION & BILLING
ATLAS is available on Standard and Pro plans. Subscriptions are managed through InterLinked® at interlinked.digital/atlas. Cancellations take effect at the end of the current billing period.

9. CHANGES
InterLinked® reserves the right to update these terms at any time. Continued use of ATLAS constitutes acceptance of the current terms.

10. CONTACT
interlinked.digital@gmail.com
interlinked.digital`

type Plan = typeof PLANS[0]
type Step = 'landing' | 'plan' | 'account'

// ─── Scroll-animate hook ────────────────────────────────────────────────────
function useInView(ref: React.RefObject<Element | null>, once = true) {
  const [visible, setVisible] = useState(false)
  useEffect(() => {
    if (!ref.current) return
    const obs = new IntersectionObserver(
      ([entry]) => {
        if (entry.isIntersecting) {
          setVisible(true)
          if (once) obs.disconnect()
        } else if (!once) {
          setVisible(false)
        }
      },
      { threshold: 0.12, rootMargin: '0px 0px -32px 0px' }
    )
    obs.observe(ref.current)
    return () => obs.disconnect()
  }, [ref, once])
  return visible
}

// ─── Animated section wrapper ───────────────────────────────────────────────
function FadeUp({
  children,
  delay = 0,
  style = {},
}: {
  children: React.ReactNode
  delay?: number
  style?: React.CSSProperties
}) {
  const ref = useRef<HTMLDivElement>(null)
  const visible = useInView(ref)
  return (
    <div
      ref={ref}
      style={{
        opacity: visible ? 1 : 0,
        transform: visible ? 'translateY(0)' : 'translateY(28px)',
        transition: `opacity 0.65s cubic-bezier(0.16,1,0.3,1) ${delay}ms, transform 0.65s cubic-bezier(0.16,1,0.3,1) ${delay}ms`,
        ...style,
      }}
    >
      {children}
    </div>
  )
}

// ─── ToS modal ──────────────────────────────────────────────────────────────
function TosModal({ onClose }: { onClose: () => void }) {
  const [opacity, setOpacity] = useState(0)
  useEffect(() => { requestAnimationFrame(() => setOpacity(1)) }, [])

  function close() {
    setOpacity(0)
    setTimeout(onClose, 160)
  }

  return (
    <div
      onClick={close}
      style={{
        position: 'fixed', inset: 0, zIndex: 100,
        background: 'rgba(0,0,0,0.75)',
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        padding: '24px',
        backdropFilter: 'blur(8px)',
        opacity, transition: 'opacity 0.17s ease',
      }}
    >
      <div
        onClick={e => e.stopPropagation()}
        style={{
          background: '#111113',
          border: '1px solid rgba(255,255,255,0.08)',
          borderRadius: '16px',
          width: '100%', maxWidth: '520px',
          boxShadow: '0 40px 80px rgba(0,0,0,0.8)',
          overflow: 'hidden',
          opacity,
          transform: `scale(${0.96 + 0.04 * opacity})`,
          transition: 'opacity 0.17s ease, transform 0.17s ease',
        }}
      >
        <div style={{
          display: 'flex', alignItems: 'center', justifyContent: 'space-between',
          padding: '14px 18px',
          borderBottom: '1px solid rgba(255,255,255,0.06)',
        }}>
          <span style={{ color: '#FFFFFF', fontSize: '13px', fontWeight: 600, letterSpacing: '-0.01em' }}>
            Terms of Service — ATLAS
          </span>
          <button
            onClick={close}
            style={{
              background: 'rgba(255,255,255,0.06)',
              border: '1px solid rgba(255,255,255,0.08)',
              borderRadius: '6px',
              width: '26px', height: '26px',
              cursor: 'pointer', color: '#8A8A96',
              fontSize: '11px', fontWeight: 700,
              display: 'flex', alignItems: 'center', justifyContent: 'center',
              transition: 'background 0.12s',
            }}
            onMouseEnter={e => (e.currentTarget.style.background = 'rgba(255,255,255,0.10)')}
            onMouseLeave={e => (e.currentTarget.style.background = 'rgba(255,255,255,0.06)')}
          >✕</button>
        </div>
        <div style={{ maxHeight: '380px', overflowY: 'auto', padding: '18px' }}>
          <pre style={{
            color: '#8A8A96', fontSize: '11.5px', lineHeight: '1.8',
            whiteSpace: 'pre-wrap', fontFamily: 'inherit', margin: 0,
          }}>
            {TOS_TEXT}
          </pre>
        </div>
        <div style={{ borderTop: '1px solid rgba(255,255,255,0.06)' }}>
          <button
            onClick={close}
            style={{
              width: '100%', padding: '12px',
              border: 'none', background: 'transparent',
              color: '#8A8A96', fontSize: '12px',
              fontWeight: 500, cursor: 'pointer',
              transition: 'color 0.12s',
            }}
            onMouseEnter={e => (e.currentTarget.style.color = '#FFFFFF')}
            onMouseLeave={e => (e.currentTarget.style.color = '#8A8A96')}
          >
            Close
          </button>
        </div>
      </div>
    </div>
  )
}

// ─── Main page ──────────────────────────────────────────────────────────────
export default function AtlasSignupPage() {
  const [step, setStep] = useState<Step>('landing')
  const [selectedPlan, setSelectedPlan] = useState<Plan | null>(null)
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [confirmPassword, setConfirmPassword] = useState('')
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState('')
  const [tosAgreed, setTosAgreed] = useState(false)
  const [showTosModal, setShowTosModal] = useState(false)
  const [showPassword, setShowPassword] = useState(false)
  const [showConfirmPassword, setShowConfirmPassword] = useState(false)

  // Kick off hero text animation on mount
  const [heroIn, setHeroIn] = useState(false)
  useEffect(() => {
    const t = setTimeout(() => setHeroIn(true), 80)
    return () => clearTimeout(t)
  }, [])

  function handleSelectPlan(plan: Plan) {
    setSelectedPlan(plan)
    setError('')
    setTosAgreed(false)
    setStep('account')
    window.scrollTo({ top: 0, behavior: 'smooth' })
  }

  async function handleSignup(e: React.FormEvent) {
    e.preventDefault()
    if (!selectedPlan) return
    if (!tosAgreed) { setError('Please agree to the Terms of Service to continue.'); return }
    if (password !== confirmPassword) { setError('Passwords do not match.'); return }
    if (password.length < 8) { setError('Password must be at least 8 characters.'); return }
    setError('')
    setLoading(true)
    const { error: signUpError } = await supabase.auth.signUp({ email, password })
    setLoading(false)
    if (signUpError) { setError(signUpError.message); return }
    window.location.href = selectedPlan.stripeUrl
  }

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
        input::placeholder { color: rgba(255,255,255,0.20); }
        input:focus { outline: none; border-color: rgba(62,207,178,0.5) !important; box-shadow: 0 0 0 3px rgba(62,207,178,0.08) !important; }
        .plan-card { transition: border-color 0.2s ease, transform 0.2s cubic-bezier(0.16,1,0.3,1), box-shadow 0.2s ease; }
        .plan-card:hover { transform: translateY(-3px); }
        .feature-card { transition: background 0.18s ease, border-color 0.18s ease; }
        .feature-card:hover { background: rgba(255,255,255,0.04) !important; border-color: rgba(255,255,255,0.08) !important; }
        .cta-btn { transition: opacity 0.15s, transform 0.15s cubic-bezier(0.16,1,0.3,1), box-shadow 0.15s; }
        .cta-btn:hover:not(:disabled) { opacity: 0.88; transform: translateY(-1px); }
        .cta-btn:active:not(:disabled) { transform: scale(0.98); }
        .cta-btn:disabled { opacity: 0.35; cursor: not-allowed; }
        .nav-back { transition: color 0.12s; }
        .nav-back:hover { color: #FFFFFF !important; }
        .tos-link:hover { opacity: 0.75 !important; }
      `}</style>

      {showTosModal && <TosModal onClose={() => setShowTosModal(false)} />}

      <main style={{
        minHeight: '100vh',
        background: '#080809',
        fontFamily: '"Inter", -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif',
        WebkitFontSmoothing: 'antialiased',
      }}>

        {/* ── Top nav bar ── */}
        <nav style={{
          position: 'sticky', top: 0, zIndex: 50,
          background: 'rgba(8,8,9,0.85)',
          backdropFilter: 'blur(20px)',
          borderBottom: '1px solid rgba(255,255,255,0.06)',
          padding: '0 24px',
          display: 'flex', alignItems: 'center', justifyContent: 'space-between',
          height: '52px',
        }}>
          {/* Left slot: "Back to InterLinked" on landing, "← Back" on inner steps */}
          {step === 'landing' ? (
            <a
              href="https://www.interlinked.digital/"
              className="nav-back"
              style={{
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
              Back to InterLinked©
            </a>
          ) : (
            <button
              className="nav-back"
              onClick={() => { setStep('landing'); setSelectedPlan(null) }}
              style={{
                background: 'none', border: 'none', cursor: 'pointer',
                color: '#8A8A96', fontSize: '13px', fontWeight: 500,
                display: 'flex', alignItems: 'center', gap: '6px',
              }}
              onMouseEnter={e => (e.currentTarget.style.color = '#FFFFFF')}
              onMouseLeave={e => (e.currentTarget.style.color = '#8A8A96')}
            >
              <svg width="14" height="14" viewBox="0 0 14 14" fill="none" style={{ flexShrink: 0 }}>
                <path d="M9 2L4 7L9 12" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round"/>
              </svg>
              Back
            </button>
          )}
          {/* Right slot: Sign in */}
          <a
            href="/auth/login"
            style={{
              color: '#8A8A96', fontSize: '13px', fontWeight: 500,
              textDecoration: 'none', transition: 'color 0.12s',
            }}
            onMouseEnter={e => (e.currentTarget.style.color = '#FFFFFF')}
            onMouseLeave={e => (e.currentTarget.style.color = '#8A8A96')}
          >
            Sign in
          </a>
        </nav>

        {/* ── Landing / hero ── */}
        {step === 'landing' && (
          <div>

            {/* Hero */}
            <section style={{
              maxWidth: '860px', margin: '0 auto',
              padding: '100px 24px 80px',
              textAlign: 'center',
            }}>
              <div style={{
                opacity: heroIn ? 1 : 0,
                transform: heroIn ? 'translateY(0)' : 'translateY(32px)',
                transition: 'opacity 0.8s cubic-bezier(0.16,1,0.3,1), transform 0.8s cubic-bezier(0.16,1,0.3,1)',
              }}>
                {/* ATLAS star logo */}
                <div style={{ marginBottom: '24px', display: 'flex', justifyContent: 'center' }}>
                  <img
                    src="/atlas-logo.png"
                    alt="ATLAS"
                    style={{
                      width: 'clamp(64px, 10vw, 88px)',
                      height: 'clamp(64px, 10vw, 88px)',
                      objectFit: 'contain',
                      filter: 'drop-shadow(0 0 28px rgba(62,207,178,0.22))',
                    }}
                  />
                </div>

                <h1 style={{
                  fontFamily: "'SF-Intellivised', -apple-system, sans-serif",
                  fontSize: 'clamp(64px, 12vw, 110px)',
                  fontWeight: 'normal',
                  letterSpacing: 'clamp(14px, 2.5vw, 28px)',
                  textIndent: 'clamp(14px, 2.5vw, 28px)',
                  lineHeight: 1,
                  marginBottom: '28px',
                  background: 'linear-gradient(160deg, #FFFFFF 30%, rgba(255,255,255,0.55) 100%)',
                  WebkitBackgroundClip: 'text',
                  WebkitTextFillColor: 'transparent',
                  backgroundClip: 'text',
                }}>
                  ATLAS
                </h1>

                <p style={{
                  fontSize: '18px', fontWeight: 400,
                  color: 'rgba(255,255,255,0.55)',
                  letterSpacing: '-0.01em', lineHeight: 1.5,
                  maxWidth: '480px', margin: '0 auto 14px',
                  opacity: heroIn ? 1 : 0,
                  transition: 'opacity 0.8s cubic-bezier(0.16,1,0.3,1) 180ms',
                }}>
                  The future of macOS installation.
                </p>

                <p style={{
                  fontSize: '13px',
                  color: 'rgba(255,255,255,0.25)',
                  letterSpacing: '3px',
                  textTransform: 'uppercase',
                  marginBottom: '48px',
                  opacity: heroIn ? 1 : 0,
                  transition: 'opacity 0.8s cubic-bezier(0.16,1,0.3,1) 260ms',
                }}>
                  by InterLinked®
                </p>

                <div style={{
                  display: 'flex', gap: '12px', justifyContent: 'center', flexWrap: 'wrap',
                  opacity: heroIn ? 1 : 0,
                  transition: 'opacity 0.8s cubic-bezier(0.16,1,0.3,1) 340ms',
                }}>
                  <button
                    className="cta-btn"
                    onClick={() => setStep('plan')}
                    style={{
                      background: '#3ECFB2',
                      border: 'none',
                      borderRadius: '10px',
                      padding: '12px 28px',
                      color: '#080809',
                      fontSize: '14px', fontWeight: 700,
                      cursor: 'pointer',
                      letterSpacing: '-0.01em',
                      boxShadow: '0 0 32px rgba(62,207,178,0.25)',
                    }}
                  >
                    Get started →
                  </button>
                  <a
                    href="/auth/login"
                    style={{
                      background: 'rgba(255,255,255,0.06)',
                      border: '1px solid rgba(255,255,255,0.08)',
                      borderRadius: '10px',
                      padding: '12px 24px',
                      color: '#FFFFFF',
                      fontSize: '14px', fontWeight: 500,
                      cursor: 'pointer',
                      textDecoration: 'none',
                      display: 'inline-block',
                    }}
                  >
                    Sign in
                  </a>
                </div>
              </div>
            </section>

            {/* Divider */}
            <div style={{
              width: '100%', height: '1px',
              background: 'linear-gradient(90deg, transparent, rgba(255,255,255,0.07) 30%, rgba(255,255,255,0.07) 70%, transparent)',
            }} />

            {/* Features */}
            <section style={{
              maxWidth: '860px', margin: '0 auto',
              padding: '80px 24px',
            }}>
              <FadeUp>
                <p style={{
                  textAlign: 'center',
                  fontSize: '11px', fontWeight: 600,
                  letterSpacing: '3px', textTransform: 'uppercase',
                  color: '#3ECFB2', marginBottom: '40px',
                }}>
                  What ATLAS does
                </p>
              </FadeUp>

              <div style={{
                display: 'grid',
                gridTemplateColumns: 'repeat(auto-fit, minmax(220px, 1fr))',
                gap: '14px',
              }}>
                {FEATURES.map((f, i) => (
                  <FadeUp key={f.title} delay={i * 90}>
                    <div
                      className="feature-card"
                      style={{
                        background: 'rgba(255,255,255,0.02)',
                        border: '1px solid rgba(255,255,255,0.05)',
                        borderRadius: '14px',
                        padding: '24px',
                        height: '100%',
                      }}
                    >
                      <div style={{ fontSize: '22px', marginBottom: '14px', lineHeight: 1 }}>{f.icon}</div>
                      <h3 style={{
                        fontSize: '14px', fontWeight: 600,
                        color: '#FFFFFF', marginBottom: '8px',
                        letterSpacing: '-0.01em',
                      }}>{f.title}</h3>
                      <p style={{
                        fontSize: '13px', color: '#525260',
                        lineHeight: 1.6, letterSpacing: '-0.005em',
                      }}>{f.desc}</p>
                    </div>
                  </FadeUp>
                ))}
              </div>
            </section>

            {/* Divider */}
            <div style={{
              width: '100%', height: '1px',
              background: 'linear-gradient(90deg, transparent, rgba(255,255,255,0.07) 30%, rgba(255,255,255,0.07) 70%, transparent)',
            }} />

            {/* Plans teaser */}
            <section style={{
              maxWidth: '560px', margin: '0 auto',
              padding: '80px 24px 100px',
              textAlign: 'center',
            }}>
              <FadeUp>
                <p style={{
                  fontSize: '11px', fontWeight: 600,
                  letterSpacing: '3px', textTransform: 'uppercase',
                  color: '#44444E', marginBottom: '18px',
                }}>
                  Pricing
                </p>
                <h2 style={{
                  fontSize: '32px', fontWeight: 700,
                  color: '#FFFFFF', marginBottom: '14px',
                  letterSpacing: '-0.03em', lineHeight: 1.15,
                }}>
                  Pick a plan. Start installing.
                </h2>
                <p style={{
                  fontSize: '14px', color: '#525260',
                  lineHeight: 1.6, marginBottom: '36px',
                }}>
                  Both plans include TITAN CORE™ — our installation intelligence engine.
                  Upgrade to Pro for unlimited installs, bulk mode, and Smart Storage.
                </p>
                <button
                  className="cta-btn"
                  onClick={() => setStep('plan')}
                  style={{
                    background: 'rgba(255,255,255,0.06)',
                    border: '1px solid rgba(255,255,255,0.10)',
                    borderRadius: '10px',
                    padding: '12px 28px',
                    color: '#FFFFFF',
                    fontSize: '14px', fontWeight: 500,
                    cursor: 'pointer',
                  }}
                >
                  See plans →
                </button>
              </FadeUp>
            </section>
          </div>
        )}

        {/* ── Plan selection ── */}
        {step === 'plan' && (
          <div style={{ maxWidth: '600px', margin: '0 auto', padding: '48px 24px 80px' }}>
            <FadeUp>
              <div style={{ textAlign: 'center', marginBottom: '40px' }}>
                <h2 style={{
                  fontSize: '28px', fontWeight: 700,
                  color: '#FFFFFF', letterSpacing: '-0.03em', marginBottom: '10px',
                }}>
                  Choose your plan
                </h2>
                <p style={{ fontSize: '14px', color: '#525260' }}>
                  Subscribe and create your account — takes 60 seconds
                </p>
              </div>
            </FadeUp>

            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '14px', marginBottom: '24px' }}>
              {PLANS.map((plan, i) => (
                <FadeUp key={plan.id} delay={i * 80}>
                  <div
                    className="plan-card"
                    style={{
                      background: '#0E0E10',
                      borderRadius: '16px',
                      border: plan.recommended
                        ? `1px solid ${plan.accentColor}40`
                        : '1px solid rgba(255,255,255,0.07)',
                      overflow: 'hidden',
                      display: 'flex',
                      flexDirection: 'column',
                      boxShadow: plan.recommended
                        ? `0 0 40px ${plan.accentColor}14`
                        : 'none',
                    }}
                  >
                    {plan.recommended && (
                      <div style={{
                        background: `${plan.accentColor}18`,
                        borderBottom: `1px solid ${plan.accentColor}28`,
                        padding: '6px 0',
                        textAlign: 'center',
                        color: plan.accentColor,
                        fontSize: '9px', fontWeight: 800,
                        letterSpacing: '2.5px',
                      }}>
                        MOST POPULAR
                      </div>
                    )}

                    <div style={{
                      padding: '20px 20px 16px',
                      borderBottom: '1px solid rgba(255,255,255,0.06)',
                    }}>
                      <div style={{
                        color: plan.accentColor,
                        fontSize: '9px', fontWeight: 800,
                        letterSpacing: '2px', marginBottom: '12px',
                        textTransform: 'uppercase',
                      }}>
                        {plan.name}
                      </div>
                      <div style={{ display: 'flex', alignItems: 'baseline', gap: '4px' }}>
                        <span style={{ color: '#FFFFFF', fontSize: '30px', fontWeight: 700, letterSpacing: '-0.02em', lineHeight: 1 }}>
                          {plan.price}
                        </span>
                        <span style={{ color: '#525260', fontSize: '12px' }}>{plan.period}</span>
                      </div>
                    </div>

                    <div style={{ padding: '16px 20px', flex: 1, display: 'flex', flexDirection: 'column', gap: '9px' }}>
                      {plan.features.map(f => (
                        <div key={f} style={{ display: 'flex', gap: '10px', alignItems: 'flex-start' }}>
                          <span style={{ color: plan.accentColor, fontSize: '10px', fontWeight: 700, marginTop: '2px', flexShrink: 0 }}>✓</span>
                          <span style={{ color: '#CCCCCC', fontSize: '12px', lineHeight: 1.45 }}>{f}</span>
                        </div>
                      ))}
                      {plan.excluded.map(f => (
                        <div key={f} style={{ display: 'flex', gap: '10px', alignItems: 'flex-start' }}>
                          <span style={{ color: 'rgba(255,255,255,0.12)', fontSize: '10px', fontWeight: 700, marginTop: '2px', flexShrink: 0 }}>·</span>
                          <span style={{ color: 'rgba(255,255,255,0.18)', fontSize: '12px', lineHeight: 1.45 }}>{f}</span>
                        </div>
                      ))}
                    </div>

                    <div style={{ padding: '0 16px 16px' }}>
                      <button
                        className="cta-btn"
                        onClick={() => handleSelectPlan(plan)}
                        style={{
                          width: '100%', padding: '10px',
                          borderRadius: '10px',
                          border: plan.recommended ? 'none' : `1px solid ${plan.accentColor}35`,
                          background: plan.recommended
                            ? plan.accentColor
                            : `${plan.accentColor}12`,
                          color: plan.recommended ? '#080809' : plan.accentColor,
                          fontSize: '12px', fontWeight: 700,
                          cursor: 'pointer', letterSpacing: '-0.01em',
                        }}
                      >
                        Get started — {plan.name}
                      </button>
                    </div>
                  </div>
                </FadeUp>
              ))}
            </div>

            <FadeUp delay={200}>
              <div style={{ textAlign: 'center' }}>
                <p style={{ color: 'rgba(255,255,255,0.20)', fontSize: '12px', marginBottom: '6px' }}>
                  Secure payment via Stripe · Cancel anytime
                </p>
                <p style={{ color: 'rgba(255,255,255,0.20)', fontSize: '12px' }}>
                  Already subscribed?{' '}
                  <a href="/auth/login" style={{ color: '#3ECFB2', textDecoration: 'none' }}>Sign in →</a>
                </p>
              </div>
            </FadeUp>
          </div>
        )}

        {/* ── Account creation ── */}
        {step === 'account' && selectedPlan && (
          <div style={{ maxWidth: '420px', margin: '0 auto', padding: '48px 24px 80px' }}>
            <FadeUp>
              {/* Plan badge */}
              <div style={{
                background: `${selectedPlan.accentColor}0C`,
                border: `1px solid ${selectedPlan.accentColor}28`,
                borderRadius: '12px',
                padding: '12px 16px',
                marginBottom: '16px',
                display: 'flex', alignItems: 'center', justifyContent: 'space-between',
              }}>
                <div>
                  <div style={{
                    color: selectedPlan.accentColor, fontSize: '9px',
                    fontWeight: 800, letterSpacing: '2px',
                    textTransform: 'uppercase', marginBottom: '4px',
                  }}>
                    {selectedPlan.name} Plan
                  </div>
                  <div style={{ display: 'flex', alignItems: 'baseline', gap: '3px' }}>
                    <span style={{ color: '#FFFFFF', fontSize: '15px', fontWeight: 700 }}>{selectedPlan.price}</span>
                    <span style={{ color: '#525260', fontSize: '11px' }}>{selectedPlan.period}</span>
                  </div>
                </div>
                <button
                  onClick={() => { setStep('plan'); setError(''); setTosAgreed(false) }}
                  style={{
                    background: 'rgba(255,255,255,0.05)',
                    border: '1px solid rgba(255,255,255,0.08)',
                    borderRadius: '7px', padding: '5px 12px',
                    color: '#8A8A96', fontSize: '11px', fontWeight: 500,
                    cursor: 'pointer', transition: 'color 0.12s',
                  }}
                  onMouseEnter={e => (e.currentTarget.style.color = '#FFFFFF')}
                  onMouseLeave={e => (e.currentTarget.style.color = '#8A8A96')}
                >
                  Change
                </button>
              </div>

              {/* Form card */}
              <div style={{
                background: '#0E0E10',
                borderRadius: '16px',
                border: '1px solid rgba(255,255,255,0.07)',
                overflow: 'hidden',
              }}>
                <div style={{
                  padding: '16px 20px',
                  borderBottom: '1px solid rgba(255,255,255,0.06)',
                }}>
                  <h2 style={{
                    color: '#FFFFFF', fontSize: '14px', fontWeight: 600,
                    letterSpacing: '-0.01em', marginBottom: '4px',
                  }}>Create your account</h2>
                  <p style={{ color: '#525260', fontSize: '12px' }}>
                    You&apos;ll complete payment right after
                  </p>
                </div>

                <form onSubmit={handleSignup} style={{ padding: '20px', display: 'flex', flexDirection: 'column', gap: '10px' }}>
                  {error && (
                    <div style={{
                      background: 'rgba(224,85,85,0.08)',
                      border: '1px solid rgba(224,85,85,0.20)',
                      borderRadius: '9px', padding: '10px 14px',
                      color: '#E05555', fontSize: '12px', lineHeight: 1.5,
                    }}>{error}</div>
                  )}

                  <input type="email" placeholder="Email address" value={email}
                    onChange={e => setEmail(e.target.value)} required style={inputStyle} />

                  <div style={{ position: 'relative' }}>
                    <input
                      type={showPassword ? 'text' : 'password'}
                      placeholder="Password (min 8 chars)"
                      value={password}
                      onChange={e => setPassword(e.target.value)}
                      required
                      style={{ ...inputStyle, paddingRight: '40px' }}
                    />
                    <button
                      type="button"
                      onClick={() => setShowPassword(v => !v)}
                      style={{
                        position: 'absolute', right: '12px', top: '50%',
                        transform: 'translateY(-50%)',
                        background: 'none', border: 'none', cursor: 'pointer',
                        color: '#525260', padding: '2px',
                        display: 'flex', alignItems: 'center', justifyContent: 'center',
                        transition: 'color 0.12s',
                      }}
                      onMouseEnter={e => (e.currentTarget.style.color = '#8A8A96')}
                      onMouseLeave={e => (e.currentTarget.style.color = '#525260')}
                      tabIndex={-1}
                      aria-label={showPassword ? 'Hide password' : 'Show password'}
                    >
                      {showPassword ? <EyeOffIcon /> : <EyeIcon />}
                    </button>
                  </div>

                  <div style={{ position: 'relative' }}>
                    <input
                      type={showConfirmPassword ? 'text' : 'password'}
                      placeholder="Confirm password"
                      value={confirmPassword}
                      onChange={e => setConfirmPassword(e.target.value)}
                      required
                      style={{ ...inputStyle, paddingRight: '40px' }}
                    />
                    <button
                      type="button"
                      onClick={() => setShowConfirmPassword(v => !v)}
                      style={{
                        position: 'absolute', right: '12px', top: '50%',
                        transform: 'translateY(-50%)',
                        background: 'none', border: 'none', cursor: 'pointer',
                        color: '#525260', padding: '2px',
                        display: 'flex', alignItems: 'center', justifyContent: 'center',
                        transition: 'color 0.12s',
                      }}
                      onMouseEnter={e => (e.currentTarget.style.color = '#8A8A96')}
                      onMouseLeave={e => (e.currentTarget.style.color = '#525260')}
                      tabIndex={-1}
                      aria-label={showConfirmPassword ? 'Hide password' : 'Show password'}
                    >
                      {showConfirmPassword ? <EyeOffIcon /> : <EyeIcon />}
                    </button>
                  </div>

                  {/* ToS */}
                  <div style={{ display: 'flex', alignItems: 'center', gap: '10px', marginTop: '4px' }}>
                    <div
                      onClick={() => setTosAgreed(a => !a)}
                      style={{
                        width: '18px', height: '18px', flexShrink: 0,
                        borderRadius: '5px', cursor: 'pointer',
                        border: `1.5px solid ${tosAgreed ? '#3ECFB2' : 'rgba(255,255,255,0.15)'}`,
                        background: tosAgreed ? 'rgba(62,207,178,0.14)' : 'transparent',
                        display: 'flex', alignItems: 'center', justifyContent: 'center',
                        transition: 'border-color 0.15s, background 0.15s',
                      }}
                    >
                      {tosAgreed && (
                        <span style={{ color: '#3ECFB2', fontSize: '10px', fontWeight: 800, lineHeight: 1 }}>✓</span>
                      )}
                    </div>
                    <span style={{ fontSize: '12px', color: '#525260' }}>
                      I agree to the{' '}
                      <button
                        type="button"
                        className="tos-link"
                        onClick={() => setShowTosModal(true)}
                        style={{
                          background: 'none', border: 'none', padding: 0,
                          color: '#3ECFB2', fontSize: '12px',
                          cursor: 'pointer', textDecoration: 'underline',
                          fontFamily: 'inherit', opacity: 1,
                          transition: 'opacity 0.12s',
                        }}
                      >
                        Terms of Service
                      </button>
                    </span>
                  </div>

                  <button
                    type="submit"
                    disabled={loading || !tosAgreed}
                    className="cta-btn"
                    style={{
                      width: '100%', padding: '12px',
                      border: 'none', borderRadius: '10px',
                      background: `linear-gradient(135deg, ${selectedPlan.accentColor}, ${selectedPlan.accentColor}CC)`,
                      color: selectedPlan.recommended ? '#080809' : '#fff',
                      fontSize: '13px', fontWeight: 700,
                      cursor: tosAgreed && !loading ? 'pointer' : 'not-allowed',
                      marginTop: '4px',
                      letterSpacing: '-0.01em',
                      boxShadow: tosAgreed ? `0 0 24px ${selectedPlan.accentColor}22` : 'none',
                      transition: 'box-shadow 0.2s',
                    }}
                  >
                    {loading ? 'Creating account…' : 'Continue to checkout →'}
                  </button>

                  <p style={{ color: 'rgba(255,255,255,0.20)', fontSize: '11px', textAlign: 'center' }}>
                    Already have an account?{' '}
                    <a href="/auth/login" style={{ color: '#3ECFB2', textDecoration: 'none' }}>Sign in</a>
                  </p>
                </form>
              </div>
            </FadeUp>
          </div>
        )}

        {/* Footer */}
        <footer style={{
          borderTop: '1px solid rgba(255,255,255,0.05)',
          padding: '24px',
          textAlign: 'center',
        }}>
          <p style={{ color: 'rgba(255,255,255,0.15)', fontSize: '11px', letterSpacing: '0.02em' }}>
            InterLinked® · All rights reserved
          </p>
        </footer>

      </main>
    </>
  )
}

function EyeIcon() {
  return (
    <svg width="16" height="16" viewBox="0 0 16 16" fill="none" xmlns="http://www.w3.org/2000/svg">
      <path d="M1 8C1 8 3.5 3.5 8 3.5C12.5 3.5 15 8 15 8C15 8 12.5 12.5 8 12.5C3.5 12.5 1 8 1 8Z"
        stroke="currentColor" strokeWidth="1.2" strokeLinejoin="round"/>
      <circle cx="8" cy="8" r="2" stroke="currentColor" strokeWidth="1.2"/>
    </svg>
  )
}

function EyeOffIcon() {
  return (
    <svg width="16" height="16" viewBox="0 0 16 16" fill="none" xmlns="http://www.w3.org/2000/svg">
      <path d="M2 2L14 14" stroke="currentColor" strokeWidth="1.2" strokeLinecap="round"/>
      <path d="M6.5 4C7 3.8 7.5 3.5 8 3.5C12.5 3.5 15 8 15 8C15 8 14.3 9.3 13.2 10.4"
        stroke="currentColor" strokeWidth="1.2" strokeLinecap="round"/>
      <path d="M4 5.5C2.6 6.5 1.5 7.7 1 8C1 8 3.5 12.5 8 12.5C9.2 12.5 10.3 12.1 11.2 11.5"
        stroke="currentColor" strokeWidth="1.2" strokeLinecap="round"/>
      <path d="M5.8 5.8A2 2 0 0 0 10.2 10.2" stroke="currentColor" strokeWidth="1.2" strokeLinecap="round"/>
    </svg>
  )
}

const inputStyle: React.CSSProperties = {
  width: '100%',
  padding: '11px 14px',
  background: 'rgba(255,255,255,0.04)',
  border: '1px solid rgba(255,255,255,0.09)',
  borderRadius: '9px',
  color: '#FFFFFF',
  fontSize: '13px',
  outline: 'none',
  boxSizing: 'border-box',
  transition: 'border-color 0.15s, box-shadow 0.15s',
  letterSpacing: '-0.005em',
}
