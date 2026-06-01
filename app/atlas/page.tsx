'use client'

import { useState, useEffect } from 'react'
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
    period: '/month',
    color: '#5B8DEF',
    recommended: false,
    features: ['1 device', '3 installs per day', 'Install history', 'Notifications'],
    excluded: ['Bulk installation', 'Uninstall & Rollback', 'TITAN CORE™', 'Smart Storage'],
    stripeUrl: 'https://buy.stripe.com/7sYcN4b66b0l3VJ1judjO00',
  },
  {
    id: 'pro',
    name: 'Pro',
    price: '$29.99',
    period: '/month',
    color: '#3ECFB2',
    recommended: true,
    features: [
      'Up to 3 devices',
      'Unlimited installs',
      'Bulk installation',
      'Uninstall & Rollback',
      'TITAN CORE™',
      'Smart Storage',
      'Full install history',
    ],
    excluded: [],
    stripeUrl: 'https://buy.stripe.com/aFafZg7TUc4p0Jx7HSdjO01',
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
ATLAS is available on Standard (free) and Pro (paid) plans. Subscriptions are managed through InterLinked® at interlinked.digital/atlas. Cancellations take effect at the end of the current billing period.

9. CHANGES
InterLinked® reserves the right to update these terms at any time. Continued use of ATLAS constitutes acceptance of the current terms.

10. CONTACT
interlinked.digital@gmail.com
interlinked.digital`

type Plan = typeof PLANS[0]
type Step = 'plan' | 'account'

function TosModal({ onClose }: { onClose: () => void }) {
  const [opacity, setOpacity] = useState(0)

  useEffect(() => {
    requestAnimationFrame(() => setOpacity(1))
  }, [])

  function close() {
    setOpacity(0)
    setTimeout(onClose, 160)
  }

  return (
    <div
      onClick={close}
      style={{
        position: 'fixed', inset: 0, zIndex: 100,
        background: 'rgba(0,0,0,0.65)',
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        padding: '24px',
        opacity, transition: 'opacity 0.17s ease',
      }}
    >
      <div
        onClick={e => e.stopPropagation()}
        style={{
          background: '#0A0D1C',
          border: '1px solid #1E2240',
          borderRadius: '14px',
          width: '100%', maxWidth: '520px',
          boxShadow: '0 32px 80px rgba(0,0,0,0.7)',
          overflow: 'hidden',
          opacity, transform: `scale(${0.97 + 0.03 * opacity})`,
          transition: 'opacity 0.17s ease, transform 0.17s ease',
        }}
      >
        {/* Header */}
        <div style={{
          display: 'flex', alignItems: 'center', justifyContent: 'space-between',
          padding: '12px 16px',
          borderBottom: '1px solid #1E2240',
        }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
            <span style={{ color: '#3ECFB2', fontSize: '13px' }}>📄</span>
            <span style={{ color: '#F0F2FF', fontSize: '13px', fontWeight: 600 }}>
              Terms of Service — ATLAS by InterLinked®
            </span>
          </div>
          <button
            onClick={close}
            style={{
              background: '#1E2240', border: 'none', borderRadius: '6px',
              width: '24px', height: '24px', cursor: 'pointer',
              color: '#6B7399', fontSize: '11px', fontWeight: 700,
              display: 'flex', alignItems: 'center', justifyContent: 'center',
            }}
          >✕</button>
        </div>

        {/* Content */}
        <div style={{ maxHeight: '360px', overflowY: 'auto', padding: '16px' }}>
          <pre style={{
            color: '#A0A8C8', fontSize: '11.5px', lineHeight: '1.75',
            whiteSpace: 'pre-wrap', fontFamily: 'inherit', margin: 0,
          }}>
            {TOS_TEXT}
          </pre>
        </div>

        <div style={{ borderTop: '1px solid #1E2240' }}>
          <button
            onClick={close}
            style={{
              width: '100%', padding: '11px', border: 'none',
              background: '#0F1327', color: '#F0F2FF',
              fontSize: '12px', fontWeight: 600, cursor: 'pointer',
            }}
          >
            Close
          </button>
        </div>
      </div>
    </div>
  )
}

export default function AtlasSignupPage() {
  const [step, setStep] = useState<Step>('plan')
  const [selectedPlan, setSelectedPlan] = useState<Plan | null>(null)
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [confirmPassword, setConfirmPassword] = useState('')
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState('')
  const [tosAgreed, setTosAgreed] = useState(false)
  const [showTosModal, setShowTosModal] = useState(false)

  function handleSelectPlan(plan: Plan) {
    setSelectedPlan(plan)
    setError('')
    setTosAgreed(false)
    setStep('account')
  }

  async function handleSignup(e: React.FormEvent) {
    e.preventDefault()
    if (!selectedPlan) return
    if (!tosAgreed) { setError('Please agree to the Terms of Service to continue.'); return }
    setError('')

    if (password !== confirmPassword) { setError('Passwords do not match.'); return }
    if (password.length < 8) { setError('Password must be at least 8 characters.'); return }

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
          font-family: 'Bezmiar';
          src: url('/fonts/Bezmiar-Regular.otf') format('opentype');
          font-weight: normal;
          font-style: normal;
          font-display: swap;
        }
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body { background: #07080F; }
        input { transition: border-color 0.15s; }
        input::placeholder { color: #2E3355; }
        input:focus { border-color: #4A5280 !important; outline: none; }
        button { transition: opacity 0.15s, transform 0.1s; }
        button:hover:not(:disabled) { opacity: 0.88; }
        button:active:not(:disabled) { transform: scale(0.985); }
        button:disabled { opacity: 0.45; cursor: not-allowed; }
        .plan-card { transition: border-color 0.15s, box-shadow 0.15s; }
        .plan-card:hover { border-color: var(--plan-color) !important; box-shadow: 0 0 0 1px var(--plan-color)22; }
        .tos-checkbox { transition: background 0.15s, border-color 0.15s; }
        .tos-link { transition: opacity 0.12s; }
        .tos-link:hover { opacity: 0.75; }
      `}</style>

      {showTosModal && <TosModal onClose={() => setShowTosModal(false)} />}

      <main style={{
        minHeight: '100vh',
        background: '#07080F',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        padding: '32px 20px',
        fontFamily: '-apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif',
      }}>
        <div style={{ width: '100%', maxWidth: step === 'plan' ? '580px' : '440px', transition: 'max-width 0.2s' }}>

          {/* ATLAS header */}
          <div style={{ textAlign: 'center', marginBottom: '40px' }}>
            <h1 style={{
              color: '#E8ECFF',
              fontSize: '48px',
              fontWeight: 'normal',
              letterSpacing: '12px',
              fontFamily: 'Bezmiar, -apple-system, sans-serif',
              lineHeight: 1,
              marginBottom: '8px',
              textIndent: '12px',
            }}>ATLAS</h1>
            <p style={{ color: '#353860', fontSize: '11px', letterSpacing: '3px', textTransform: 'uppercase' }}>
              by InterLinked
            </p>
          </div>

          {/* ── Step 1: Plan selection ── */}
          {step === 'plan' && (
            <div>
              <div style={{ textAlign: 'center', marginBottom: '22px' }}>
                <h2 style={{ color: '#C0C8E8', fontSize: '15px', fontWeight: '500', marginBottom: '5px' }}>
                  Choose your plan
                </h2>
                <p style={{ color: '#353860', fontSize: '12px' }}>
                  Create your account right after — takes 30 seconds
                </p>
              </div>

              <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '14px' }}>
                {PLANS.map(plan => (
                  <div
                    key={plan.id}
                    className="plan-card"
                    style={{
                      '--plan-color': plan.color,
                      background: '#0C0E1C',
                      borderRadius: '12px',
                      border: `1px solid ${plan.recommended ? plan.color + '55' : '#1E2240'}`,
                      overflow: 'hidden',
                      display: 'flex',
                      flexDirection: 'column',
                    } as React.CSSProperties}
                  >
                    {plan.recommended && (
                      <div style={{
                        background: `linear-gradient(90deg, ${plan.color}25, ${plan.color}10)`,
                        borderBottom: `1px solid ${plan.color}30`,
                        padding: '5px 0',
                        textAlign: 'center',
                        color: plan.color,
                        fontSize: '8px',
                        fontWeight: '800',
                        letterSpacing: '2px',
                      }}>
                        MOST POPULAR
                      </div>
                    )}

                    <div style={{
                      padding: '16px',
                      background: plan.color + '08',
                      borderBottom: '1px solid #1E2240',
                    }}>
                      <div style={{
                        color: plan.color,
                        fontSize: '10px',
                        fontWeight: '800',
                        letterSpacing: '1.8px',
                        marginBottom: '8px',
                      }}>
                        {plan.name.toUpperCase()}
                      </div>
                      <div>
                        <span style={{ color: '#E8ECFF', fontSize: '28px', fontWeight: '700', lineHeight: 1 }}>
                          {plan.price}
                        </span>
                        <span style={{ color: '#353860', fontSize: '11px' }}>{plan.period}</span>
                      </div>
                    </div>

                    <div style={{ padding: '14px 16px', flex: 1, display: 'flex', flexDirection: 'column', gap: '8px' }}>
                      {plan.features.map(f => (
                        <div key={f} style={{ display: 'flex', gap: '8px', alignItems: 'flex-start' }}>
                          <span style={{ color: plan.color, fontSize: '9px', fontWeight: '800', marginTop: '3px', flexShrink: 0 }}>✓</span>
                          <span style={{ color: '#A8B4D0', fontSize: '11px', lineHeight: 1.4 }}>{f}</span>
                        </div>
                      ))}
                      {plan.excluded.map(f => (
                        <div key={f} style={{ display: 'flex', gap: '8px', alignItems: 'flex-start' }}>
                          <span style={{ color: '#252845', fontSize: '9px', fontWeight: '800', marginTop: '3px', flexShrink: 0 }}>✕</span>
                          <span style={{ color: '#252845', fontSize: '11px', lineHeight: 1.4 }}>{f}</span>
                        </div>
                      ))}
                    </div>

                    <div style={{ padding: '0 14px 14px' }}>
                      <button
                        onClick={() => handleSelectPlan(plan)}
                        style={{
                          width: '100%',
                          padding: '10px',
                          borderRadius: '8px',
                          border: plan.recommended ? 'none' : `1px solid ${plan.color}45`,
                          background: plan.recommended
                            ? `linear-gradient(135deg, ${plan.color}, ${plan.color}BB)`
                            : plan.color + '14',
                          color: plan.recommended ? '#07080F' : plan.color,
                          fontSize: '11px',
                          fontWeight: '700',
                          cursor: 'pointer',
                          letterSpacing: '0.3px',
                        }}
                      >
                        Get Started — {plan.name}
                      </button>
                    </div>
                  </div>
                ))}
              </div>

              <div style={{ marginTop: '22px', textAlign: 'center', display: 'flex', flexDirection: 'column', gap: '6px' }}>
                <p style={{ color: '#252845', fontSize: '11px' }}>
                  Secure payment via Stripe · Cancel anytime
                </p>
                <p style={{ color: '#252845', fontSize: '11px' }}>
                  Already subscribed?{' '}
                  <a href="/auth/login" style={{ color: '#3C4A70', textDecoration: 'none' }}>
                    Sign in →
                  </a>
                </p>
              </div>
            </div>
          )}

          {/* ── Step 2: Create account ── */}
          {step === 'account' && selectedPlan && (
            <div>
              <div style={{
                background: selectedPlan.color + '0E',
                border: `1px solid ${selectedPlan.color}35`,
                borderRadius: '10px',
                padding: '12px 16px',
                marginBottom: '14px',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'space-between',
              }}>
                <div>
                  <div style={{ color: selectedPlan.color, fontSize: '9px', fontWeight: '800', letterSpacing: '1.5px', marginBottom: '3px' }}>
                    {selectedPlan.name.toUpperCase()} PLAN SELECTED
                  </div>
                  <div>
                    <span style={{ color: '#E8ECFF', fontSize: '14px', fontWeight: '600' }}>
                      {selectedPlan.price}
                    </span>
                    <span style={{ color: '#353860', fontSize: '11px' }}>{selectedPlan.period}</span>
                  </div>
                </div>
                <button
                  onClick={() => { setStep('plan'); setError(''); setTosAgreed(false) }}
                  style={{
                    background: 'none',
                    border: '1px solid #1E2240',
                    borderRadius: '6px',
                    padding: '5px 11px',
                    color: '#4A5280',
                    fontSize: '10px',
                    cursor: 'pointer',
                    fontWeight: '500',
                  }}
                >
                  Change
                </button>
              </div>

              <div style={{
                background: '#0C0E1C',
                borderRadius: '12px',
                border: '1px solid #1E2240',
                overflow: 'hidden',
              }}>
                <div style={{
                  padding: '14px 18px',
                  borderBottom: '1px solid #1E2240',
                  background: '#0F1128',
                }}>
                  <h2 style={{ color: '#C8D0E8', fontSize: '13px', fontWeight: '600' }}>
                    Create your account
                  </h2>
                  <p style={{ color: '#353860', fontSize: '11px', marginTop: '3px' }}>
                    You&apos;ll be taken to secure checkout after
                  </p>
                </div>

                <form onSubmit={handleSignup} style={{ padding: '18px', display: 'flex', flexDirection: 'column', gap: '10px' }}>
                  {error && (
                    <div style={{
                      background: 'rgba(224,85,85,0.07)',
                      border: '1px solid rgba(224,85,85,0.22)',
                      borderRadius: '8px',
                      padding: '9px 12px',
                      color: '#E05555',
                      fontSize: '12px',
                    }}>{error}</div>
                  )}

                  <input
                    type="email"
                    placeholder="Email address"
                    value={email}
                    onChange={e => setEmail(e.target.value)}
                    required
                    style={inputStyle}
                  />
                  <input
                    type="password"
                    placeholder="Password (min 8 characters)"
                    value={password}
                    onChange={e => setPassword(e.target.value)}
                    required
                    style={inputStyle}
                  />
                  <input
                    type="password"
                    placeholder="Confirm password"
                    value={confirmPassword}
                    onChange={e => setConfirmPassword(e.target.value)}
                    required
                    style={inputStyle}
                  />

                  {/* ToS checkbox */}
                  <div style={{ display: 'flex', alignItems: 'center', gap: '10px', marginTop: '2px' }}>
                    <div
                      className="tos-checkbox"
                      onClick={() => setTosAgreed(a => !a)}
                      style={{
                        width: '18px', height: '18px', flexShrink: 0,
                        borderRadius: '4px', cursor: 'pointer',
                        border: `1.5px solid ${tosAgreed ? '#3ECFB2' : '#2E3355'}`,
                        background: tosAgreed ? 'rgba(62,207,178,0.12)' : '#07080F',
                        display: 'flex', alignItems: 'center', justifyContent: 'center',
                      }}
                    >
                      {tosAgreed && (
                        <span style={{ color: '#3ECFB2', fontSize: '10px', fontWeight: 800, lineHeight: 1 }}>✓</span>
                      )}
                    </div>
                    <span style={{ fontSize: '11px', color: '#7080A0' }}>
                      I agree to the{' '}
                      <button
                        type="button"
                        className="tos-link"
                        onClick={() => setShowTosModal(true)}
                        style={{
                          background: 'none', border: 'none', padding: 0,
                          color: '#3ECFB2', fontSize: '11px', cursor: 'pointer',
                          textDecoration: 'underline', fontFamily: 'inherit',
                        }}
                      >
                        Terms of Service
                      </button>
                    </span>
                  </div>

                  <button
                    type="submit"
                    disabled={loading || !tosAgreed}
                    style={{
                      width: '100%',
                      padding: '11px',
                      border: 'none',
                      borderRadius: '9px',
                      background: `linear-gradient(135deg, ${selectedPlan.color}, ${selectedPlan.color}BB)`,
                      color: selectedPlan.recommended ? '#07080F' : '#fff',
                      fontSize: '13px',
                      fontWeight: '600',
                      cursor: tosAgreed && !loading ? 'pointer' : 'not-allowed',
                      marginTop: '2px',
                    }}
                  >
                    {loading ? 'Creating account…' : 'Continue to Checkout →'}
                  </button>

                  <p style={{ color: '#252845', fontSize: '11px', textAlign: 'center' }}>
                    Already have an account?{' '}
                    <a href="/auth/login" style={{ color: '#3ECFB2', textDecoration: 'none' }}>
                      Sign in
                    </a>
                  </p>
                </form>
              </div>
            </div>
          )}

          <p style={{ color: '#181A2A', fontSize: '10px', textAlign: 'center', marginTop: '28px' }}>
            InterLinked© · All rights reserved
          </p>
        </div>
      </main>
    </>
  )
}

const inputStyle: React.CSSProperties = {
  width: '100%',
  padding: '10px 12px',
  background: '#07080F',
  border: '1px solid #1E2240',
  borderRadius: '8px',
  color: '#D0D8F0',
  fontSize: '13px',
  outline: 'none',
  boxSizing: 'border-box',
}
