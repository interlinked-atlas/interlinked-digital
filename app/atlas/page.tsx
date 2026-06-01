'use client'

import { useState } from 'react'
import { createClient } from '@supabase/supabase-js'

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!
)

const PLANS = [
  {
    name: 'Standard',
    price: '$14.99',
    period: '/month',
    color: '#5B8DEF',
    features: [
      '1 device',
      '3 installs per day',
      'Install history',
      'Notifications',
    ],
    excluded: ['Bulk installation', 'Uninstall & Rollback', 'TITAN CORE™', 'Smart Storage'],
    stripeUrl: 'https://buy.stripe.com/7sYcN4b66b0l3VJ1judjO00',
  },
  {
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

type Step = 'account' | 'plan' | 'done'

export default function AtlasSignupPage() {
  const [step, setStep] = useState<Step>('account')
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [confirmPassword, setConfirmPassword] = useState('')
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState('')

  async function handleSignup(e: React.FormEvent) {
    e.preventDefault()
    setError('')

    if (password !== confirmPassword) {
      setError('Passwords do not match.')
      return
    }
    if (password.length < 8) {
      setError('Password must be at least 8 characters.')
      return
    }

    setLoading(true)
    const { error: signUpError } = await supabase.auth.signUp({ email, password })
    setLoading(false)

    if (signUpError) {
      setError(signUpError.message)
      return
    }

    setStep('plan')
  }

  function handleChoosePlan(stripeUrl: string) {
    // Open Stripe checkout in same tab so they come back after payment
    window.location.href = stripeUrl
  }

  return (
    <main style={{
      minHeight: '100vh',
      background: '#0D0F1A',
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'center',
      padding: '24px',
      fontFamily: '-apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif',
    }}>
      <div style={{ width: '100%', maxWidth: '480px' }}>

        {/* Header */}
        <div style={{ textAlign: 'center', marginBottom: '32px' }}>
          <h1 style={{
            color: '#E8ECFF',
            fontSize: '28px',
            fontWeight: '700',
            letterSpacing: '6px',
            margin: '0 0 6px',
          }}>ATLAS</h1>
          <p style={{ color: '#6B7399', fontSize: '13px', margin: 0 }}>
            by InterLinked
          </p>
        </div>

        {/* Step 1: Create account */}
        {step === 'account' && (
          <div style={{
            background: '#111324',
            borderRadius: '12px',
            border: '1px solid #2E3350',
            overflow: 'hidden',
          }}>
            <div style={{
              padding: '16px 20px',
              borderBottom: '1px solid #2E3350',
              background: '#141628',
            }}>
              <h2 style={{ color: '#E8ECFF', fontSize: '14px', fontWeight: '600', margin: 0 }}>
                Create your account
              </h2>
              <p style={{ color: '#6B7399', fontSize: '12px', margin: '4px 0 0' }}>
                Step 1 of 2 — then choose your plan
              </p>
            </div>

            <form onSubmit={handleSignup} style={{ padding: '20px', display: 'flex', flexDirection: 'column', gap: '12px' }}>
              {error && (
                <div style={{
                  background: 'rgba(224,85,85,0.08)',
                  border: '1px solid rgba(224,85,85,0.25)',
                  borderRadius: '8px',
                  padding: '10px 12px',
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

              <button type="submit" disabled={loading} style={primaryButtonStyle}>
                {loading ? 'Creating account…' : 'Continue to Plan Selection →'}
              </button>

              <p style={{ color: '#3A3F60', fontSize: '11px', textAlign: 'center', margin: 0 }}>
                Already have an account?{' '}
                <span style={{ color: '#3ECFB2', cursor: 'pointer' }}
                  onClick={() => window.location.href = 'atlas://'}>
                  Open ATLAS to sign in
                </span>
              </p>
            </form>
          </div>
        )}

        {/* Step 2: Choose plan */}
        {step === 'plan' && (
          <div>
            <div style={{ textAlign: 'center', marginBottom: '20px' }}>
              <div style={{
                display: 'inline-block',
                background: 'rgba(62,207,178,0.1)',
                border: '1px solid rgba(62,207,178,0.3)',
                borderRadius: '8px',
                padding: '8px 16px',
                color: '#3ECFB2',
                fontSize: '12px',
                marginBottom: '12px',
              }}>
                ✓ Account created for {email}
              </div>
              <h2 style={{ color: '#E8ECFF', fontSize: '16px', fontWeight: '600', margin: '0 0 4px' }}>
                Choose your plan
              </h2>
              <p style={{ color: '#6B7399', fontSize: '12px', margin: 0 }}>
                Step 2 of 2 — you'll be taken to secure checkout
              </p>
            </div>

            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '12px' }}>
              {PLANS.map(plan => (
                <div key={plan.name} style={{
                  background: '#111324',
                  borderRadius: '10px',
                  border: `1px solid ${plan.recommended ? plan.color + '50' : '#2E3350'}`,
                  overflow: 'hidden',
                  display: 'flex',
                  flexDirection: 'column',
                }}>
                  <div style={{
                    padding: '12px',
                    background: plan.color + '12',
                    borderBottom: '1px solid #2E3350',
                  }}>
                    <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                      <span style={{
                        color: plan.color,
                        fontSize: '11px',
                        fontWeight: '800',
                        letterSpacing: '1.2px',
                      }}>{plan.name.toUpperCase()}</span>
                      {plan.recommended && (
                        <span style={{
                          background: plan.color + '20',
                          border: `1px solid ${plan.color}50`,
                          borderRadius: '4px',
                          padding: '2px 6px',
                          color: plan.color,
                          fontSize: '8px',
                          fontWeight: '800',
                          letterSpacing: '0.8px',
                        }}>BEST VALUE</span>
                      )}
                    </div>
                    <div style={{ marginTop: '4px' }}>
                      <span style={{ color: '#E8ECFF', fontSize: '20px', fontWeight: '700' }}>{plan.price}</span>
                      <span style={{ color: '#6B7399', fontSize: '11px' }}>{plan.period}</span>
                    </div>
                  </div>

                  <div style={{ padding: '12px', flex: 1, display: 'flex', flexDirection: 'column', gap: '6px' }}>
                    {plan.features.map(f => (
                      <div key={f} style={{ display: 'flex', gap: '6px', alignItems: 'flex-start' }}>
                        <span style={{ color: plan.color, fontSize: '10px', fontWeight: '700', marginTop: '2px' }}>✓</span>
                        <span style={{ color: '#C8D0E8', fontSize: '11px' }}>{f}</span>
                      </div>
                    ))}
                    {plan.excluded.map(f => (
                      <div key={f} style={{ display: 'flex', gap: '6px', alignItems: 'flex-start' }}>
                        <span style={{ color: '#3A3F60', fontSize: '10px', fontWeight: '700', marginTop: '2px' }}>✕</span>
                        <span style={{ color: '#3A3F60', fontSize: '11px' }}>{f}</span>
                      </div>
                    ))}
                  </div>

                  <div style={{ padding: '0 12px 12px' }}>
                    <button
                      onClick={() => handleChoosePlan(plan.stripeUrl)}
                      style={{
                        width: '100%',
                        padding: '9px',
                        borderRadius: '8px',
                        border: plan.recommended ? 'none' : `1px solid ${plan.color}60`,
                        background: plan.recommended
                          ? `linear-gradient(135deg, ${plan.color}, ${plan.color}cc)`
                          : plan.color + '15',
                        color: plan.recommended ? '#0D0F1A' : plan.color,
                        fontSize: '11px',
                        fontWeight: '700',
                        cursor: 'pointer',
                        letterSpacing: '0.3px',
                      }}
                    >
                      Subscribe — {plan.name}
                    </button>
                  </div>
                </div>
              ))}
            </div>

            <p style={{ color: '#3A3F60', fontSize: '11px', textAlign: 'center', marginTop: '16px' }}>
              Secure payment via Stripe · Cancel anytime
            </p>
          </div>
        )}

        {/* Footer */}
        <p style={{
          color: '#3A3F60',
          fontSize: '10px',
          textAlign: 'center',
          marginTop: '24px',
        }}>
          InterLinked© · All rights reserved
        </p>
      </div>
    </main>
  )
}

const inputStyle: React.CSSProperties = {
  width: '100%',
  padding: '10px 12px',
  background: '#0D0F1A',
  border: '1px solid #2E3350',
  borderRadius: '8px',
  color: '#D0D8F0',
  fontSize: '13px',
  outline: 'none',
  boxSizing: 'border-box',
}

const primaryButtonStyle: React.CSSProperties = {
  width: '100%',
  padding: '11px',
  background: 'linear-gradient(135deg, #3ECFB2, #2ABEAA)',
  border: 'none',
  borderRadius: '9px',
  color: 'white',
  fontSize: '13px',
  fontWeight: '600',
  cursor: 'pointer',
  marginTop: '4px',
}
