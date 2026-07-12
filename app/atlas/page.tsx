'use client'

import { useState, useEffect, useRef } from 'react'

export default function ATLASWaitlistPage() {
  const [email, setEmail]           = useState('')
  const [status, setStatus]         = useState<'idle' | 'loading' | 'verifying' | 'confirming' | 'success' | 'error'>('idle')
  const [errorMsg, setErrorMsg]     = useState('')
  const [codeInput, setCodeInput]   = useState('')
  const [verifyToken, setVerifyToken] = useState('')
  const [verifyTs, setVerifyTs]     = useState(0)
  const [shareEmail, setShareEmail] = useState('')
  const [shareStatus, setShareStatus] = useState<'idle' | 'sending' | 'sent' | 'error'>('idle')
  const [shareError, setShareError] = useState('')
  const [mounted, setMounted]       = useState(false)
  const [count, setCount]           = useState<number | null>(null)
  const [coinAnim, setCoinAnim]     = useState(false)
  const [demoUnlocked, setDemo]     = useState(false)
  const [unlocking, setUnlocking]   = useState(false)
  const prevCount                   = useRef<number | null>(null)
  const demoRef                     = useRef<HTMLDivElement>(null)

  useEffect(() => {
    setMounted(true)
    // Auto-unlock if coming from email link
    if (typeof window !== 'undefined' && window.location.search.includes('demo=1')) {
      setDemo(true)
    }
  }, [])

  useEffect(() => {
    async function fetchCount() {
      try {
        const res = await fetch('/api/atlas/subscriber-count')
        const data = await res.json()
        if (prevCount.current !== null && data.count > prevCount.current) {
          setCoinAnim(true)
          setTimeout(() => setCoinAnim(false), 900)
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
      const res = await fetch('/api/atlas/send-code', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email }),
      })
      const data = await res.json()
      if (res.ok) {
        setVerifyToken(data.token)
        setVerifyTs(data.ts)
        setStatus('verifying')
      } else {
        setErrorMsg(data.error ?? 'Something went wrong.')
        setStatus('error')
      }
    } catch {
      setErrorMsg('Connection failed. Try again.')
      setStatus('error')
    }
  }

  async function handleVerify(e: React.FormEvent) {
    e.preventDefault()
    if (!codeInput || status === 'confirming') return
    setStatus('confirming'); setErrorMsg('')

    try {
      const res = await fetch('/api/atlas/verify-code', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email, code: codeInput, token: verifyToken, ts: verifyTs }),
      })
      const data = await res.json()
      if (data.success) {
        setStatus('success')
        setCount(c => c !== null ? c + 1 : c)
        setCoinAnim(true)
        setTimeout(() => setCoinAnim(false), 900)
        setUnlocking(true)
        setTimeout(() => {
          setUnlocking(false)
          setDemo(true)
          setTimeout(() => {
            demoRef.current?.scrollIntoView({ behavior: 'smooth', block: 'start' })
          }, 100)
        }, 1400)
      } else {
        setErrorMsg(data.error ?? 'Invalid code.')
        setStatus('verifying')
      }
    } catch {
      setErrorMsg('Connection failed. Try again.')
      setStatus('verifying')
    }
  }

  async function handleShare(e: React.FormEvent) {
    e.preventDefault()
    if (!shareEmail || shareStatus === 'sending') return
    setShareStatus('sending'); setShareError('')
    try {
      const res = await fetch('/api/atlas/share', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ friendEmail: shareEmail }),
      })
      const data = await res.json()
      if (data.success) {
        setShareStatus('sent')
        setShareEmail('')
      } else {
        setShareError(data.error ?? 'Could not send invite.')
        setShareStatus('error')
      }
    } catch {
      setShareError('Connection failed. Try again.')
      setShareStatus('error')
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

        /* ── Subscriber counter banner ── */
        .counter-banner {
          width: 100%;
          margin-top: 12px;
          background: rgba(62,207,178,0.06);
          border: 1px solid rgba(62,207,178,0.15);
          border-radius: 12px;
          padding: 12px 20px;
          display: flex;
          align-items: center;
          justify-content: center;
          gap: 12px;
        }
        .counter-coin {
          width: 26px;
          height: 26px;
          border-radius: 50%;
          background: radial-gradient(circle at 35% 35%, #5EFFD8, #3ECFB2 60%, #1a8a72);
          display: flex;
          align-items: center;
          justify-content: center;
          font-size: 11px;
          box-shadow: 0 0 10px rgba(62,207,178,0.5);
          flex-shrink: 0;
        }
        .counter-coin.pop {
          animation: coinPop 1.2s ease forwards;
        }
        @keyframes coinPop {
          0%   { transform: scale(1) translateY(0); box-shadow: 0 0 10px rgba(62,207,178,0.5); }
          20%  { transform: scale(1.5) translateY(-8px); box-shadow: 0 0 30px rgba(62,207,178,1); }
          50%  { transform: scale(1.15) translateY(-3px); box-shadow: 0 0 18px rgba(62,207,178,0.7); }
          100% { transform: scale(1) translateY(0); box-shadow: 0 0 10px rgba(62,207,178,0.5); }
        }
        .counter-label {
          font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
          font-size: 12px;
          color: #525260;
          letter-spacing: -0.01em;
        }
        .counter-num {
          font-weight: 700;
          color: #3ECFB2;
          font-variant-numeric: tabular-nums;
          font-size: 13px;
        }
        .counter-dot {
          width: 5px;
          height: 5px;
          border-radius: 50%;
          background: #3ECFB2;
          opacity: 0.5;
          animation: pulse 2s ease-in-out infinite;
          flex-shrink: 0;
        }
        @keyframes pulse {
          0%, 100% { opacity: 0.5; transform: scale(1); }
          50% { opacity: 1; transform: scale(1.3); }
        }

        /* ── Locked demo teaser ── */
        .demo-locked {
          width: 100%;
          margin-top: 20px;
          position: relative;
          border-radius: 14px;
          overflow: hidden;
          border: 1px solid rgba(255,255,255,0.07);
          cursor: default;
        }
        .demo-locked-thumb {
          width: 100%;
          aspect-ratio: 16/9;
          background: url('https://img.youtube.com/vi/OHbz5y4kHeg/maxresdefault.jpg') center/cover no-repeat;
          filter: blur(6px) brightness(0.35);
          transform: scale(1.05);
        }
        .demo-locked-overlay {
          position: absolute;
          inset: 0;
          display: flex;
          flex-direction: column;
          align-items: center;
          justify-content: center;
          gap: 10px;
        }
        .demo-lock-icon {
          font-size: 28px;
          opacity: 0.7;
        }
        .demo-lock-text {
          font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
          font-size: 13px;
          font-weight: 600;
          color: rgba(255,255,255,0.5);
          letter-spacing: -0.01em;
          text-align: center;
        }
        /* ── Unlocking flash ── */
        .demo-unlocking {
          animation: unlockFlash 1.4s ease forwards;
        }
        @keyframes unlockFlash {
          0%   { opacity: 1; }
          40%  { opacity: 0.3; box-shadow: 0 0 60px rgba(62,207,178,0.6); }
          100% { opacity: 1; }
        }
        /* ── Demo section ── */
        .demo-section {
          width: 100%;
          max-width: 760px;
          margin-top: 0;
          display: flex;
          flex-direction: column;
          align-items: center;
          gap: 20px;
          animation: fadeUp 0.6s ease forwards;
        }
        @keyframes fadeUp {
          from { opacity: 0; transform: translateY(20px); }
          to   { opacity: 1; transform: translateY(0); }
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
          border: 1px solid rgba(62,207,178,0.2);
          box-shadow: 0 0 60px rgba(62,207,178,0.12), 0 30px 80px rgba(0,0,0,0.7);
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
        .demo-back-btn {
          font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
          font-size: 12px;
          font-weight: 600;
          color: #525260;
          background: transparent;
          border: 1px solid rgba(255,255,255,0.08);
          border-radius: 8px;
          padding: 8px 16px;
          cursor: pointer;
          text-decoration: none;
          display: inline-flex;
          align-items: center;
          gap: 6px;
          transition: color 0.2s, border-color 0.2s;
          align-self: flex-start;
        }
        .demo-back-btn:hover { color: #fff; border-color: rgba(255,255,255,0.2); }

        /* ── Code verification ── */
        .verify-state {
          display: flex;
          flex-direction: column;
          align-items: flex-start;
          gap: 6px;
        }
        .verify-icon {
          width: 36px;
          height: 36px;
          border-radius: 50%;
          background: rgba(62,207,178,0.1);
          border: 1px solid rgba(62,207,178,0.2);
          display: flex;
          align-items: center;
          justify-content: center;
          font-size: 16px;
          margin-bottom: 8px;
        }
        .verify-heading {
          font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
          font-size: 15px;
          font-weight: 700;
          color: #ffffff;
          letter-spacing: -0.02em;
        }
        .verify-sub {
          font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
          font-size: 13px;
          color: #525260;
          line-height: 1.6;
          margin-bottom: 16px;
        }
        .code-row {
          display: flex;
          gap: 8px;
          width: 100%;
        }
        .code-input {
          flex: 1;
          background: #0C0C0E;
          border: 1px solid rgba(62,207,178,0.3);
          border-radius: 10px;
          padding: 12px 16px;
          font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
          font-size: 18px;
          font-weight: 700;
          letter-spacing: 0.18em;
          color: #ffffff;
          outline: none;
          transition: border-color 0.2s;
          min-width: 0;
          text-align: center;
        }
        .code-input::placeholder { color: #2A2A38; letter-spacing: 0.1em; font-weight: 400; font-size: 14px; }
        .code-input:focus { border-color: rgba(62,207,178,0.6); }
        .resend-btn {
          background: transparent;
          border: none;
          padding: 0;
          font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
          font-size: 12px;
          color: #525260;
          cursor: pointer;
          text-decoration: underline;
          text-underline-offset: 2px;
          margin-top: 8px;
        }
        .resend-btn:hover { color: #8A8A96; }

        /* ── Share section ── */
        .share-section {
          width: 100%;
          background: #111113;
          border: 1px solid rgba(255,255,255,0.07);
          border-radius: 16px;
          padding: 22px 24px;
          display: flex;
          flex-direction: column;
          gap: 12px;
        }
        .share-heading {
          font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
          font-size: 13px;
          font-weight: 700;
          color: #ffffff;
          letter-spacing: -0.02em;
        }
        .share-sub {
          font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
          font-size: 12px;
          color: #525260;
          line-height: 1.5;
          margin-top: -4px;
        }
        .share-row {
          display: flex;
          gap: 8px;
        }
        .share-input {
          flex: 1;
          background: #0C0C0E;
          border: 1px solid rgba(255,255,255,0.08);
          border-radius: 10px;
          padding: 11px 14px;
          font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
          font-size: 13px;
          color: #ffffff;
          outline: none;
          transition: border-color 0.2s;
          min-width: 0;
        }
        .share-input::placeholder { color: #3A3A48; }
        .share-input:focus { border-color: rgba(62,207,178,0.4); }
        .share-btn {
          background: transparent;
          border: 1px solid rgba(62,207,178,0.35);
          border-radius: 10px;
          padding: 11px 18px;
          font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
          font-size: 13px;
          font-weight: 700;
          color: #3ECFB2;
          cursor: pointer;
          white-space: nowrap;
          flex-shrink: 0;
          transition: background 0.2s, border-color 0.2s;
        }
        .share-btn:hover:not(:disabled) { background: rgba(62,207,178,0.08); border-color: rgba(62,207,178,0.6); }
        .share-btn:disabled { opacity: 0.45; cursor: default; }
        .share-sent {
          font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
          font-size: 12px;
          color: #3ECFB2;
          display: flex;
          align-items: center;
          gap: 6px;
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
                Subscribe &amp; watch ATLAS in action — unlock the demo the moment you join.
              </p>

              <div className="divider" />

              {status === 'success' ? (
                <div className="success-state">
                  <div className="success-check">✓</div>
                  <p className="success-heading">You're on the list.</p>
                  <p className="success-sub">
                    We sent your welcome email to{' '}
                    <strong style={{ color: '#8A8A96', fontWeight: 600 }}>{email}</strong>.
                  </p>
                  <p className="success-sub" style={{ marginTop: 8, color: '#3A3A48', fontSize: 12 }}>
                    Don't see it? Check your <strong style={{ color: '#525260' }}>spam or junk folder</strong>.
                  </p>
                </div>
              ) : status === 'verifying' || status === 'confirming' ? (
                <div className="verify-state">
                  <div className="verify-icon">✉️</div>
                  <p className="verify-heading">Check your inbox.</p>
                  <p className="verify-sub">
                    We sent a 5-digit code to <strong style={{ color: '#8A8A96' }}>{email}</strong>. Enter it below to unlock the demo.
                  </p>
                  <form className="form" style={{ width: '100%' }} onSubmit={handleVerify}>
                    <div className="code-row">
                      <input
                        className="code-input"
                        type="text"
                        inputMode="numeric"
                        placeholder="_ _ _ _ _"
                        maxLength={5}
                        value={codeInput}
                        onChange={e => setCodeInput(e.target.value.replace(/\D/g, '').slice(0, 5))}
                        autoFocus
                        autoComplete="one-time-code"
                        disabled={status === 'confirming'}
                      />
                      <button
                        className="submit-btn"
                        type="submit"
                        disabled={status === 'confirming' || codeInput.length < 5}
                      >
                        {status === 'confirming' ? 'Verifying…' : 'Unlock →'}
                      </button>
                    </div>
                    {errorMsg && <p className="error-msg">{errorMsg}</p>}
                  </form>
                  <button className="resend-btn" onClick={() => { setStatus('idle'); setCodeInput(''); setErrorMsg('') }}>
                    ← Use a different email
                  </button>
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
                      {status === 'loading' ? 'Sending…' : 'Subscribe & Watch →'}
                    </button>
                  </div>
                  {status === 'error' && (
                    <p className="error-msg">{errorMsg}</p>
                  )}
                </form>
              )}


            </div>
          </div>

          {/* Live subscriber counter banner */}
          {count !== null && (
            <div className="counter-banner">
              <div className="counter-dot" />
              <div className={`counter-coin${coinAnim ? ' pop' : ''}`}>✦</div>
              <span className="counter-label">
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

        {/* Locked demo teaser — shown before subscribing */}
        {!demoUnlocked && (
          <div style={{ width: '100%', maxWidth: 460, marginTop: 16 }}>
            <p className="demo-eyebrow" style={{ textAlign: 'center', marginBottom: 10 }}>↓ Demo Preview</p>
            <div className={`demo-locked${unlocking ? ' demo-unlocking' : ''}`}>
              <div className="demo-locked-thumb" />
              <div className="demo-locked-overlay">
                <span className="demo-lock-icon">🔒</span>
                <span className="demo-lock-text">Subscribe above to unlock the ATLAS demo</span>
              </div>
            </div>
          </div>
        )}

        {/* Unlocked demo section */}
        {demoUnlocked && (
          <div className="demo-section" ref={demoRef} style={{ marginTop: 48 }}>
            <button className="demo-back-btn" onClick={() => { setDemo(false); setStatus('idle'); setEmail(''); setCodeInput(''); setErrorMsg(''); window.scrollTo({ top: 0, behavior: 'smooth' }) }}>
              ← Back to Waitlist
            </button>
            <p className="demo-eyebrow">🔓 Demo Unlocked</p>
            <h2 className="demo-heading">See ATLAS in Action</h2>
            <p className="demo-sub">Watch how ATLAS autonomously installs plugins and software — drop a file, ATLAS handles the rest.</p>
            <p style={{ fontFamily: '-apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif', fontSize: 12, fontWeight: 600, color: '#3ECFB2', opacity: 0.8, marginTop: -8 }}>Stay Tuned for Subscription Plans &amp; Pricing.</p>
            <div className="demo-divider" />
            <div className="demo-video-wrap">
              <iframe
                className="demo-iframe"
                src="https://www.youtube.com/embed/OHbz5y4kHeg?rel=0&modestbranding=1&color=white&autoplay=1"
                title="ATLAS Demo"
                allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture"
                allowFullScreen
              />
            </div>

            {/* Share with a friend */}
            <div className="share-section">
              <p className="share-heading">Know someone who'd love this?</p>
              <p className="share-sub">Enter their email and we'll send them a personal invite to join the waitlist.</p>
              {shareStatus === 'sent' ? (
                <p className="share-sent">✓ Invite sent — they'll hear from us shortly.</p>
              ) : (
                <form className="share-row" onSubmit={handleShare}>
                  <input
                    className="share-input"
                    type="email"
                    placeholder="friend@email.com"
                    value={shareEmail}
                    onChange={e => setShareEmail(e.target.value)}
                    required
                    disabled={shareStatus === 'sending'}
                    autoComplete="off"
                  />
                  <button
                    className="share-btn"
                    type="submit"
                    disabled={shareStatus === 'sending' || !shareEmail}
                  >
                    {shareStatus === 'sending' ? 'Sending…' : 'Send Invite →'}
                  </button>
                </form>
              )}
              {shareStatus === 'error' && (
                <p className="error-msg">{shareError}</p>
              )}
            </div>
          </div>
        )}

      </div>
    </>
  )
}
