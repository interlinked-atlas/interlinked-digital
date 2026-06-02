'use client'

import { useState } from 'react'
import { createClient } from '@/lib/supabase/client'
import { useRouter } from 'next/navigation'

export default function LoginPage() {
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [error, setError] = useState('')
  const [loading, setLoading] = useState(false)
  const router = useRouter()
  const supabase = createClient()

  async function handleLogin(e: React.FormEvent) {
    e.preventDefault()
    setLoading(true)
    setError('')
    const { error: authError } = await supabase.auth.signInWithPassword({ email, password })
    setLoading(false)
    if (authError) { setError(authError.message); return }
    router.push('/atlas/account')
    router.refresh()
  }

  return (
    <>
      <style>{`
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body { background: #080809; }
        input { transition: border-color 0.15s, box-shadow 0.15s; }
        input::placeholder { color: rgba(255,255,255,0.20); }
        input:focus { border-color: rgba(62,207,178,0.5) !important; box-shadow: 0 0 0 3px rgba(62,207,178,0.08) !important; outline: none; }
        .login-btn { transition: opacity 0.15s, transform 0.12s cubic-bezier(0.16,1,0.3,1); }
        .login-btn:hover:not(:disabled) { opacity: 0.88; transform: translateY(-1px); }
        .login-btn:active:not(:disabled) { transform: scale(0.985); }
        .login-btn:disabled { opacity: 0.4; cursor: not-allowed; }
        a { text-decoration: none; }
      `}</style>

      <main style={{
        minHeight: '100vh', background: '#080809', display: 'flex',
        alignItems: 'center', justifyContent: 'center',
        padding: '32px 20px',
        fontFamily: '"Inter", -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif',
        WebkitFontSmoothing: 'antialiased',
      }}>
        <div style={{ width: '100%', maxWidth: '400px' }}>

          {/* ATLAS heading */}
          <div style={{ textAlign: 'center', marginBottom: '40px' }}>
            <a href="/atlas" style={{ display: 'inline-block' }}>
              <h1 style={{
                fontFamily: "'SF-Intellivised', -apple-system, sans-serif",
                fontSize: '52px',
                fontWeight: 'normal',
                letterSpacing: '14px',
                textIndent: '14px',
                lineHeight: 1,
                marginBottom: '10px',
                background: 'linear-gradient(160deg, #FFFFFF 30%, rgba(255,255,255,0.55) 100%)',
                WebkitBackgroundClip: 'text',
                WebkitTextFillColor: 'transparent',
                backgroundClip: 'text',
              }}>ATLAS</h1>
            </a>
            <p style={{
              color: '#44444E', fontSize: '11px',
              letterSpacing: '3px', textTransform: 'uppercase',
            }}>
              by InterLinked©
            </p>
          </div>

          {/* Login card */}
          <div style={{
            background: '#0E0E10',
            borderRadius: '16px',
            border: '1px solid rgba(255,255,255,0.07)',
            overflow: 'hidden',
          }}>
            <div style={{
              padding: '14px 20px',
              borderBottom: '1px solid rgba(255,255,255,0.06)',
            }}>
              <h2 style={{
                color: '#FFFFFF', fontSize: '14px', fontWeight: 600,
                letterSpacing: '-0.01em', marginBottom: '4px',
              }}>
                Sign in to your account
              </h2>
              <p style={{ color: '#525260', fontSize: '12px' }}>
                Access your subscription, devices, and downloads
              </p>
            </div>

            <form onSubmit={handleLogin} style={{ padding: '20px', display: 'flex', flexDirection: 'column', gap: '10px' }}>
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
              <input type="password" placeholder="Password" value={password}
                onChange={e => setPassword(e.target.value)} required style={inputStyle} />

              <button type="submit" disabled={loading} className="login-btn" style={{
                width: '100%', padding: '12px', border: 'none', borderRadius: '10px',
                background: 'linear-gradient(135deg, #3ECFB2, #2ABEAA)',
                color: '#080809', fontSize: '13px', fontWeight: 700,
                cursor: loading ? 'not-allowed' : 'pointer',
                marginTop: '4px', letterSpacing: '-0.01em',
                boxShadow: '0 0 24px rgba(62,207,178,0.20)',
              }}>
                {loading ? 'Signing in…' : 'Sign in →'}
              </button>

              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginTop: '2px' }}>
                <a href="/auth/forgot-password" style={{
                  color: '#44444E', fontSize: '11px', transition: 'color 0.12s',
                }}
                  onMouseEnter={e => (e.currentTarget.style.color = '#8A8A96')}
                  onMouseLeave={e => (e.currentTarget.style.color = '#44444E')}
                >
                  Forgot password?
                </a>
                <p style={{ color: '#44444E', fontSize: '11px' }}>
                  New to ATLAS?{" "}
                  <a href="/atlas" style={{ color: '#3ECFB2', fontWeight: 600 }}>
                    Get started →
                  </a>
                </p>
              </div>
            </form>
          </div>

          <p style={{ color: 'rgba(255,255,255,0.12)', fontSize: '10px', textAlign: 'center', marginTop: '28px', letterSpacing: '0.04em' }}>
            InterLinked© · All rights reserved
          </p>
        </div>
      </main>
    </>
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
  letterSpacing: '-0.005em',
}
