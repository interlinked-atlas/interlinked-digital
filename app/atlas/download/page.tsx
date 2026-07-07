"use client"

import { useEffect, useState } from "react"
import Link from "next/link"

export default function DownloadPage() {
  const [mounted, setMounted] = useState(false)
  useEffect(() => { const t = setTimeout(() => setMounted(true), 40); return () => clearTimeout(t) }, [])

  return (
    <div className="min-h-screen bg-[#0a0a0f] text-white flex flex-col items-center justify-center px-4 py-16">
      {/* Background blobs */}
      <div className="fixed inset-0 overflow-hidden pointer-events-none">
        <div className="absolute top-1/4 left-1/4 w-96 h-96 bg-[#7c6fee]/5 rounded-full blur-3xl" />
        <div className="absolute bottom-1/4 right-1/4 w-96 h-96 bg-[#4ecdc4]/5 rounded-full blur-3xl" />
      </div>

      <div
        className="relative w-full max-w-2xl"
        style={{
          opacity: mounted ? 1 : 0,
          transform: mounted ? 'translateY(0)' : 'translateY(20px)',
          transition: 'opacity 0.65s cubic-bezier(0.16,1,0.3,1), transform 0.65s cubic-bezier(0.16,1,0.3,1)',
        }}
      >
        {/* Logo */}
        <div className="text-center mb-10">
          <Link href="/atlas">
            <h1 className="text-2xl font-bold tracking-[0.2em] text-white/90">ATLAS</h1>
          </Link>
        </div>

        {/* Success badge */}
        <div className="flex justify-center mb-8">
          <div className="w-20 h-20 rounded-full bg-[#4ecdc4]/20 flex items-center justify-center">
            <svg className="w-10 h-10 text-[#4ecdc4]" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5 13l4 4L19 7" />
            </svg>
          </div>
        </div>

        <h2 className="text-4xl font-bold text-center mb-3">You&apos;re in.</h2>
        <p className="text-white/50 text-center text-lg mb-12">
          Your subscription is active. Download ATLAS and sign in to get started.
        </p>

        {/* Download cards */}
        <div className="grid grid-cols-1 sm:grid-cols-2 gap-4 mb-10">
          {/* Mac */}
          <a
            href="/downloads/ATLAS-latest.dmg"
            className="group bg-[#1a1a2e]/60 backdrop-blur-sm border border-white/10 rounded-2xl p-6 flex flex-col items-center gap-4 hover:border-[#4ecdc4]/40 hover:bg-[#1a1a2e]/80 transition-all"
          >
            <svg className="w-12 h-12 text-white/60 group-hover:text-white/90 transition-colors" viewBox="0 0 24 24" fill="currentColor">
              <path d="M18.71 19.5c-.83 1.24-1.71 2.45-3.05 2.47-1.34.03-1.77-.79-3.29-.79-1.53 0-2 .77-3.27.82-1.31.05-2.3-1.32-3.14-2.53C4.25 17 2.94 12.45 4.7 9.39c.87-1.52 2.43-2.48 4.12-2.51 1.28-.02 2.5.87 3.29.87.78 0 2.26-1.07 3.8-.91.65.03 2.47.26 3.64 1.98-.09.06-2.17 1.28-2.15 3.81.03 3.02 2.65 4.03 2.68 4.04-.03.07-.42 1.44-1.38 2.83M13 3.5c.73-.83 1.94-1.46 2.94-1.5.13 1.17-.34 2.35-1.04 3.19-.69.85-1.83 1.51-2.95 1.42-.15-1.15.41-2.35 1.05-3.11z"/>
            </svg>
            <div className="text-center">
              <div className="font-semibold text-white mb-1">Download for Mac</div>
              <div className="text-sm text-white/40">.dmg · macOS 12+</div>
            </div>
            <div className="mt-auto w-full py-3 bg-gradient-to-r from-[#7c6fee] to-[#4ecdc4] rounded-xl font-medium text-center text-sm group-hover:opacity-90 transition-opacity">
              Download
            </div>
          </a>

          {/* Windows */}
          <a
            href="/downloads/ATLAS-latest-win.exe"
            className="group bg-[#1a1a2e]/60 backdrop-blur-sm border border-white/10 rounded-2xl p-6 flex flex-col items-center gap-4 hover:border-[#7c6fee]/40 hover:bg-[#1a1a2e]/80 transition-all"
          >
            <svg className="w-12 h-12 text-white/60 group-hover:text-white/90 transition-colors" viewBox="0 0 24 24" fill="currentColor">
              <path d="M3 12V6.75l6-1.32v6.57H3zm17 0V5.25L11 3.5V12h9zm-17 1h6v6.43L3 18v-5zm17 0h-9v8.5l9-1.75V13z"/>
            </svg>
            <div className="text-center">
              <div className="font-semibold text-white mb-1">Download for Windows</div>
              <div className="text-sm text-white/40">.exe · Windows 10+</div>
            </div>
            <div className="mt-auto w-full py-3 bg-gradient-to-r from-[#7c6fee] to-[#4ecdc4] rounded-xl font-medium text-center text-sm group-hover:opacity-90 transition-opacity">
              Download
            </div>
          </a>
        </div>

        {/* Getting started steps */}
        <div className="bg-[#1a1a2e]/40 border border-white/8 rounded-2xl p-6 mb-8">
          <h3 className="font-semibold text-white mb-4">Getting started</h3>
          <ol className="space-y-3">
            {[
              'Download and install ATLAS for your platform above',
              'Open ATLAS — it lives in your menu bar',
              'Sign in with the email and password you just created',
              'Start installing plugins — ATLAS handles the rest',
            ].map((step, i) => (
              <li key={i} className="flex items-start gap-3 text-sm text-white/60">
                <span className="flex-shrink-0 w-5 h-5 rounded-full bg-[#7c6fee]/20 text-[#7c6fee] text-xs flex items-center justify-center font-medium mt-0.5">
                  {i + 1}
                </span>
                {step}
              </li>
            ))}
          </ol>
        </div>

        {/* Account link */}
        <p className="text-center text-white/40 text-sm">
          Your account is ready.{' '}
          <Link href="/atlas/account" className="text-[#4ecdc4] hover:text-[#7c6fee] transition-colors">
            View account dashboard →
          </Link>
        </p>
      </div>
    </div>
  )
}
