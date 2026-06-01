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

export default function AtlasSignupPage() {
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
          font-family: 'Bezmiar';
          src: url('/fonts/Bezmiar-Regular.otf') format('opentype');
          font-weight: normal; font-style: normal; font-display: swap;
        }
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body { background: #07080F; }
        input { transition: border-color 0.15s; }
        input::placeholder { color: #2A2D50; }
        input:focus { border-color: #4A5280 !important; outline: none; }
        button { transition: opacity 0.15s, transform 0.1s; }
        button:hover:not(:disabled) { opacity: 0.88; }
        button:active:not(:disabled) { transform: scale(0.985); }
        button:disabled { opacity: 0.45; cursor: not-allowed; }
      `}</style>

      <main style={{
        minHeight: '100vh', background: '#07080F', display: 'flex',
        alignItems: 'center', justifyContent: 'center',
        padding: '32px 20px',
        fontFamily: '-apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif',
      }}>
        <div style={{ width: '100%', maxWidth: step === 'plan' ? '580px' : '440px' }}>

          {/* ATLAS heading */}
          <div style={{ textAlign: 'center', marginBottom: '40px' }}>
            <h1 style={{
              color: '#E8ECFF', fontSize: '48px', fontWeight: 'normal',
              letterSpacing: '12px', fontFamily: 'Bezmiar, -apple-system, sans-serif',
              lineHeight: 1, marginBottom: '8px', textIndent: '12px',
            }}>ATLAS</h1>
            <p style={{ color: '#303460', fontSize: '11px', letterSpacing: '3px', textTransform: 'uppercase' }}>
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
                <p style={{ color: '#303460', fontSize: '12px' }}>
                  Create your account right after — takes 30 seconds
                </p>
              </div>

              <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '14px' }}>
                {PLANS.map(plan => (
                  <div key={plan.id} style={{
                    background: '#0C0E1C', borderRadius: '12px',
                    border: `1px solid ${plan.recommended ? plan.color + '55' : '#1A1D38'}`,
                    overflow: 'hidden', display: 'flex', flexDirection: 'column',
                  }}>
                    {plan.recommended && (
                      <div style={{
                        background: plan.color + '20', borderBottom: `1px solid ${plan.color}25`,
                        padding: '5px 0', textAlign: 'center',
                        color: plan.color, fontSize: '8px', fontWeight: '800', letterSpacing: '2px',
                      }}>MOST POPULAR</div>
                    )}
                    <div style={{
                      padding: '16px', background: plan.color + '08',
                      borderBottom: '1px solid #1A1D38',
                    }}>
                      <div style={{ color: plan.color, fontSize: '10px', fontWeight: '800', letterSpacing: '1.8px', marginBottom: '8px' }}>
                        {plan.name.toUpperCase()}
                      </div>
                      <div>
                        <span style={{ color: '#E8ECFF', fontSize: '28px', fontWeight: '700', lineHeight: 1 }}>{plan.price}</span>
                        <span style={{ color: '#303460', fontSize: '11px' }}>{plan.period}</span>
                      </div>
                    </div>
                    <div style={{ padding: '14px 16px', flex: 1, display: 'flex', flexDirection: 'column', gap: '8px' }}>
                      {plan.features.map(f => (
                        <div key={f} style={{ display: 'flex', gap: '8px', alignItems: 'flex-start' }}>
                          <span style={{ color: plan.color, fontSize: '9px', fontWeight: '800', marginTop: '3px', flexShrink: 0 }}>✓</span>
                          <span style={{ color: '#A0ACCC', fontSize: '11px', lineHeight: 1.4 }}>{f}</span>
                        </div>
                      ))}
                      {plan.excluded.map(f => (
                        <div key={f} style={{ display: 'flex', gap: '8px', alignItems: 'flex-start' }}>
                          <span style={{ color: '#202340', fontSize: '9px', fontWeight: '800', marginTop: '3px', flexShrink: 0 }}>✕</span>
                          <span style={{ color: '#202340', fontSize: '11px', lineHeight: 1.4 }}>{f}</span>
                        </div>
                      ))}
                    </div>
                    <div style={{ padding: '0 14px 14px' }}>
                      <button onClick={() => handleSelectPlan(plan)} style={{
                        width: '100%', padding: '10px', borderRadius: '8px',
                        border: plan.recommended ? 'none' : `1px solid ${plan.color}45`,
                        background: plan.recommended
                          ? `linear-gradient(135deg, ${plan.color}, ${plan.color}BB)`
                          : plan.color + '14',
                        color: plan.recommended ? '#07080F' : plan.color,
                        fontSize: '11px', fontWeight: '700', cursor: 'pointer',
                      }}>
                        Get Started — {plan.name}
                      </button>
                    </div>
                  </div>
                ))}
              </div>

              <div style={{ marginTop: '20px', textAlign: 'center', display: 'flex', flexDirection: 'column', gap: '6px' }}>
                <p style={{ color: '#1E2140', fontSize: '11px' }}>Secure payment via Stripe · Cancel anytime</p>
                <p style={{ color: '#2A2E55', fontSize: '11px' }}>
                  Have an Account?{' '}
                  <a href="/auth/login" style={{ color: '#3ECFB2', textDecoration: 'none', fontWeight: '600' }}>Login Here</a>
                </p>
              </div>
            </div>
          )}

          {/* ── Step 2: Create account (signup) ── */}
          {step === 'account' && selectedPlan && (
            <div>
              {/* Selected plan summary */}
              <div style={{
                background: selectedPlan.color + '0D',
                border: `1px solid ${selectedPlan.color}30`,
                borderRadius: '10px', padding: '12px 16px',
                marginBottom: '14px', display: 'flex',
                alignItems: 'center', justifyContent: 'space-between',
              }}>
                <div>
                  <div style={{ color: selectedPlan.color, fontSize: '9px', fontWeight: '800', letterSpacing: '1.5px', marginBottom: '3px' }}>
                    {selectedPlan.name.toUpperCase()} PLAN SELECTED
                  </div>
                  <div>
                    <span style={{ color: '#E8ECFF', fontSize: '14px', fontWeight: '600' }}>{selectedPlan.price}</span>
                    <span style={{ color: '#303460', fontSize: '11px' }}>{selectedPlan.period}</span>
                  </div>
                </div>
                <button onClick={() => { setStep('plan'); setError('') }} style={{
                  background: 'none', border: '1px solid #1A1D38', borderRadius: '6px',
                  padding: '5px 11px', color: '#3A4070', fontSize: '10px', cursor: 'pointer',
                }}>Change</button>
              </div>

              <div style={{
                background: '#0C0E1C', borderRadius: '12px',
                border: '1px solid #1A1D38', overflow: 'hidden',
              }}>
                {/* Header — explicitly says Sign Up */}
                <div style={{
                  padding: '14px 18px', borderBottom: '1px solid #1A1D38',
                  background: '#0F1128',
                }}>
                  <div style={{ display: 'flex', alignItems: 'center', gap: '8px', marginBottom: '3px' }}>
                    <span style={{
                      background: selectedPlan.color + '20',
                      border: `1px solid ${selectedPlan.color}40`,
                      borderRadius: '5px', padding: '2px 7px',
                      color: selectedPlan.color, fontSize: '9px', fontWeight: '800', letterSpacing: '1px',
                    }}>NEW ACCOUNT</span>
                  </div>
                  <h2 style={{ color: '#C8D0E8', fontSize: '14px', fontWeight: '600' }}>
                    Create your ATLAS account
                  </h2>
                  <p style={{ color: '#2A2E55', fontSize: '11px', marginTop: '3px' }}>
                    After signing up you&apos;ll be taken to secure Stripe checkout
                  </p>
                </div>

                <form onSubmit={handleSignup} style={{ padding: '18px', display: 'flex', flexDirection: 'column', gap: '10px' }}>
                  {error && (
                    <div style={{
                      background: 'rgba(224,85,85,0.07)', border: '1px solid rgba(224,85,85,0.22)',
                      borderRadius: '8px', padding: '9px 12px', color: '#E05555', fontSize: '12px',
                    }}>{error}</div>
                  )}
                  <input type="email" placeholder="Email address" value={email}
                    onChange={e => setEmail(e.target.value)} required style={inputStyle} />
                  <input type="password" placeholder="Password (min 8 characters)" value={password}
                    onChange={e => setPassword(e.target.value)} required style={inputStyle} />
                  <input type="password" placeholder="Confirm password" value={confirmPassword}
                    onChange={e => setConfirmPassword(e.target.value)} required style={inputStyle} />
                  <button type="submit" disabled={loading} style={{
                    width: '100%', padding: '11px', border: 'none', borderRadius: '9px',
                    background: `linear-gradient(135deg, ${selectedPlan.color}, ${selectedPlan.color}BB)`,
                    color: selectedPlan.recommended ? '#07080F' : '#fff',
                    fontSize: '13px', fontWeight: '600', cursor: 'pointer', marginTop: '2px',
                  }}>
                    {loading ? 'Creating account…' : 'Sign Up & Continue to Checkout →'}
                  </button>
                  <p style={{ color: '#202340', fontSize: '11px', textAlign: 'center' }}>
                    Have an Account?{' '}
                    <a href="/auth/login" style={{ color: '#3ECFB2', textDecoration: 'none', fontWeight: '600' }}>
                      Login Here
                    </a>
                  </p>
                </form>
              </div>
            </div>
          )}

          <p style={{ color: '#141628', fontSize: '10px', textAlign: 'center', marginTop: '28px' }}>
            InterLinked© · All rights reserved
          </p>
        </div>
      </main>
    </>
  )
}

const inputStyle: React.CSSProperties = {
  width: '100%', padding: '10px 12px',
  background: '#07080F', border: '1px solid #1A1D38',
  borderRadius: '8px', color: '#D0D8F0', fontSize: '13px',
  outline: 'none', boxSizing: 'border-box',
}
