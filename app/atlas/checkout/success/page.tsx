"use client"

import { useEffect, useState } from "react"
import { useSearchParams, useRouter } from "next/navigation"
import Link from "next/link"
import { Suspense } from "react"
import { getCheckoutSessionStatus } from "@/app/actions/stripe"
import { createClient } from "@/lib/supabase/client"
import { nextPollOutcome } from "@/lib/entitlementPoll"

// Stripe's own session.status === 'complete' only means the customer
// finished paying — it says nothing about whether our webhook has actually
// updated Supabase yet. Polling subscriptions.status directly (the same
// canonical column the account dashboard's Realtime subscription watches)
// avoids telling the customer "You're subscribed!" before entitlement is
// actually active. If the webhook hasn't landed within the poll window, we
// still move on to the account page rather than block indefinitely — that
// page has its own Realtime subscription and will self-correct the moment
// the webhook completes.
const ENTITLEMENT_POLL_ATTEMPTS = 5
const ENTITLEMENT_POLL_INTERVAL_MS = 1500

function SuccessContent() {
  const searchParams = useSearchParams()
  const router = useRouter()
  const sessionId = searchParams.get("session_id")
  const [status, setStatus] = useState<"loading" | "pending" | "success" | "error">("loading")

  useEffect(() => {
    let cancelled = false

    async function waitForEntitlement() {
      const supabase = createClient()
      const { data: { user } } = await supabase.auth.getUser()
      if (!user) return false

      for (let attempt = 0; attempt < ENTITLEMENT_POLL_ATTEMPTS; attempt++) {
        if (cancelled) return false
        const { data: subscription } = await supabase
          .from("subscriptions")
          .select("status")
          .eq("user_id", user.id)
          .single()
        const outcome = nextPollOutcome(subscription?.status, attempt, ENTITLEMENT_POLL_ATTEMPTS)
        if (outcome === 'active') return true
        if (outcome === 'give_up') return false
        await new Promise((r) => setTimeout(r, ENTITLEMENT_POLL_INTERVAL_MS))
      }
      return false
    }

    if (sessionId) {
      getCheckoutSessionStatus(sessionId)
        .then(async (data) => {
          if (data.status !== "complete") {
            if (!cancelled) setStatus("error")
            return
          }
          setStatus("pending")
          const entitled = await waitForEntitlement()
          if (cancelled) return
          setStatus("success")
          // Whether or not the webhook confirmed within the poll window, the
          // account page is Realtime-backed and will reflect the real state
          // the moment it lands — we never grant access here, only navigate.
          setTimeout(() => router.push("/atlas/account?welcome=1"), entitled ? 800 : 0)
        })
        .catch(() => { if (!cancelled) setStatus("error") })
    } else {
      setStatus("error")
    }

    return () => { cancelled = true }
  }, [sessionId, router])

  if (status === "loading" || status === "pending") {
    return (
      <div className="text-center">
        <div className="w-12 h-12 border-2 border-white/20 border-t-[#4ecdc4] rounded-full animate-spin mx-auto mb-6" />
        <p className="text-white/50">
          {status === "pending" ? "Activating your subscription…" : "Confirming your subscription..."}
        </p>
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
      <h1 className="text-3xl font-bold mb-4">You&apos;re subscribed!</h1>
      <p className="text-white/50 mb-8 max-w-md mx-auto">
        Your subscription is active. Taking you to your account…
      </p>
      <div className="w-8 h-8 border-2 border-white/20 border-t-[#4ecdc4] rounded-full animate-spin mx-auto" />
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
