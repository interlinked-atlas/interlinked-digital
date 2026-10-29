'use client'

import { useState } from 'react'

const FAQ_ITEMS: { q: string; a: string }[] = [
  {
    q: 'What is ATLAS?',
    a: 'ATLAS is a macOS app that automates installing, tracking, and uninstalling software and plugins — no remote-install services, no handing anyone access to your Mac.',
  },
  {
    q: 'How much does it cost?',
    a: 'One plan: $30/month. Everything is included — no per-file charges, no tiers, no add-ons.',
  },
  {
    q: 'How many devices can I use it on?',
    a: 'Up to 3 devices per account.',
  },
  {
    q: 'What if I cancel?',
    a: 'Cancelling stops future renewal — you keep access through the period you’ve already paid for. No partial refunds for unused time.',
  },
  {
    q: 'Is there a Windows version?',
    a: 'Windows support is coming soon. You’ll be notified the moment it’s available.',
  },
  {
    q: 'What macOS version do I need?',
    a: 'macOS 12 Monterey or later, Apple Silicon or Intel.',
  },
  {
    q: 'Is my data private?',
    a: 'ATLAS runs locally on your Mac. Installation happens on your own machine — no one remotely accesses your computer.',
  },
]

function Modal({ title, onClose, children }: { title: string; onClose: () => void; children: React.ReactNode }) {
  return (
    <div
      onClick={onClose}
      style={{
        position: 'fixed', inset: 0, zIndex: 9999,
        background: 'rgba(8,8,9,0.82)',
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        padding: '20px',
      }}
    >
      <div
        onClick={e => e.stopPropagation()}
        style={{
          background: '#0E0E10',
          border: '1px solid rgba(255,255,255,0.09)',
          borderRadius: 16,
          padding: '24px 24px 28px',
          width: '100%', maxWidth: 440,
          maxHeight: '80vh',
          overflowY: 'auto',
          fontFamily: '"Inter", -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif',
        }}
      >
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 18 }}>
          <p style={{ color: '#FFFFFF', fontSize: 15, fontWeight: 600, letterSpacing: '-0.01em', margin: 0 }}>
            {title}
          </p>
          <button
            onClick={onClose}
            style={{ background: 'none', border: 'none', color: '#44444E', cursor: 'pointer', fontSize: 20, lineHeight: 1, padding: 0 }}
          >×</button>
        </div>
        {children}
      </div>
    </div>
  )
}

function FaqModal({ onClose }: { onClose: () => void }) {
  return (
    <Modal title="Frequently Asked Questions" onClose={onClose}>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>
        {FAQ_ITEMS.map((item, i) => (
          <div key={i}>
            <p style={{ color: '#E8E8F0', fontSize: 13, fontWeight: 600, marginBottom: 4 }}>{item.q}</p>
            <p style={{ color: '#8A8A96', fontSize: 13, lineHeight: 1.6, margin: 0 }}>{item.a}</p>
          </div>
        ))}
      </div>
    </Modal>
  )
}

function SupportModal({ onClose }: { onClose: () => void }) {
  const [email, setEmail] = useState('')
  const [message, setMessage] = useState('')
  const [status, setStatus] = useState<'idle' | 'sending' | 'sent' | 'error'>('idle')
  const [error, setError] = useState('')

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    setStatus('sending')
    setError('')
    try {
      const res = await fetch('/api/atlas/public-contact', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email, message }),
      })
      const data = await res.json()
      if (!res.ok) {
        setError(data.error ?? 'Something went wrong. Please try again.')
        setStatus('error')
        return
      }
      setStatus('sent')
    } catch {
      setError('Something went wrong. Please try again.')
      setStatus('error')
    }
  }

  return (
    <Modal title="Contact Support" onClose={onClose}>
      {status === 'sent' ? (
        <p style={{ color: '#8A8A96', fontSize: 13, lineHeight: 1.6 }}>
          Thanks — we got your message and will get back to you at <strong style={{ color: '#C8C8D0' }}>{email}</strong>, typically within 24 hours.
        </p>
      ) : (
        <form onSubmit={handleSubmit} style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
          {error && (
            <div style={{
              background: 'rgba(224,85,85,0.08)', border: '1px solid rgba(224,85,85,0.20)',
              borderRadius: 9, padding: '8px 12px', color: '#E05555', fontSize: 12,
            }}>{error}</div>
          )}
          <input
            type="email"
            required
            placeholder="Your email"
            value={email}
            onChange={e => setEmail(e.target.value)}
            style={{
              width: '100%', padding: '11px 14px',
              background: 'rgba(255,255,255,0.04)', border: '1px solid rgba(255,255,255,0.09)',
              borderRadius: 9, color: '#FFFFFF', fontSize: 13, outline: 'none', boxSizing: 'border-box',
            }}
          />
          <textarea
            required
            placeholder="How can we help?"
            value={message}
            onChange={e => setMessage(e.target.value)}
            rows={5}
            style={{
              width: '100%', padding: '11px 14px',
              background: 'rgba(255,255,255,0.04)', border: '1px solid rgba(255,255,255,0.09)',
              borderRadius: 9, color: '#FFFFFF', fontSize: 13, outline: 'none', boxSizing: 'border-box',
              resize: 'vertical', fontFamily: 'inherit',
            }}
          />
          <button
            type="submit"
            disabled={status === 'sending'}
            style={{
              width: '100%', padding: 12, border: 'none', borderRadius: 10,
              background: 'linear-gradient(135deg, #3ECFB2, #2ABEAA)',
              color: '#080809', fontSize: 13, fontWeight: 700,
              cursor: status === 'sending' ? 'default' : 'pointer',
              opacity: status === 'sending' ? 0.7 : 1,
            }}
          >
            {status === 'sending' ? 'Sending…' : 'Send Message'}
          </button>
        </form>
      )}
    </Modal>
  )
}

export function SiteFooterLinks() {
  const [open, setOpen] = useState<'faq' | 'support' | null>(null)

  return (
    <>
      <p style={{ textAlign: 'center', marginTop: 10 }}>
        <a href="/atlas/terms" style={{ color: '#44444E', fontSize: 12, textDecoration: 'none' }}>Terms of Service</a>
        <span style={{ color: '#2A2A32', fontSize: 12, margin: '0 10px' }}>·</span>
        <button
          onClick={() => setOpen('support')}
          style={{ background: 'none', border: 'none', color: '#44444E', fontSize: 12, cursor: 'pointer', padding: 0 }}
        >Support</button>
        <span style={{ color: '#2A2A32', fontSize: 12, margin: '0 10px' }}>·</span>
        <button
          onClick={() => setOpen('faq')}
          style={{ background: 'none', border: 'none', color: '#44444E', fontSize: 12, cursor: 'pointer', padding: 0 }}
        >FAQ</button>
      </p>

      {open === 'faq' && <FaqModal onClose={() => setOpen(null)} />}
      {open === 'support' && <SupportModal onClose={() => setOpen(null)} />}
    </>
  )
}
