'use client'

import { useState, useEffect } from 'react'
import { createClient } from '@/lib/supabase/client'
import { useRouter } from 'next/navigation'

function EyeIcon() {
  return (
    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"/>
      <circle cx="12" cy="12" r="3"/>
    </svg>
  )
}

function EyeOffIcon() {
  return (
    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <path d="M17.94 17.94A10.07 10.07 0 0112 20c-7 0-11-8-11-8a18.45 18.45 0 015.06-5.94M9.9 4.24A9.12 9.12 0 0112 4c7 0 11 8 11 8a18.5 18.5 0 01-2.16 3.19m-6.72-1.07a3 3 0 11-4.24-4.24"/>
      <line x1="1" y1="1" x2="23" y2="23"/>
    </svg>
  )
}

export default function LoginPage() {
  const [mounted, setMounted] = useState(false)
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [showPassword, setShowPassword] = useState(false)
  const [error, setError] = useState('')
  const [loading, setLoading] = useState(false)
  const router = useRouter()
  const supabase = createClient()

  useEffect(() => { const t = setTimeout(() => setMounted(true), 40); return () => clearTimeout(t) }, [])

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
        .eye-btn { background: none; border: none; cursor: pointer; color: rgba(255,255,255,0.25); padding: 0; display: flex; align-items: center; transition: color 0.15s; }
        .eye-btn:hover { color: rgba(255,255,255,0.55); }
        a { text-decoration: none; }
      `}</style>

      <main style={{
        minHeight: '100vh', background: '#080809', display: 'flex',
        alignItems: 'center', justifyContent: 'center',
        padding: '32px 20px',
        fontFamily: '"Inter", -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif',
        WebkitFontSmoothing: 'antialiased',
      }}>
        <div style={{
          width: '100%', maxWidth: '400px',
          opacity: mounted ? 1 : 0,
          transform: mounted ? 'translateY(0)' : 'translateY(20px)',
          transition: 'opacity 0.65s cubic-bezier(0.16,1,0.3,1), transform 0.65s cubic-bezier(0.16,1,0.3,1)',
        }}>

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

              <div style={{ position: 'relative' }}>
                <input
                  type={showPassword ? 'text' : 'password'}
                  placeholder="Password"
                  value={password}
                  onChange={e => setPassword(e.target.value)}
                  required
                  style={{ ...inputStyle, paddingRight: '44px' }}
                />
                <button
                  type="button"
                  className="eye-btn"
                  onClick={() => setShowPassword(v => !v)}
                  style={{
                    position: 'absolute', right: '14px', top: '50%',
                    transform: 'translateY(-50%)',
                    background: 'none', border: 'none', cursor: 'pointer',
                    color: showPassword ? 'rgba(62,207,178,0.7)' : 'rgba(255,255,255,0.25)',
                    display: 'flex', alignItems: 'center',
                    transition: 'color 0.15s',
                  }}
                  tabIndex={-1}
                >
                  {showPassword ? <EyeOffIcon /> : <EyeIcon />}
                </button>
              </div>

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
