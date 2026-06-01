"use client"

import { useEffect, useState } from "react"
import { useSearchParams } from "next/navigation"
import Link from "next/link"
import { Suspense } from "react"
import { getCheckoutSessionStatus } from "@/app/actions/stripe"

function SuccessContent() {
  const searchParams = useSearchParams()
  const sessionId = searchParams.get("session_id")
  const [status, setStatus] = useState<"loading" | "success" | "error">("loading")
  const [email, setEmail] = useState<string | null>(null)

  useEffect(() => {
    if (sessionId) {
      getCheckoutSessionStatus(sessionId)
        .then((data) => {
          if (data.status === "complete") {
            setStatus("success")
            setEmail(data.customerEmail || null)
          } else {
            setStatus("error")
          }
        })
        .catch(() => setStatus("error"))
    } else {
      setStatus("error")
    }
  }, [sessionId])

  if (status === "loading") {
    return (
      <div className="text-center">
        <div className="w-12 h-12 border-2 border-white/20 border-t-[#4ecdc4] rounded-full animate-spin mx-auto mb-6" />
        <p className="text-white/50">Confirming your subscription...</p>
      </div>
    )
  }

  if (status === "error") {
    return (
      <div className="text-center">
        <div className="w-20 h-20 mx-auto mb-6 rounded-full bg-red-500/20 flex items-center justify-center">
          <svg className="w-10 h-10 text-red-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
          </svg>
        </div>
        <h1 className="text-3xl font-bold mb-4">Something went wrong</h1>
        <p className="text-white/50 mb-8 max-w-md mx-auto">
          We couldn&apos;t confirm your subscription. Please contact support if you were charged.
        </p>
        <Link
          href="/atlas"
          className="inline-block px-8 py-4 bg-gradient-to-r from-[#7c6fee] to-[#4ecdc4] rounded-xl font-medium hover:opacity-90 transition-opacity"
        >
          Back to ATLAS
        </Link>
      </div>
    )
  }

  return (
    <div className="text-center">
      <div className="w-20 h-20 mx-auto mb-6 rounded-full bg-[#4ecdc4]/20 flex items-center justify-center">
        <svg className="w-10 h-10 text-[#4ecdc4]" fill="none" viewBox="0 0 24 24" stroke="currentColor">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5 13l4 4L19 7" />
        </svg>
      </div>
      <h1 className="text-3xl font-bold mb-4">Welcome to ATLAS!</h1>
      <p className="text-white/50 mb-2 max-w-md mx-auto">
        Your subscription is now active.
      </p>
      {email && (
        <p className="text-white/50 mb-8 max-w-md mx-auto">
          Check <span className="text-white">{email}</span> for your login details and password setup link.
        </p>
      )}
      
      <div className="flex flex-col sm:flex-row items-center justify-center gap-4">
        <Link
          href="/auth/login"
          className="w-full sm:w-auto px-8 py-4 bg-gradient-to-r from-[#7c6fee] to-[#4ecdc4] rounded-xl font-medium hover:opacity-90 transition-opacity"
        >
          Sign In to Your Account
        </Link>
        <Link
          href="/atlas#download"
          className="w-full sm:w-auto px-8 py-4 border border-white/20 rounded-xl font-medium hover:bg-white/5 transition-colors"
        >
          Download ATLAS
        </Link>
      </div>
    </div>
  )
}

export default function SuccessPage() {
  return (
    <div className="min-h-screen bg-[#0a0a0f] text-white flex items-center justify-center px-4">
      <div className="fixed inset-0 overflow-hidden pointer-events-none">
        <div className="absolute top-1/4 left-1/4 w-96 h-96 bg-[#7c6fee]/5 rounded-full blur-3xl" />
        <div className="absolute bottom-1/4 right-1/4 w-96 h-96 bg-[#4ecdc4]/5 rounded-full blur-3xl" />
      </div>

      <div className="relative w-full max-w-lg">
        <Suspense fallback={
          <div className="text-center">
            <div className="w-12 h-12 border-2 border-white/20 border-t-[#4ecdc4] rounded-full animate-spin mx-auto mb-6" />
            <p className="text-white/50">Loading...</p>
          </div>
        }>
          <SuccessContent />
        </Suspense>
      </div>
    </div>
  )
}
