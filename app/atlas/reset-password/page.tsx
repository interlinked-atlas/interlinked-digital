"use client"

import { useState, useEffect } from "react"
import { createClient } from "@/lib/supabase/client"
import Link from "next/link"
import { useRouter } from "next/navigation"

export default function AtlasResetPasswordPage() {
  const [password, setPassword] = useState("")
  const [confirmPassword, setConfirmPassword] = useState("")
  const [error, setError] = useState<string | null>(null)
  const [loading, setLoading] = useState(false)
  const [success, setSuccess] = useState(false)
  // null = still checking; "" never used as a value, undefined = no session found
  const [email, setEmail] = useState<string | null>(null)
  const [sessionChecked, setSessionChecked] = useState(false)
  const router = useRouter()
  const supabase = createClient()

  useEffect(() => {
    // Same proven pattern as the existing /auth/reset-password page: Supabase
    // processes the recovery token (verified server-side by /auth/confirm,
    // which already established the session via cookies before redirecting
    // here) asynchronously on the client, so we listen for the auth event
    // rather than racily checking the session immediately on mount.
    const { data: { subscription } } = supabase.auth.onAuthStateChange((event, session) => {
      if (event === "PASSWORD_RECOVERY") {
        setEmail(session?.user?.email ?? null)
        setSessionChecked(true)
      } else if (event === "SIGNED_OUT") {
        setSessionChecked(true)
      }
    })

    // The session may already be established by the time this page mounts
    // (set via cookies by /auth/confirm before the redirect) — PASSWORD_RECOVERY
    // only fires for the implicit/hash-based flow, not a pre-existing cookie
    // session, so check directly as the primary path, with the above listener
    // as a fallback for any client-side-detected recovery event.
    const check = setTimeout(async () => {
      const { data: { session } } = await supabase.auth.getSession()
      setEmail(session?.user?.email ?? null)
      setSessionChecked(true)
    }, 400)

    return () => {
      subscription.unsubscribe()
      clearTimeout(check)
    }
  }, [supabase])

  const handleReset = async (e: React.FormEvent) => {
    e.preventDefault()
    setLoading(true)
    setError(null)

    if (password !== confirmPassword) {
      setError("Passwords do not match")
      setLoading(false)
      return
    }

    if (password.length < 8) {
      setError("Password must be at least 8 characters")
      setLoading(false)
      return
    }

    const { error } = await supabase.auth.updateUser({ password })

    if (error) {
      setError(error.message)
      setLoading(false)
      return
    }

    setLoading(false)
    setSuccess(true)
  }

  return (
    <div className="min-h-screen bg-[#0a0a0f] flex items-center justify-center px-4">
      <div className="fixed inset-0 overflow-hidden pointer-events-none">
        <div className="absolute top-1/4 left-1/4 w-96 h-96 bg-[#7c6fee]/5 rounded-full blur-3xl" />
        <div className="absolute bottom-1/4 right-1/4 w-96 h-96 bg-[#4ecdc4]/5 rounded-full blur-3xl" />
      </div>

      <div className="relative w-full max-w-md">
        <div className="text-center mb-8">
          <Link href="/atlas" className="inline-block">
            <h1 className="text-2xl font-bold tracking-[0.2em] text-white/90" style={{ fontFamily: "'SF-Intellivised', sans-serif" }}>ATLAS</h1>
          </Link>
          <p className="text-white/40 text-sm mt-2">Set your new password</p>
        </div>

        {success ? (
          <div className="bg-[#1a1a2e]/50 backdrop-blur-sm border border-white/10 rounded-2xl p-8 text-center">
            <div className="w-16 h-16 mx-auto mb-6 rounded-full bg-[#4ecdc4]/20 flex items-center justify-center">
              <svg className="w-8 h-8 text-[#4ecdc4]" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5 13l4 4L19 7" />
              </svg>
            </div>
            <h2 className="text-xl font-semibold text-white mb-2">Password updated</h2>
            <p className="text-white/50 mb-6">
              Your password has been changed successfully. Taking you to your account…
            </p>
            {(() => {
              // Fire the redirect once, right here on render, rather than a
              // separate effect — keeps this file's state surface minimal.
              if (typeof window !== "undefined") {
                setTimeout(() => router.push("/atlas/account"), 1200)
              }
              return null
            })()}
            <Link
              href="/atlas/account"
              className="inline-block px-6 py-3 border border-white/20 rounded-xl text-white/70 hover:bg-white/5 transition-colors"
            >
              Go to your account now
            </Link>
          </div>
        ) : !sessionChecked ? (
          <div className="bg-[#1a1a2e]/50 backdrop-blur-sm border border-white/10 rounded-2xl p-8 text-center">
            <p className="text-white/40">Verifying your reset link…</p>
          </div>
        ) : !email ? (
          <div className="bg-[#1a1a2e]/50 backdrop-blur-sm border border-white/10 rounded-2xl p-8 text-center">
            <h2 className="text-xl font-semibold text-white mb-2">This reset link isn&apos;t valid</h2>
            <p className="text-white/50 mb-6">
              It may have expired or already been used. Request a new password reset link to continue.
            </p>
            <Link
              href="/auth/forgot-password"
              className="inline-block px-6 py-3 bg-gradient-to-r from-[#7c6fee] to-[#4ecdc4] rounded-xl font-medium hover:opacity-90 transition-opacity"
            >
              Request a new link
            </Link>
          </div>
        ) : (
          <form onSubmit={handleReset} className="bg-[#1a1a2e]/50 backdrop-blur-sm border border-white/10 rounded-2xl p-8">
            {error && (
              <div className="mb-6 p-4 bg-red-500/10 border border-red-500/20 rounded-xl text-red-400 text-sm">
                {error}
              </div>
            )}

            <div className="space-y-6">
              <div>
                <label className="block text-sm font-medium text-white/70 mb-2">
                  Account
                </label>
                <div className="w-full px-4 py-3 bg-[#0a0a0f] border border-white/10 rounded-xl text-white/60">
                  {email}
                </div>
              </div>

              <div>
                <label htmlFor="password" className="block text-sm font-medium text-white/70 mb-2">
                  New password
                </label>
                <input
                  id="password"
                  type="password"
                  value={password}
                  onChange={(e) => setPassword(e.target.value)}
                  required
                  minLength={8}
                  className="w-full px-4 py-3 bg-[#0a0a0f] border border-white/10 rounded-xl text-white placeholder-white/30 focus:outline-none focus:border-[#7c6fee]/50 transition-colors"
                  placeholder="Minimum 8 characters"
                />
              </div>

              <div>
                <label htmlFor="confirmPassword" className="block text-sm font-medium text-white/70 mb-2">
                  Confirm new password
                </label>
                <input
                  id="confirmPassword"
                  type="password"
                  value={confirmPassword}
                  onChange={(e) => setConfirmPassword(e.target.value)}
                  required
                  className="w-full px-4 py-3 bg-[#0a0a0f] border border-white/10 rounded-xl text-white placeholder-white/30 focus:outline-none focus:border-[#7c6fee]/50 transition-colors"
                  placeholder="Confirm your password"
                />
              </div>

              <button
                type="submit"
                disabled={loading}
                className="w-full py-4 bg-gradient-to-r from-[#7c6fee] to-[#4ecdc4] rounded-xl font-medium hover:opacity-90 transition-opacity disabled:opacity-50 disabled:cursor-not-allowed"
              >
                {loading ? "Updating…" : "Reset Password"}
              </button>
            </div>
          </form>
        )}
      </div>
    </div>
  )
}
