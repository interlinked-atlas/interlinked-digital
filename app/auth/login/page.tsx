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
        a { text-decoration: none; }
      `}</style>

      <main style={{
        minHeight: '100vh', background: '#07080F', display: 'flex',
        alignItems: 'center', justifyContent: 'center',
        padding: '32px 20px',
        fontFamily: '-apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif',
      }}>
        <div style={{ width: '100%', maxWidth: '400px' }}>

          {/* ATLAS heading */}
          <div style={{ textAlign: 'center', marginBottom: '40px' }}>
            <a href="/atlas" style={{ display: 'inline-block' }}>
              <h1 style={{
                color: '#E8ECFF', fontSize: '48px', fontWeight: 'normal',
                letterSpacing: '12px', fontFamily: 'Bezmiar, -apple-system, sans-serif',
                lineHeight: 1, marginBottom: '8px', textIndent: '12px',
              }}>ATLAS</h1>
            </a>
            <p style={{ color: '#303460', fontSize: '11px', letterSpacing: '3px', textTransform: 'uppercase' }}>
              by InterLinked
            </p>
          </div>

          {/* Login card */}
          <div style={{
            background: '#0C0E1C', borderRadius: '12px',
            border: '1px solid #1A1D38', overflow: 'hidden',
          }}>
            <div style={{
              padding: '14px 18px', borderBottom: '1px solid #1A1D38',
              background: '#0F1128',
            }}>
              <h2 style={{ color: '#C8D0E8', fontSize: '14px', fontWeight: '600' }}>
                Sign in to your account
              </h2>
              <p style={{ color: '#2A2E55', fontSize: '11px', marginTop: '3px' }}>
                Access your subscription, devices, and downloads
              </p>
            </div>

            <form onSubmit={handleLogin} style={{ padding: '18px', display: 'flex', flexDirection: 'column', gap: '10px' }}>
              {error && (
                <div style={{
                  background: 'rgba(224,85,85,0.07)', border: '1px solid rgba(224,85,85,0.22)',
                  borderRadius: '8px', padding: '9px 12px', color: '#E05555', fontSize: '12px',
                }}>{error}</div>
              )}

              <input type="email" placeholder="Email address" value={email}
                onChange={e => setEmail(e.target.value)} required style={inputStyle} />
              <input type="password" placeholder="Password" value={password}
                onChange={e => setPassword(e.target.value)} required style={inputStyle} />

              <button type="submit" disabled={loading} style={{
                width: '100%', padding: '11px', border: 'none', borderRadius: '9px',
                background: 'linear-gradient(135deg, #3ECFB2, #2ABEAA)',
                color: '#07080F', fontSize: '13px', fontWeight: '600',
                cursor: 'pointer', marginTop: '2px',
              }}>
                {loading ? 'Signing in…' : 'Sign In →'}
              </button>

              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginTop: '2px' }}>
                <a href="/auth/forgot-password" style={{ color: '#3A4070', fontSize: '11px' }}>
                  Forgot password?
                </a>
                <p style={{ color: '#202340', fontSize: '11px' }}>
                  New to ATLAS?{' '}
                  <a href="/atlas" style={{ color: '#3ECFB2', fontWeight: '600' }}>
                    Get Started →
                  </a>
                </p>
              </div>
            </form>
          </div>

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
