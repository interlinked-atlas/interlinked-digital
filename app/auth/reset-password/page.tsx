"use client"

import { useState, useEffect } from "react"
import { createClient } from "@/lib/supabase/client"
import Link from "next/link"
import { useRouter } from "next/navigation"

export default function ResetPasswordPage() {
  const [password, setPassword] = useState("")
  const [confirmPassword, setConfirmPassword] = useState("")
  const [error, setError] = useState<string | null>(null)
  const [loading, setLoading] = useState(false)
  const router = useRouter()
  const supabase = createClient()

  useEffect(() => {
    // Check if we have a valid session from the reset link
    const checkSession = async () => {
      const { data: { session } } = await supabase.auth.getSession()
      if (!session) {
        router.push("/auth/forgot-password")
      }
    }
    checkSession()
  }, [supabase, router])

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

    router.push("/atlas/account")
  }

  return (
    <div className="min-h-screen bg-[#0a0a0f] flex items-center justify-center px-4">
      <div className="fixed inset-0 overflow-hidden pointer-events-none">
        <div className="absolute top-1/4 left-1/4 w-96 h-96 bg-[#7c6fee]/5 rounded-full blur-3xl" />
        <div className="absolute bottom-1/4 right-1/4 w-96 h-96 bg-[#4ecdc4]/5 rounded-full blur-3xl" />
      </div>

      <div className="relative w-full max-w-md">
        <div className="text-center mb-8">
          <Link href="/" className="inline-block">
            <h1 className="text-2xl font-bold tracking-[0.2em] text-white/90">INTERLINKED</h1>
          </Link>
          <p className="text-white/40 text-sm mt-2">Set your new password</p>
        </div>

        <form onSubmit={handleReset} className="bg-[#1a1a2e]/50 backdrop-blur-sm border border-white/10 rounded-2xl p-8">
          {error && (
            <div className="mb-6 p-4 bg-red-500/10 border border-red-500/20 rounded-xl text-red-400 text-sm">
              {error}
            </div>
          )}

          <div className="space-y-6">
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
                Confirm password
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
              {loading ? "Updating..." : "Update password"}
            </button>
          </div>
        </form>
      </div>
    </div>
  )
}
