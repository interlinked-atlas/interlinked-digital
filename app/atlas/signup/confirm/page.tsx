"use client"

import { Suspense } from "react"
import { useSearchParams } from "next/navigation"
import Link from "next/link"
import Image from "next/image"
import { Mail, ArrowLeft } from "lucide-react"

function ConfirmContent() {
  const searchParams = useSearchParams()
  const email = searchParams.get("email") || ""
  const plan = searchParams.get("plan") || "atlas-pro"

  return (
    <div className="min-h-screen bg-[#0a0a0f] flex items-center justify-center px-4">
      {/* Background effects */}
      <div className="fixed inset-0 overflow-hidden pointer-events-none">
        <div className="absolute top-1/4 left-1/4 w-96 h-96 bg-[#7c6fee]/5 rounded-full blur-3xl" />
        <div className="absolute bottom-1/4 right-1/4 w-96 h-96 bg-[#4ecdc4]/5 rounded-full blur-3xl" />
      </div>

      <div className="relative w-full max-w-md text-center">
        {/* Logo */}
        <div className="mb-8">
          <Link href="/atlas" className="inline-flex items-center gap-3">
            <Image 
              src="/images/atlas-icon.png" 
              alt="ATLAS" 
              width={40} 
              height={40}
              className="w-10 h-10"
            />
            <span className="text-2xl font-bold tracking-wide text-white">ATLAS</span>
          </Link>
        </div>

        <div className="bg-[#1a1a2e]/50 backdrop-blur-sm border border-white/10 rounded-2xl p-8">
          {/* Email Icon */}
          <div className="inline-flex items-center justify-center w-16 h-16 bg-gradient-to-r from-[#7c6fee]/20 to-[#4ecdc4]/20 rounded-full mb-6">
            <Mail className="w-8 h-8 text-[#4ecdc4]" />
          </div>

          <h1 className="text-2xl font-bold text-white mb-4">Check your email</h1>
          
          <p className="text-white/60 mb-6">
            We sent a confirmation link to<br />
            <span className="text-white font-medium">{email}</span>
          </p>

          <p className="text-white/40 text-sm mb-8">
            Click the link in the email to verify your account, then you&apos;ll be taken to complete your payment.
          </p>

          <div className="space-y-3">
            <a 
              href={`https://mail.google.com/mail/u/0/#search/from%3Asupabase+OR+from%3Ainterlinked`}
              target="_blank"
              rel="noopener noreferrer"
              className="block w-full py-3 bg-gradient-to-r from-[#7c6fee] to-[#4ecdc4] rounded-xl font-medium hover:opacity-90 transition-opacity"
            >
              Open Gmail
            </a>
            
            <a 
              href="https://outlook.live.com/mail/"
              target="_blank"
              rel="noopener noreferrer"
              className="block w-full py-3 border border-white/20 rounded-xl font-medium hover:bg-white/5 transition-colors text-white/80"
            >
              Open Outlook
            </a>
          </div>

          <p className="mt-6 text-white/40 text-xs">
            {"Didn't receive the email? Check your spam folder or "}
            <Link href={`/atlas/signup?plan=${plan}`} className="text-[#4ecdc4] hover:underline">
              try again
            </Link>
          </p>
        </div>

        <Link 
          href="/atlas"
          className="inline-flex items-center gap-2 mt-6 text-white/50 text-sm hover:text-white transition-colors"
        >
          <ArrowLeft className="w-4 h-4" />
          Back to ATLAS
        </Link>
      </div>
    </div>
  )
}

export default function ConfirmPage() {
  return (
    <Suspense fallback={
      <div className="min-h-screen bg-[#0a0a0f] flex items-center justify-center">
        <div className="text-white/50">Loading...</div>
      </div>
    }>
      <ConfirmContent />
    </Suspense>
  )
}
