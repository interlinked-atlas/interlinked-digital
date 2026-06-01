'use client'

import { useState } from 'react'
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

type Plan = typeof PLANS[0]
type Step = 'plan' | 'account'

export default function AtlasPage() {
  const [step, setStep] = useState<Step>('plan')
  const [selectedPlan, setSelectedPlan] = useState<Plan | null>(null)
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [confirmPassword, setConfirmPassword] = useState('')
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState('')

  function handleSelectPlan(plan: Plan) {
    setSelectedPlan(plan)
    setError('')
    setStep('account')
  }

  async function handleSignup(e: React.FormEvent) {
    e.preventDefault()
    if (!selectedPlan) return
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
          font-family: 'SF-Intellivised';
          src: url('/fonts/SF-Intellivised.ttf') format('truetype');
          font-weight: normal; font-style: normal; font-display: swap;
        }
        @font-face {
          font-family: 'Bezmiar';
          src: url('/fonts/Bezmiar-Regular.otf') format('opentype');
          font-weight: normal; font-style: normal; font-display: swap;
        }
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body { background: #07080F; }
        input { transition: border-color 0.15s; }
        input::placeholder { color: #252845; }
        input:focus { border-color: #4A5280 !important; outline: none; }
        button { transition: opacity 0.15s, transform 0.1s; }
        button:hover:not(:disabled) { opacity: 0.88; }
        button:active:not(:disabled) { transform: scale(0.985); }
        button:disabled { opacity: 0.45; cursor: not-allowed; }
        .plan-card { transition: border-color 0.15s, box-shadow 0.15s; }
        .plan-card:hover { border-color: var(--plan-color) !important; box-shadow: 0 0 0 1px var(--plan-color)22; }
      `}</style>

      <main style={{
        minHeight: '100vh',
        background: '#07080F',
        backgroundImage: `
          linear-gradient(rgba(62,207,178,0.02) 1px, transparent 1px),
          linear-gradient(90deg, rgba(62,207,178,0.02) 1px, transparent 1px)
        `,
        backgroundSize: '60px 60px',
        display: 'flex',
        flexDirection: 'column',
        alignItems: 'center',
        fontFamily: '-apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif',
      }}>

        {/* ── Top navigation bar ── */}
        <nav style={{
          width: '100%',
          maxWidth: '900px',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'space-between',
          padding: '18px 24px',
          position: 'sticky',
          top: 0,
          zIndex: 50,
          background: 'rgba(7,8,15,0.85)',
          backdropFilter: 'blur(12px)',
          borderBottom: '1px solid #1E2240',
        }}>
          {/* Home button */}
          <a
            href="/"
            style={{
              display: 'flex',
              alignItems: 'center',
              gap: '8px',
              color: '#6B7399',
              textDecoration: 'none',
              fontSize: '11px',
              letterSpacing: '1px',
              fontWeight: 500,
              padding: '6px 12px',
              borderRadius: '7px',
              border: '1px solid #1E2240',
              background: 'transparent',
              transition: 'color 0.15s, border-color 0.15s',
            }}
            onMouseEnter={e => {
              (e.currentTarget as HTMLAnchorElement).style.color = '#A8B4D0'
              ;(e.currentTarget as HTMLAnchorElement).style.borderColor = '#2E3350'
            }}
            onMouseLeave={e => {
              (e.currentTarget as HTMLAnchorElement).style.color = '#6B7399'
              ;(e.currentTarget as HTMLAnchorElement).style.borderColor = '#1E2240'
            }}
          >
            ← HOME
          </a>

          {/* Centered wordmark */}
          <span style={{
            color: '#252845',
            fontSize: '9px',
            letterSpacing: '4px',
            textTransform: 'uppercase',
            fontWeight: 500,
          }}>
            BY INTERLINKED
          </span>

          {/* Login button */}
          <a
            href="/auth/login"
            style={{
              display: 'flex',
              alignItems: 'center',
              gap: '6px',
              color: '#3ECFB2',
              textDecoration: 'none',
              fontSize: '11px',
              letterSpacing: '1px',
              fontWeight: 600,
              padding: '6px 14px',
              borderRadius: '7px',
              border: '1px solid rgba(62,207,178,0.3)',
              background: 'rgba(62,207,178,0.06)',
              transition: 'background 0.15s, border-color 0.15s',
            }}
            onMouseEnter={e => {
              (e.currentTarget as HTMLAnchorElement).style.background = 'rgba(62,207,178,0.12)'
              ;(e.currentTarget as HTMLAnchorElement).style.borderColor = 'rgba(62,207,178,0.5)'
            }}
            onMouseLeave={e => {
              (e.currentTarget as HTMLAnchorElement).style.background = 'rgba(62,207,178,0.06)'
              ;(e.currentTarget as HTMLAnchorElement).style.borderColor = 'rgba(62,207,178,0.3)'
            }}
          >
            LOGIN →
          </a>
        </nav>

        {/* ── Page body ── */}
        <div style={{
          width: '100%',
          maxWidth: step === 'plan' ? '620px' : '440px',
          transition: 'max-width 0.25s ease',
          padding: '40px 20px 60px',
        }}>

          {/* ── ATLAS header ── */}
          <div style={{ textAlign: 'center', marginBottom: '44px' }}>
            {/* Logo */}
            <div style={{ marginBottom: '16px' }}>
              <img
                src="/images/ATLASLogo.png"
                alt="ATLAS"
                style={{
                  width: '72px',
                  height: '72px',
                  objectFit: 'contain',
                  margin: '0 auto',
                  display: 'block',
                  filter: 'drop-shadow(0 0 16px rgba(62,207,178,0.25))',
                }}
              />
            </div>

            {/* ATLAS wordmark */}
            <h1 style={{
              color: '#E8ECFF',
              fontSize: '52px',
              fontWeight: 'normal',
              letterSpacing: '14px',
              fontFamily: "'SF-Intellivised', 'Bezmiar', -apple-system, sans-serif",
              lineHeight: 1,
              marginBottom: '8px',
              textIndent: '14px',
              textShadow: '0 0 40px rgba(62,207,178,0.15)',
            }}>
              ATLAS
            </h1>
            <p style={{ color: '#353860', fontSize: '10px', letterSpacing: '3.5px', textTransform: 'uppercase' }}>
              by InterLinked
            </p>
          </div>

          {/* ── Step 1: Plan selection ── */}
          {step === 'plan' && (
            <div>
              <div style={{ textAlign: 'center', marginBottom: '24px' }}>
                <h2 style={{ color: '#C0C8E8', fontSize: '15px', fontWeight: 500, marginBottom: '5px' }}>
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
                        background: `linear-gradient(90deg, ${plan.color}22, ${plan.color}0D)`,
                        borderBottom: `1px solid ${plan.color}30`,
                        padding: '5px 0',
                        textAlign: 'center',
                        color: plan.color,
                        fontSize: '8px',
                        fontWeight: 800,
                        letterSpacing: '2.5px',
                      }}>
                        MOST POPULAR
                      </div>
                    )}

                    <div style={{
                      padding: '16px',
                      background: plan.color + '07',
                      borderBottom: '1px solid #1A1D30',
                    }}>
                      <div style={{
                        color: plan.color,
                        fontSize: '10px',
                        fontWeight: 800,
                        letterSpacing: '2px',
                        marginBottom: '8px',
                      }}>
                        {plan.name.toUpperCase()}
                      </div>
                      <div>
                        <span style={{ color: '#E8ECFF', fontSize: '28px', fontWeight: 700, lineHeight: 1 }}>
                          {plan.price}
                        </span>
                        <span style={{ color: '#353860', fontSize: '11px' }}>{plan.period}</span>
                      </div>
                    </div>

                    <div style={{ padding: '14px 16px', flex: 1, display: 'flex', flexDirection: 'column', gap: '8px' }}>
                      {plan.features.map(f => (
                        <div key={f} style={{ display: 'flex', gap: '8px', alignItems: 'flex-start' }}>
                          <span style={{ color: plan.color, fontSize: '9px', fontWeight: 800, marginTop: '3px', flexShrink: 0 }}>✓</span>
                          <span style={{ color: '#A8B4D0', fontSize: '11px', lineHeight: 1.4 }}>{f}</span>
                        </div>
                      ))}
                      {plan.excluded.map(f => (
                        <div key={f} style={{ display: 'flex', gap: '8px', alignItems: 'flex-start' }}>
                          <span style={{ color: '#1E2240', fontSize: '9px', fontWeight: 800, marginTop: '3px', flexShrink: 0 }}>✕</span>
                          <span style={{ color: '#1E2240', fontSize: '11px', lineHeight: 1.4 }}>{f}</span>
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
                            : plan.color + '12',
                          color: plan.recommended ? '#07080F' : plan.color,
                          fontSize: '11px',
                          fontWeight: 700,
                          cursor: 'pointer',
                          letterSpacing: '0.5px',
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
                  <a href="/auth/login" style={{ color: '#2E4060', textDecoration: 'none' }}>
                    Sign in →
                  </a>
                </p>
              </div>
            </div>
          )}

          {/* ── Step 2: Create account ── */}
          {step === 'account' && selectedPlan && (
            <div>
              {/* Selected plan summary */}
              <div style={{
                background: selectedPlan.color + '0D',
                border: `1px solid ${selectedPlan.color}35`,
                borderRadius: '10px',
                padding: '12px 16px',
                marginBottom: '14px',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'space-between',
              }}>
                <div>
                  <div style={{ color: selectedPlan.color, fontSize: '9px', fontWeight: 800, letterSpacing: '1.5px', marginBottom: '3px' }}>
                    {selectedPlan.name.toUpperCase()} PLAN SELECTED
                  </div>
                  <div>
                    <span style={{ color: '#E8ECFF', fontSize: '14px', fontWeight: 600 }}>{selectedPlan.price}</span>
                    <span style={{ color: '#353860', fontSize: '11px' }}>{selectedPlan.period}</span>
                  </div>
                </div>
                <button
                  onClick={() => { setStep('plan'); setError('') }}
                  style={{
                    background: 'none',
                    border: '1px solid #1E2240',
                    borderRadius: '6px',
                    padding: '5px 11px',
                    color: '#4A5280',
                    fontSize: '10px',
                    cursor: 'pointer',
                    fontWeight: 500,
                  }}
                >
                  Change
                </button>
              </div>

              {/* Signup form */}
              <div style={{
                background: '#0C0E1C',
                borderRadius: '12px',
                border: '1px solid #1E2240',
                overflow: 'hidden',
              }}>
                <div style={{
                  padding: '14px 18px',
                  borderBottom: '1px solid #1A1D30',
                  background: '#0A0D1C',
                }}>
                  <h2 style={{ color: '#C8D0E8', fontSize: '13px', fontWeight: 600 }}>
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

                  <input type="email" placeholder="Email address" value={email}
                    onChange={e => setEmail(e.target.value)} required style={inputStyle} />
                  <input type="password" placeholder="Password (min 8 characters)" value={password}
                    onChange={e => setPassword(e.target.value)} required style={inputStyle} />
                  <input type="password" placeholder="Confirm password" value={confirmPassword}
                    onChange={e => setConfirmPassword(e.target.value)} required style={inputStyle} />

                  <button
                    type="submit"
                    disabled={loading}
                    style={{
                      width: '100%',
                      padding: '11px',
                      border: 'none',
                      borderRadius: '9px',
                      background: `linear-gradient(135deg, ${selectedPlan.color}, ${selectedPlan.color}BB)`,
                      color: selectedPlan.recommended ? '#07080F' : '#fff',
                      fontSize: '13px',
                      fontWeight: 600,
                      cursor: 'pointer',
                      marginTop: '2px',
                    }}
                  >
                    {loading ? 'Creating account…' : 'Sign Up & Continue to Checkout →'}
                  </button>

                  <p style={{ color: '#252845', fontSize: '11px', textAlign: 'center' }}>
                    Have an account?{' '}
                    <a href="/auth/login" style={{ color: '#3ECFB2', textDecoration: 'none' }}>
                      Login Here.
                    </a>
                  </p>
                </form>
              </div>
            </div>
          )}

          <p style={{ color: '#13151F', fontSize: '10px', textAlign: 'center', marginTop: '32px', letterSpacing: '1.5px' }}>
            INTERLINKED© · ALL RIGHTS RESERVED
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
}
