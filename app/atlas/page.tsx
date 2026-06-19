'use client'

import { useState, useEffect } from 'react'
import Image from 'next/image'

export default function ATLASWaitlistPage() {
  const [email, setEmail]       = useState('')
  const [status, setStatus]     = useState<'idle' | 'loading' | 'success' | 'error'>('idle')
  const [errorMsg, setErrorMsg] = useState('')
  const [mounted, setMounted]   = useState(false)

  useEffect(() => { setMounted(true) }, [])

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    if (!email || status === 'loading') return
    setStatus('loading'); setErrorMsg('')

    try {
      const res = await fetch('/api/atlas/waitlist', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email }),
      })
      const data = await res.json()
      if (data.success) {
        setStatus('success')
      } else {
        setErrorMsg(data.error ?? 'Something went wrong.')
        setStatus('error')
      }
    } catch {
      setErrorMsg('Connection failed. Try again.')
      setStatus('error')
    }
  }

  return (
    <>
      <style>{`
        @font-face {
          font-family: 'SF-Intellivised';
          src: url('/fonts/SF-Intellivised.ttf') format('truetype');
          font-weight: normal;
          font-style: normal;
        }

        * { box-sizing: border-box; margin: 0; padding: 0; }
        body, html { background: #080809; }

        .page {
          min-height: 100vh;
          background: #080809;
          display: flex;
          flex-direction: column;
          align-items: center;
          justify-content: center;
          padding: 40px 20px;
          position: relative;
          overflow: hidden;
        }

        .glow {
          position: fixed;
          top: -200px;
          left: 50%;
          transform: translateX(-50%);
          width: 900px;
          height: 560px;
          background: radial-gradient(ellipse at center, rgba(62,207,178,0.07) 0%, transparent 70%);
          pointer-events: none;
          z-index: 0;
        }

        .content {
          position: relative;
          z-index: 1;
          width: 100%;
          max-width: 460px;
          display: flex;
          flex-direction: column;
          align-items: center;
          opacity: ${mounted ? 1 : 0};
          transform: translateY(${mounted ? '0' : '14px'});
          transition: opacity 0.7s ease, transform 0.7s ease;
        }

        /* ── Video logo lockup ── */
        .logo-lockup {
          display: flex;
          flex-direction: column;
          align-items: center;
          gap: 20px;
          margin-bottom: 44px;
        }

        .logo-video-wrap {
          width: 100px;
          height: 100px;
          border-radius: 24px;
          overflow: hidden;
          background: #0A0A0C;
        }
        .logo-video {
          width: 100%;
          height: 100%;
          object-fit: cover;
          display: block;
        }

        .logo-text {
          font-family: 'SF-Intellivised', -apple-system, sans-serif;
          font-size: 38px;
          font-weight: normal;
          letter-spacing: 18px;
          color: #ffffff;
          text-transform: uppercase;
          padding-left: 4px;
          line-height: 1;
        }

        /* ── Card ── */
        .card {
          width: 100%;
          background: #111113;
          border: 1px solid rgba(255,255,255,0.07);
          border-radius: 20px;
          overflow: hidden;
          box-shadow: 0 40px 100px rgba(0,0,0,0.7), 0 0 0 1px rgba(255,255,255,0.04);
        }

        .card-top-bar {
          height: 2px;
          background: linear-gradient(90deg, #3ECFB2 0%, #5E6AD2 100%);
        }

        .card-body { padding: 36px 36px 38px; }

        /* ── Platform badges ── */
        .platforms {
          display: flex;
          gap: 10px;
          margin-bottom: 30px;
        }
        .platform-badge {
          display: flex;
          align-items: center;
          gap: 9px;
          background: #0C0C0E;
          border: 1px solid rgba(255,255,255,0.08);
          border-radius: 10px;
          padding: 9px 16px;
          transition: border-color 0.2s;
        }
        .platform-badge:hover { border-color: rgba(255,255,255,0.14); }

        .platform-img {
          display: block;
          object-fit: contain;
        }

        .platform-label {
          font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
          font-size: 12px;
          font-weight: 600;
          color: #8A8A96;
          letter-spacing: -0.01em;
        }

        /* ── Text ── */
        .eyebrow {
          font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
          font-size: 10px;
          font-weight: 600;
          letter-spacing: 3px;
          text-transform: uppercase;
          color: #525260;
          margin-bottom: 10px;
        }
        .heading {
          font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
          font-size: 22px;
          font-weight: 700;
          letter-spacing: -0.035em;
          line-height: 1.2;
          color: #ffffff;
          margin-bottom: 10px;
        }
        .subtext {
          font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
          font-size: 13px;
          color: #525260;
          line-height: 1.7;
          letter-spacing: -0.005em;
          margin-bottom: 26px;
        }
        .divider {
          height: 1px;
          background: rgba(255,255,255,0.06);
          margin: 26px 0;
        }

        /* ── Form ── */
        .form { display: flex; flex-direction: column; gap: 10px; }
        .input-row { display: flex; gap: 8px; }

        .email-input {
          flex: 1;
          background: #0C0C0E;
          border: 1px solid rgba(255,255,255,0.08);
          border-radius: 10px;
          padding: 12px 16px;
          font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
          font-size: 13px;
          color: #ffffff;
          outline: none;
          transition: border-color 0.2s;
          min-width: 0;
        }
        .email-input::placeholder { color: #3A3A48; }
        .email-input:focus { border-color: rgba(62,207,178,0.4); }

        .submit-btn {
          background: #3ECFB2;
          border: none;
          border-radius: 10px;
          padding: 12px 20px;
          font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
          font-size: 13px;
          font-weight: 700;
          letter-spacing: -0.01em;
          color: #080809;
          cursor: pointer;
          white-space: nowrap;
          transition: opacity 0.2s, transform 0.15s;
          flex-shrink: 0;
        }
        .submit-btn:hover:not(:disabled) { opacity: 0.88; }
        .submit-btn:active:not(:disabled) { transform: scale(0.97); }
        .submit-btn:disabled { opacity: 0.5; cursor: default; }

        .error-msg {
          font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
          font-size: 12px;
          color: #EF5B5B;
          padding-left: 2px;
        }

        /* ── Success ── */
        .success-state {
          display: flex;
          flex-direction: column;
          align-items: flex-start;
          gap: 6px;
        }
        .success-check {
          width: 36px;
          height: 36px;
          border-radius: 50%;
          background: rgba(62,207,178,0.12);
          border: 1px solid rgba(62,207,178,0.25);
          display: flex;
          align-items: center;
          justify-content: center;
          font-size: 15px;
          margin-bottom: 8px;
        }
        .success-heading {
          font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
          font-size: 15px;
          font-weight: 700;
          color: #ffffff;
          letter-spacing: -0.02em;
        }
        .success-sub {
          font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
          font-size: 13px;
          color: #525260;
          line-height: 1.6;
        }

        /* ── Footer ── */
        .footer {
          margin-top: 28px;
          display: flex;
          flex-direction: column;
          align-items: center;
          gap: 6px;
        }
        .footer-brand {
          font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
          font-size: 10px;
          letter-spacing: 2.5px;
          text-transform: uppercase;
          color: #1E1E28;
        }
        .footer-link {
          font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
          font-size: 11px;
          color: #252530;
          text-decoration: none;
        }
        .footer-link:hover { color: #3A3A48; }

        @media (max-width: 480px) {
          .card-body { padding: 28px 22px 30px; }
          .logo-text { font-size: 30px; letter-spacing: 14px; }
          .logo-video-wrap { width: 80px; height: 80px; }
          .input-row { flex-direction: column; }
          .submit-btn { width: 100%; }
        }
      `}</style>

      <div className="page">
        <div className="glow" />

        <div className="content">

          {/* Logo lockup — video + ATLAS wordmark */}
          <div className="logo-lockup">
            <div className="logo-video-wrap">
              <video
                className="logo-video"
                src="/atlas-logo-visualizer.mp4"
                autoPlay
                loop
                muted
                playsInline
              />
            </div>
            <span className="logo-text">ATLAS</span>
          </div>

          {/* Card */}
          <div className="card">
            <div className="card-top-bar" />
            <div className="card-body">

              {/* Platform badges with real logos */}
              <div className="platforms">
                <div className="platform-badge">
                  <Image
                    src="/apple-logo.png"
                    alt="Apple"
                    width={16}
                    height={16}
                    className="platform-img"
                    style={{ filter: 'brightness(0) invert(0.55)' }}
                  />
                  <span className="platform-label">macOS</span>
                </div>
                <div className="platform-badge">
                  <Image
                    src="/windows-logo.png"
                    alt="Windows"
                    width={16}
                    height={16}
                    className="platform-img"
                    style={{ filter: 'brightness(0) invert(0.55)' }}
                  />
                  <span className="platform-label">Windows</span>
                </div>
              </div>

              <p className="eyebrow">Coming Soon</p>
              <h1 className="heading">Be the first to know.</h1>
              <p className="subtext">
                Subscribe with your email and we'll notify you the moment ATLAS is available.
              </p>

              <div className="divider" />

              {status === 'success' ? (
                <div className="success-state">
                  <div className="success-check">✓</div>
                  <p className="success-heading">You're on the list.</p>
                  <p className="success-sub">
                    Check your inbox — we sent a confirmation to{' '}
                    <strong style={{ color: '#8A8A96', fontWeight: 600 }}>{email}</strong>.
                  </p>
                </div>
              ) : (
                <form className="form" onSubmit={handleSubmit}>
                  <div className="input-row">
                    <input
                      className="email-input"
                      type="email"
                      placeholder="your@email.com"
                      value={email}
                      onChange={e => setEmail(e.target.value)}
                      required
                      disabled={status === 'loading'}
                      autoComplete="email"
                    />
                    <button
                      className="submit-btn"
                      type="submit"
                      disabled={status === 'loading' || !email}
                    >
                      {status === 'loading' ? 'Saving…' : 'Notify me'}
                    </button>
                  </div>
                  {status === 'error' && (
                    <p className="error-msg">{errorMsg}</p>
                  )}
                </form>
              )}

            </div>
          </div>

          {/* Footer */}
          <div className="footer">
            <span className="footer-brand">InterLinked Digital</span>
            <a href="https://www.interlinked.digital" className="footer-link">interlinked.digital</a>
          </div>

        </div>
      </div>
    </>
  )
}
