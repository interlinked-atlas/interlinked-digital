"use client"

import { useState } from "react"
import { createClient } from "@/lib/supabase/client"
import Link from "next/link"
import { useRouter, useSearchParams } from "next/navigation"
import Image from "next/image"
import { Check, Eye, EyeOff } from "lucide-react"
import { Suspense } from "react"

function SignupForm() {
  const [email, setEmail] = useState("")
  const [password, setPassword] = useState("")
  const [confirmPassword, setConfirmPassword] = useState("")
  const [showPassword, setShowPassword] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [loading, setLoading] = useState(false)
  const router = useRouter()
  const searchParams = useSearchParams()
  const plan = searchParams.get("plan") || "atlas-pro"
  const supabase = createClient()

  const planDetails = {
    "atlas-basic": {
      name: "Basic",
      price: "$14.99",
      features: ["Standard installations", "Core ATLAS workflow tools", "Single computer activation", "Up to 3 installs daily"]
    },
    "atlas-pro": {
      name: "Pro",
      price: "$29.99",
      features: ["Unlimited installations", "Bulk queue support", "Smart Uninstall Manager", "Recovery System", "Up to 3 computer activations"]
    }
  }

  const selectedPlan = planDetails[plan as keyof typeof planDetails] || planDetails["atlas-pro"]

  const validatePassword = (pass: string) => {
    if (pass.length < 8) return "Password must be at least 8 characters"
    if (!/[A-Z]/.test(pass)) return "Password must contain an uppercase letter"
    if (!/[a-z]/.test(pass)) return "Password must contain a lowercase letter"
    if (!/[0-9]/.test(pass)) return "Password must contain a number"
    return null
  }

  const handleSignup = async (e: React.FormEvent) => {
    e.preventDefault()
    setLoading(true)
    setError(null)

    // Validate password
    const passwordError = validatePassword(password)
    if (passwordError) {
      setError(passwordError)
      setLoading(false)
      return
    }

    if (password !== confirmPassword) {
      setError("Passwords do not match")
      setLoading(false)
      return
    }

    const { data, error: signUpError } = await supabase.auth.signUp({
      email,
      password,
      options: {
        emailRedirectTo: process.env.NEXT_PUBLIC_DEV_SUPABASE_REDIRECT_URL ?? 
          `${window.location.origin}/auth/callback?next=/atlas/checkout?plan=${plan}`,
        data: {
          selected_plan: plan
        }
      }
    })

    if (signUpError) {
      setError(signUpError.message)
      setLoading(false)
      return
    }

    // If email confirmation is disabled, redirect to checkout
    if (data.session) {
      router.push(`/atlas/checkout?plan=${plan}`)
      router.refresh()
    } else {
      // Email confirmation required
      router.push(`/atlas/signup/confirm?email=${encodeURIComponent(email)}&plan=${plan}`)
    }
  }

  return (
    <div className="min-h-screen bg-[#0a0a0f] flex items-center justify-center px-4 py-12">
      {/* Background effects */}
      <div className="fixed inset-0 overflow-hidden pointer-events-none">
        <div className="absolute top-1/4 left-1/4 w-96 h-96 bg-[#7c6fee]/5 rounded-full blur-3xl" />
        <div className="absolute bottom-1/4 right-1/4 w-96 h-96 bg-[#4ecdc4]/5 rounded-full blur-3xl" />
      </div>

      <div className="relative w-full max-w-lg">
        {/* Logo */}
        <div className="text-center mb-8">
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
          <p className="text-white/40 text-sm mt-2">Create your account to continue</p>
        </div>

        <div className="flex flex-col lg:flex-row gap-6">
          {/* Plan Summary */}
          <div className="lg:w-48 flex-shrink-0">
            <div className="bg-[#1a1a2e]/50 backdrop-blur-sm border border-white/10 rounded-xl p-4">
              <p className="text-xs uppercase tracking-wider text-white/40 mb-2">Selected Plan</p>
              <h3 className="text-lg font-semibold text-white mb-1">{selectedPlan.name}</h3>
              <p className="text-2xl font-bold bg-gradient-to-r from-[#7c6fee] to-[#4ecdc4] bg-clip-text text-transparent">
                {selectedPlan.price}<span className="text-sm text-white/50">/mo</span>
              </p>
              <div className="mt-4 space-y-2">
                {selectedPlan.features.slice(0, 3).map((feature, i) => (
                  <div key={i} className="flex items-start gap-2 text-xs text-white/60">
                    <Check className="w-3 h-3 text-[#4ecdc4] flex-shrink-0 mt-0.5" />
                    <span>{feature}</span>
                  </div>
                ))}
              </div>
              <Link 
                href="/atlas#pricing" 
                className="block mt-4 text-xs text-[#4ecdc4] hover:text-[#7c6fee] transition-colors"
              >
                Change plan
              </Link>
            </div>
          </div>

          {/* Signup Form */}
          <form onSubmit={handleSignup} className="flex-1 bg-[#1a1a2e]/50 backdrop-blur-sm border border-white/10 rounded-2xl p-6">
            <h2 className="text-xl font-semibold text-white mb-6">Create Account</h2>
            
            {error && (
              <div className="mb-6 p-4 bg-red-500/10 border border-red-500/20 rounded-xl text-red-400 text-sm">
                {error}
              </div>
            )}

            <div className="space-y-4">
              <div>
                <label htmlFor="email" className="block text-sm font-medium text-white/70 mb-2">
                  Email
                </label>
                <input
                  id="email"
                  type="email"
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  required
                  className="w-full px-4 py-3 bg-[#0a0a0f] border border-white/10 rounded-xl text-white placeholder-white/30 focus:outline-none focus:border-[#7c6fee]/50 transition-colors"
                  placeholder="you@example.com"
                />
              </div>

              <div>
                <label htmlFor="password" className="block text-sm font-medium text-white/70 mb-2">
                  Password
                </label>
                <div className="relative">
                  <input
                    id="password"
                    type={showPassword ? "text" : "password"}
                    value={password}
                    onChange={(e) => setPassword(e.target.value)}
                    required
                    className="w-full px-4 py-3 bg-[#0a0a0f] border border-white/10 rounded-xl text-white placeholder-white/30 focus:outline-none focus:border-[#7c6fee]/50 transition-colors pr-12"
                    placeholder="Min 8 characters"
                  />
                  <button
                    type="button"
                    onClick={() => setShowPassword(!showPassword)}
                    className="absolute right-4 top-1/2 -translate-y-1/2 text-white/40 hover:text-white/70 transition-colors"
                  >
                    {showPassword ? <EyeOff className="w-5 h-5" /> : <Eye className="w-5 h-5" />}
                  </button>
                </div>
                <p className="mt-2 text-xs text-white/40">
                  Must contain uppercase, lowercase, and a number
                </p>
              </div>

              <div>
                <label htmlFor="confirmPassword" className="block text-sm font-medium text-white/70 mb-2">
                  Confirm Password
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
                {loading ? "Creating account..." : "Continue to Payment"}
              </button>
            </div>

            <p className="mt-4 text-xs text-white/40 text-center">
              By signing up, you agree to our{" "}
              <a href="#" className="text-[#4ecdc4] hover:underline">Terms of Service</a>
              {" "}and{" "}
              <a href="#" className="text-[#4ecdc4] hover:underline">Privacy Policy</a>
            </p>
          </form>
        </div>

        <p className="text-center mt-6 text-white/50 text-sm">
          Already have an account?{" "}
          <Link href="/auth/login" className="text-[#4ecdc4] hover:text-[#7c6fee] transition-colors">
            Sign in
          </Link>
        </p>
      </div>
    </div>
  )
}

export default function SignupPage() {
  return (
    <Suspense fallback={
      <div className="min-h-screen bg-[#0a0a0f] flex items-center justify-center">
        <div className="text-white/50">Loading...</div>
      </div>
    }>
      <SignupForm />
    </Suspense>
  )
}
