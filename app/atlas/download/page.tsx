"use client"

import { useEffect, useState } from "react"
import Link from "next/link"
import Image from "next/image"

function StepCard({
  number,
  title,
  children,
}: {
  number: number
  title: string
  children: React.ReactNode
}) {
  return (
    <div className="bg-[#1a1a2e]/40 border border-white/8 rounded-2xl p-6 mb-5">
      <div className="flex items-start gap-4">
        <span className="flex-shrink-0 w-8 h-8 rounded-full bg-[#7c6fee]/20 text-[#7c6fee] text-sm flex items-center justify-center font-semibold mt-0.5">
          {number}
        </span>
        <div className="flex-1 min-w-0">
          <h3 className="font-semibold text-white mb-2">{title}</h3>
          <div className="text-sm text-white/60 leading-relaxed">{children}</div>
        </div>
      </div>
    </div>
  )
}

export default function DownloadPage() {
  const [mounted, setMounted] = useState(false)
  useEffect(() => { const t = setTimeout(() => setMounted(true), 40); return () => clearTimeout(t) }, [])

  return (
    <div className="min-h-screen bg-[#0a0a0f] text-white flex flex-col items-center px-4 py-16">
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
          Your subscription is active. Download ATLAS and follow the steps below to get set up.
        </p>

        {/* Download card */}
        <div className="mb-12">
          <a
            href="/downloads/ATLAS-latest.dmg"
            download="ATLAS.dmg"
            className="group block bg-[#1a1a2e]/60 backdrop-blur-sm border border-white/10 rounded-2xl p-6 hover:border-[#4ecdc4]/40 hover:bg-[#1a1a2e]/80 transition-all"
          >
            <div className="flex items-center gap-4">
              <svg className="w-10 h-10 text-white/60 group-hover:text-white/90 transition-colors flex-shrink-0" viewBox="0 0 24 24" fill="currentColor">
                <path d="M18.71 19.5c-.83 1.24-1.71 2.45-3.05 2.47-1.34.03-1.77-.79-3.29-.79-1.53 0-2 .77-3.27.82-1.31.05-2.3-1.32-3.14-2.53C4.25 17 2.94 12.45 4.7 9.39c.87-1.52 2.43-2.48 4.12-2.51 1.28-.02 2.5.87 3.29.87.78 0 2.26-1.07 3.8-.91.65.03 2.47.26 3.64 1.98-.09.06-2.17 1.28-2.15 3.81.03 3.02 2.65 4.03 2.68 4.04-.03.07-.42 1.44-1.38 2.83M13 3.5c.73-.83 1.94-1.46 2.94-1.5.13 1.17-.34 2.35-1.04 3.19-.69.85-1.83 1.51-2.95 1.42-.15-1.15.41-2.35 1.05-3.11z"/>
              </svg>
              <div className="flex-1">
                <div className="font-semibold text-white mb-1">Download ATLAS for Mac</div>
                <div className="text-sm text-white/40">.dmg · macOS 12 Monterey or later · Apple Silicon or Intel</div>
              </div>
              <div className="px-5 py-2.5 bg-gradient-to-r from-[#7c6fee] to-[#4ecdc4] rounded-xl font-medium text-sm whitespace-nowrap group-hover:opacity-90 transition-opacity">
                Download
              </div>
            </div>
          </a>
          <p className="text-center text-white/30 text-xs mt-3">
            Windows support is coming soon — you&apos;ll be notified the moment it&apos;s available.
          </p>
        </div>

        {/* Setup guide */}
        <div className="mb-4">
          <h3 className="text-xs font-bold tracking-[3px] uppercase text-white/40 text-center mb-6">
            Setup Guide
          </h3>

          <StepCard number={1} title="Open the downloaded .dmg">
            Once it finishes downloading, double-click <code className="bg-white/10 px-1.5 py-0.5 rounded text-white/80">ATLAS.dmg</code> in
            your Downloads folder to mount it.
          </StepCard>

          <StepCard number={2} title="Drag ATLAS into Applications">
            <p className="mb-4">
              A window opens with the ATLAS icon and an Applications folder shortcut side by side. Drag the ATLAS icon onto
              the Applications folder to install it.
            </p>
            <div className="rounded-xl overflow-hidden border border-white/10 bg-black">
              <Image
                src="/atlas-guide/drag-drop.png"
                alt="Drag the ATLAS icon into the Applications folder shortcut"
                width={1920}
                height={1080}
                className="w-full h-auto"
              />
            </div>
          </StepCard>

          <StepCard number={3} title="Open ATLAS — and allow it past Gatekeeper">
            <p className="mb-3">
              Since ATLAS is a new app, macOS Gatekeeper will warn you the first time you open it. This is expected and normal — here&apos;s how to get past it:
            </p>
            <ol className="space-y-2 list-decimal list-inside text-white/60">
              <li>Open your <span className="text-white/80">Applications</span> folder and find ATLAS.</li>
              <li><span className="text-white/80">Right-click</span> (or Control-click) the ATLAS icon and choose <span className="text-white/80">Open</span> — do not just double-click it the first time.</li>
              <li>A dialog will appear saying macOS can&apos;t verify the developer. Click <span className="text-white/80">Open</span> again to confirm.</li>
              <li>ATLAS will now launch, and every time after this you can open it normally.</li>
            </ol>
            <p className="mt-3 text-white/40 text-xs">
              If you only see a &quot;move to Trash&quot; option with no Open button, go to System Settings → Privacy &amp; Security,
              scroll down, and click <span className="text-white/60">Open Anyway</span> next to the ATLAS warning.
            </p>
          </StepCard>

          <StepCard number={4} title="Sign in and grant permissions">
            <p className="mb-2">
              Sign in with the email and password you just created. ATLAS will then walk you through a one-time setup:
            </p>
            <ul className="space-y-2 list-disc list-inside text-white/60">
              <li><span className="text-white/80">Admin password</span> — ATLAS asks for your Mac&apos;s login password once, so it can install and uninstall plugins cleanly. This is stored securely in macOS Keychain, never sent anywhere.</li>
              <li><span className="text-white/80">Full Disk Access</span> — macOS may prompt you to grant this in System Settings → Privacy &amp; Security so ATLAS can manage plugin files across your system.</li>
            </ul>
          </StepCard>

          <StepCard number={5} title="Start installing">
            Drag any plugin installer — a .dmg, .pkg, or .zip — onto the ATLAS window, and it handles the rest: installation,
            tracking, and clean uninstall whenever you need it.
          </StepCard>
        </div>

        {/* Account link */}
        <p className="text-center text-white/40 text-sm mt-10">
          Your account is ready.{' '}
          <Link href="/atlas/account" className="text-[#4ecdc4] hover:text-[#7c6fee] transition-colors">
            View account dashboard →
          </Link>
        </p>
      </div>
    </div>
  )
}
