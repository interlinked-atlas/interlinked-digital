'use client'

import { useState, useEffect, useRef } from 'react'

export default function ATLASWaitlistPage() {
  const [email, setEmail]       = useState('')
  const [status, setStatus]     = useState<'idle' | 'loading' | 'success' | 'error'>('idle')
  const [errorMsg, setErrorMsg] = useState('')
  const [mounted, setMounted]   = useState(false)
  const [count, setCount]       = useState<number | null>(null)
  const [coinAnim, setCoinAnim] = useState(false)
  const prevCount               = useRef<number | null>(null)

  useEffect(() => { setMounted(true) }, [])

  useEffect(() => {
    async function fetchCount() {
      try {
        const res = await fetch('/api/atlas/subscriber-count')
        const data = await res.json()
        if (prevCount.current !== null && data.count > prevCount.current) {
          setCoinAnim(true)
          setTimeout(() => setCoinAnim(false), 1200)
        }
        prevCount.current = data.count
        setCount(data.count)
      } catch {}
    }
    fetchCount()
    const interval = setInterval(fetchCount, 30000)
    return () => clearInterval(interval)
  }, [])

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
        setCount(c => c !== null ? c + 1 : c)
        setCoinAnim(true)
        setTimeout(() => setCoinAnim(false), 1200)
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
          padding: 20px 20px;
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
          gap: 12px;
          margin-bottom: 24px;
        }

        .logo-video-wrap {
          width: 72px;
          height: 72px;
          border-radius: 18px;
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
          font-size: 30px;
          font-weight: normal;
          letter-spacing: 14px;
          color: #ffffff;
          text-transform: uppercase;
          padding-left: 4px;
          line-height: 1;
        }
        .logo-tagline {
          font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
          font-size: 11px;
          font-weight: 500;
          color: #525260;
          letter-spacing: 0.01em;
          text-align: center;
          margin-top: 4px;
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

        .card-body { padding: 24px 28px 26px; }

        /* ── Platform badges ── */
        .platforms {
          display: flex;
          gap: 10px;
          margin-bottom: 20px;
        }
        .platform-badge {
          display: flex;
          align-items: center;
          gap: 9px;
          background: #0C0C0E;
          border: 1px solid rgba(255,255,255,0.08);
          border-radius: 10px;
          padding: 7px 14px;
          transition: border-color 0.2s;
        }
        .platform-badge:hover { border-color: rgba(255,255,255,0.14); }

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
          line-height: 1.6;
          letter-spacing: -0.005em;
          margin-bottom: 18px;
        }
        .divider {
          height: 1px;
          background: rgba(255,255,255,0.06);
          margin: 18px 0;
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

        .login-btn {
          width: 100%;
          background: transparent;
          border: 1px solid rgba(255,255,255,0.08);
          border-radius: 10px;
          padding: 11px 20px;
          font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
          font-size: 13px;
          font-weight: 500;
          color: #8A8A96;
          cursor: pointer;
          text-align: center;
          text-decoration: none;
          display: block;
          transition: border-color 0.2s, color 0.2s;
          letter-spacing: -0.01em;
        }
        .login-btn:hover { border-color: rgba(255,255,255,0.16); color: #ffffff; }

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

        /* ── Subscriber counter ── */
        .counter-wrap {
          width: 100%;
          margin-top: 14px;
          display: flex;
          align-items: center;
          justify-content: center;
          gap: 10px;
        }
        .counter-coin {
          width: 28px;
          height: 28px;
          border-radius: 50%;
          background: radial-gradient(circle at 35% 35%, #5EFFD8, #3ECFB2 60%, #1a8a72);
          display: flex;
          align-items: center;
          justify-content: center;
          font-size: 13px;
          box-shadow: 0 0 12px rgba(62,207,178,0.5);
          flex-shrink: 0;
          transition: transform 0.15s ease;
        }
        .counter-coin.pop {
          animation: coinPop 1.2s ease forwards;
        }
        @keyframes coinPop {
          0%   { transform: scale(1) translateY(0); box-shadow: 0 0 12px rgba(62,207,178,0.5); }
          20%  { transform: scale(1.4) translateY(-6px); box-shadow: 0 0 28px rgba(62,207,178,0.9); }
          50%  { transform: scale(1.1) translateY(-2px); box-shadow: 0 0 20px rgba(62,207,178,0.7); }
          100% { transform: scale(1) translateY(0); box-shadow: 0 0 12px rgba(62,207,178,0.5); }
        }
        .counter-text {
          font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
          font-size: 13px;
          color: #525260;
          letter-spacing: -0.01em;
        }
        .counter-num {
          font-weight: 700;
          color: #3ECFB2;
          font-variant-numeric: tabular-nums;
        }

        /* ── Demo section ── */
        .demo-section {
          width: 100%;
          max-width: 760px;
          margin-top: 64px;
          display: flex;
          flex-direction: column;
          align-items: center;
          gap: 20px;
        }
        .demo-eyebrow {
          font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
          font-size: 10px;
          font-weight: 700;
          letter-spacing: 3px;
          text-transform: uppercase;
          color: #3ECFB2;
          text-align: center;
        }
        .demo-heading {
          font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
          font-size: 26px;
          font-weight: 700;
          letter-spacing: -0.035em;
          color: #ffffff;
          text-align: center;
          line-height: 1.2;
          margin-top: 4px;
        }
        .demo-sub {
          font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
          font-size: 13px;
          color: #525260;
          text-align: center;
          line-height: 1.6;
          max-width: 380px;
        }
        .demo-video-wrap {
          width: 100%;
          border-radius: 16px;
          overflow: hidden;
          border: 1px solid rgba(255,255,255,0.08);
          box-shadow: 0 30px 80px rgba(0,0,0,0.7), 0 0 0 1px rgba(255,255,255,0.04);
          background: #000;
        }
        .demo-iframe {
          width: 100%;
          aspect-ratio: 16/9;
          border: none;
          display: block;
        }
        .demo-divider {
          width: 100%;
          height: 1px;
          background: rgba(255,255,255,0.05);
        }

        /* ── Footer ── */
        .footer {
          margin-top: 16px;
          display: flex;
          flex-direction: column;
          align-items: center;
          gap: 4px;
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
          .card-body { padding: 20px 18px 22px; }
          .logo-text { font-size: 24px; letter-spacing: 10px; }
          .logo-video-wrap { width: 60px; height: 60px; }
          .input-row { flex-direction: column; }
          .submit-btn { width: 100%; }
        }
      `}</style>

      <div className="page">
        <div className="glow" />

        <div className="content">

          {/* Logo lockup */}
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
            <p className="logo-tagline">The World's First Autonomous Installation App.</p>
          </div>

          {/* Card */}
          <div className="card">
            <div className="card-top-bar" />
            <div className="card-body">

              {/* Platform badges */}
              <div className="platforms">
                <div className="platform-badge">
                  <svg width="16" height="16" viewBox="0 0 24 24" fill="#8A8A96" xmlns="http://www.w3.org/2000/svg">
                    <path d="M18.71 19.5c-.83 1.24-1.71 2.45-3.05 2.47-1.34.03-1.77-.79-3.29-.79-1.53 0-2 .77-3.27.82-1.31.05-2.3-1.32-3.14-2.53C4.25 17 2.94 12.45 4.7 9.39c.87-1.52 2.43-2.48 4.12-2.51 1.28-.02 2.5.87 3.29.87.78 0 2.26-1.07 3.8-.91.65.03 2.47.26 3.64 1.98-.09.06-2.17 1.28-2.15 3.81.03 3.02 2.65 4.03 2.68 4.04-.03.07-.42 1.44-1.37 2.83M13 3.5c.73-.83 1.94-1.46 2.94-1.5.13 1.17-.34 2.35-1.04 3.19-.69.85-1.83 1.51-2.95 1.42-.15-1.15.41-2.35 1.05-3.11z"/>
                  </svg>
                  <span className="platform-label">macOS</span>
                </div>
                <div className="platform-badge" style={{ opacity: 0.45 }}>
                  <svg width="16" height="16" viewBox="0 0 22 22" fill="none" xmlns="http://www.w3.org/2000/svg">
                    <rect x="0" y="0" width="10" height="10" rx="1" fill="#8A8A96"/>
                    <rect x="12" y="0" width="10" height="10" rx="1" fill="#8A8A96"/>
                    <rect x="0" y="12" width="10" height="10" rx="1" fill="#8A8A96"/>
                    <rect x="12" y="12" width="10" height="10" rx="1" fill="#8A8A96"/>
                  </svg>
                  <span className="platform-label">Windows</span>
                  <span style={{ fontSize: 9, fontWeight: 700, letterSpacing: '0.08em', color: '#525260', background: 'rgba(255,255,255,0.06)', border: '1px solid rgba(255,255,255,0.08)', borderRadius: 4, padding: '1px 5px', marginLeft: 4 }}>SOON</span>
                </div>
              </div>

              <p className="eyebrow">Coming Soon</p>
              <h1 className="heading">Be the first to know.</h1>
              <p className="subtext">
                Subscribe with your email and we'll notify you the moment ATLAS is available.
              </p>
              <p style={{ fontFamily: '-apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif', fontSize: 12, fontWeight: 600, color: '#8A8A96', marginBottom: 14, marginTop: -4 }}>
                Stay Tuned for Subscription Plans &amp; Pricing.
              </p>

              <div className="divider" />

              {status === 'success' ? (
                <div className="success-state">
                  <div className="success-check">✓</div>
                  <p className="success-heading">You're on the list.</p>
                  <p className="success-sub">
                    We sent a confirmation to{' '}
                    <strong style={{ color: '#8A8A96', fontWeight: 600 }}>{email}</strong>.
                  </p>
                  <p className="success-sub" style={{ marginTop: 8, color: '#3A3A48', fontSize: 12 }}>
                    Don't see it? Check your <strong style={{ color: '#525260' }}>spam or junk folder</strong> — and mark it as "Not Spam" to make sure you get the launch email.
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

          {/* Live subscriber counter */}
          {count !== null && (
            <div className="counter-wrap">
              <div className={`counter-coin${coinAnim ? ' pop' : ''}`}>✦</div>
              <span className="counter-text">
                <span className="counter-num">{count.toLocaleString()}</span> people on the waitlist
              </span>
            </div>
          )}

          {/* Footer */}
          <div className="footer">
            <span className="footer-brand">InterLinked Digital</span>
            <a href="https://www.interlinked.digital" className="footer-link">interlinked.digital</a>
          </div>

        </div>

        {/* Demo section */}
        <div className="demo-section">
          <p className="demo-eyebrow">Watch the Demo Below</p>
          <h2 className="demo-heading">See ATLAS in Action</h2>
          <p className="demo-sub">Watch how ATLAS autonomously installs plugins and software — drop a file, ATLAS handles the rest.</p>
          <p style={{ fontFamily: '-apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif', fontSize: 12, fontWeight: 600, color: '#3ECFB2', opacity: 0.7, marginTop: -8 }}>Stay Tuned for Subscription Plans &amp; Pricing.</p>
          <div className="demo-divider" />
          <div className="demo-video-wrap">
            <iframe
              className="demo-iframe"
              src="https://www.youtube.com/embed/OHbz5y4kHeg?rel=0&modestbranding=1&color=white"
              title="ATLAS Demo — The World's First Autonomous Installation App"
              allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture"
              allowFullScreen
            />
          </div>
        </div>

      </div>
    </>
  )
}
