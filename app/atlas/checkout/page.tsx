'use client'

import { Suspense, useState } from 'react'
import { useSearchParams, useRouter } from 'next/navigation'
import Link from 'next/link'
import Image from 'next/image'
import Checkout from '@/components/checkout'
import { PRODUCTS } from '@/lib/products'
import { createClient } from '@/lib/supabase/client'
import { Eye, EyeOff, Check, ArrowRight, Loader2 } from 'lucide-react'

type Step = 'account' | 'payment'

function CheckoutContent() {
  const searchParams = useSearchParams()
  const router = useRouter()
  const planId = searchParams.get('plan')
  
  const [step, setStep] = useState<Step>('account')
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [confirmPassword, setConfirmPassword] = useState('')
  const [showPassword, setShowPassword] = useState(false)
  const [isLoading, setIsLoading] = useState(false)
  const [error, setError] = useState('')
  const [isLoggedIn, setIsLoggedIn] = useState(false)
  
  const product = PRODUCTS.find(p => p.id === planId)
  
  // Check if user is already logged in on mount
  useState(() => {
    const checkAuth = async () => {
      const supabase = createClient()
      const { data: { user } } = await supabase.auth.getUser()
      if (user) {
        setEmail(user.email || '')
        setIsLoggedIn(true)
        setStep('payment')
      }
    }
    checkAuth()
  })
  
  if (!planId || !product) {
    return (
      <div className="min-h-screen bg-[#0a0a0f] text-white flex items-center justify-center">
        <div className="text-center">
          <h1 className="text-2xl font-bold mb-4">No plan selected</h1>
          <p className="text-white/50 mb-8">Please select a subscription plan first.</p>
          <Link 
            href="/atlas#pricing"
            className="px-6 py-3 bg-gradient-to-r from-[#7c6fee] to-[#4ecdc4] rounded-xl font-medium hover:opacity-90 transition-opacity"
          >
            View Plans
          </Link>
        </div>
      </div>
    )
  }

  const handleCreateAccount = async (e: React.FormEvent) => {
    e.preventDefault()
    setError('')
    
    if (password !== confirmPassword) {
      setError('Passwords do not match')
      return
    }
    
    if (password.length < 8) {
      setError('Password must be at least 8 characters')
      return
    }
    
    setIsLoading(true)
    
    try {
      const supabase = createClient()
      
      const { data, error: signUpError } = await supabase.auth.signUp({
        email,
        password,
        options: {
          emailRedirectTo: process.env.NEXT_PUBLIC_DEV_SUPABASE_REDIRECT_URL ?? 
            `${window.location.origin}/auth/callback`,
        },
      })
      
      if (signUpError) {
        if (signUpError.message.includes('already registered')) {
          // Try to sign in instead
          const { error: signInError } = await supabase.auth.signInWithPassword({
            email,
            password,
          })
          
          if (signInError) {
            setError('This email is already registered. Please use the correct password or reset it.')
            setIsLoading(false)
            return
          }
          
          setIsLoggedIn(true)
          setStep('payment')
        } else {
          setError(signUpError.message)
        }
        setIsLoading(false)
        return
      }
      
      if (data.user) {
        setIsLoggedIn(true)
        setStep('payment')
      }
    } catch (err) {
      setError('An unexpected error occurred. Please try again.')
    }
    
    setIsLoading(false)
  }

  const handleLogin = async (e: React.FormEvent) => {
    e.preventDefault()
    setError('')
    setIsLoading(true)
    
    try {
      const supabase = createClient()
      const { error: signInError } = await supabase.auth.signInWithPassword({
        email,
        password,
      })
      
      if (signInError) {
        setError(signInError.message)
        setIsLoading(false)
        return
      }
      
      setIsLoggedIn(true)
      setStep('payment')
    } catch (err) {
      setError('An unexpected error occurred. Please try again.')
    }
    
    setIsLoading(false)
  }

  const [mode, setMode] = useState<'signup' | 'login'>('signup')
  
  return (
    <div className="min-h-screen bg-[#0a0a0f] text-white">
      {/* Header */}
      <header className="border-b border-white/5 bg-[#0a0a0f]/80 backdrop-blur-xl">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-4">
          <div className="flex items-center justify-between">
            <Link href="/atlas" className="flex items-center gap-2">
              <Image 
                src="/images/atlas-icon.png" 
                alt="ATLAS" 
                width={32} 
                height={32}
                className="w-8 h-8"
              />
              <span className="text-xl font-semibold tracking-wide">ATLAS</span>
            </Link>
            <Link 
              href="/atlas#pricing"
              className="text-sm text-white/60 hover:text-white transition-colors"
            >
              Back to Plans
            </Link>
          </div>
        </div>
      </header>

      <main className="max-w-4xl mx-auto px-4 sm:px-6 lg:px-8 py-12">
        {/* Progress Steps */}
        <div className="flex items-center justify-center gap-4 mb-12">
          <div className={`flex items-center gap-2 ${step === 'account' ? 'text-white' : 'text-white/40'}`}>
            <div className={`w-8 h-8 rounded-full flex items-center justify-center text-sm font-medium ${
              step === 'account' ? 'bg-gradient-to-r from-[#7c6fee] to-[#4ecdc4]' : 
              step === 'payment' ? 'bg-[#4ecdc4]' : 'bg-white/20'
            }`}>
              {step === 'payment' ? <Check className="w-4 h-4" /> : '1'}
            </div>
            <span className="text-sm font-medium">Create Account</span>
          </div>
          
          <div className="w-12 h-px bg-white/20" />
          
          <div className={`flex items-center gap-2 ${step === 'payment' ? 'text-white' : 'text-white/40'}`}>
            <div className={`w-8 h-8 rounded-full flex items-center justify-center text-sm font-medium ${
              step === 'payment' ? 'bg-gradient-to-r from-[#7c6fee] to-[#4ecdc4]' : 'bg-white/20'
            }`}>
              2
            </div>
            <span className="text-sm font-medium">Payment</span>
          </div>
        </div>

        {/* Plan Summary */}
        <div className="bg-[#1a1a2e] rounded-xl border border-white/10 p-4 mb-8">
          <div className="flex items-center justify-between">
            <div>
              <h3 className="font-semibold">{product.name}</h3>
              <p className="text-sm text-white/50">{product.description}</p>
            </div>
            <div className="text-right">
              <p className="text-2xl font-bold">${(product.priceInCents / 100).toFixed(2)}</p>
              <p className="text-sm text-white/50">per {product.interval}</p>
            </div>
          </div>
        </div>

        {/* Step 1: Account Creation */}
        {step === 'account' && (
          <div className="bg-[#1a1a2e] rounded-2xl border border-white/10 p-8">
            <h2 className="text-2xl font-bold mb-2">
              {mode === 'signup' ? 'Create your account' : 'Sign in to continue'}
            </h2>
            <p className="text-white/50 mb-8">
              {mode === 'signup' 
                ? 'Set up your ATLAS account to manage your subscription'
                : 'Already have an account? Sign in to subscribe'
              }
            </p>
            
            <form onSubmit={mode === 'signup' ? handleCreateAccount : handleLogin} className="space-y-6">
              <div>
                <label htmlFor="email" className="block text-sm font-medium mb-2">
                  Email address
                </label>
                <input
                  type="email"
                  id="email"
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  required
                  className="w-full px-4 py-3 bg-[#0a0a0f] border border-white/10 rounded-xl focus:outline-none focus:border-[#7c6fee] transition-colors"
                  placeholder="you@example.com"
                />
              </div>
              
              <div>
                <label htmlFor="password" className="block text-sm font-medium mb-2">
                  Password
                </label>
                <div className="relative">
                  <input
                    type={showPassword ? 'text' : 'password'}
                    id="password"
                    value={password}
                    onChange={(e) => setPassword(e.target.value)}
                    required
                    minLength={8}
                    className="w-full px-4 py-3 bg-[#0a0a0f] border border-white/10 rounded-xl focus:outline-none focus:border-[#7c6fee] transition-colors pr-12"
                    placeholder={mode === 'signup' ? 'At least 8 characters' : 'Enter your password'}
                  />
                  <button
                    type="button"
                    onClick={() => setShowPassword(!showPassword)}
                    className="absolute right-4 top-1/2 -translate-y-1/2 text-white/40 hover:text-white transition-colors"
                  >
                    {showPassword ? <EyeOff className="w-5 h-5" /> : <Eye className="w-5 h-5" />}
                  </button>
                </div>
              </div>
              
              {mode === 'signup' && (
                <div>
                  <label htmlFor="confirmPassword" className="block text-sm font-medium mb-2">
                    Confirm password
                  </label>
                  <input
                    type={showPassword ? 'text' : 'password'}
                    id="confirmPassword"
                    value={confirmPassword}
                    onChange={(e) => setConfirmPassword(e.target.value)}
                    required
                    className="w-full px-4 py-3 bg-[#0a0a0f] border border-white/10 rounded-xl focus:outline-none focus:border-[#7c6fee] transition-colors"
                    placeholder="Confirm your password"
                  />
                </div>
              )}
              
              {error && (
                <div className="p-4 bg-red-500/10 border border-red-500/20 rounded-xl text-red-400 text-sm">
                  {error}
                </div>
              )}
              
              <button
                type="submit"
                disabled={isLoading}
                className="w-full py-4 bg-gradient-to-r from-[#7c6fee] to-[#4ecdc4] rounded-xl font-medium hover:opacity-90 transition-opacity disabled:opacity-50 disabled:cursor-not-allowed flex items-center justify-center gap-2"
              >
                {isLoading ? (
                  <Loader2 className="w-5 h-5 animate-spin" />
                ) : (
                  <>
                    {mode === 'signup' ? 'Create Account & Continue' : 'Sign In & Continue'}
                    <ArrowRight className="w-5 h-5" />
                  </>
                )}
              </button>
            </form>
            
            <div className="mt-6 text-center">
              {mode === 'signup' ? (
                <p className="text-white/50 text-sm">
                  Already have an account?{' '}
                  <button
                    onClick={() => setMode('login')}
                    className="text-[#4ecdc4] hover:underline"
                  >
                    Sign in
                  </button>
                </p>
              ) : (
                <p className="text-white/50 text-sm">
                  {"Don't have an account?"}{' '}
                  <button
                    onClick={() => setMode('signup')}
                    className="text-[#4ecdc4] hover:underline"
                  >
                    Create one
                  </button>
                </p>
              )}
            </div>
          </div>
        )}

        {/* Step 2: Payment */}
        {step === 'payment' && (
          <div>
            <div className="text-center mb-8">
              <h2 className="text-2xl font-bold mb-2">Complete your subscription</h2>
              <p className="text-white/50">
                {isLoggedIn && email && (
                  <>Subscribing as <span className="text-white">{email}</span></>
                )}
              </p>
            </div>
            
            <div className="bg-[#1a1a2e] rounded-2xl border border-white/10 overflow-hidden">
              <Checkout productId={planId} />
            </div>
            
            <p className="text-center text-white/40 text-sm mt-6">
              Secure checkout powered by Stripe. Cancel anytime.
            </p>
          </div>
        )}
      </main>
    </div>
  )
}

export default function CheckoutPage() {
  return (
    <Suspense fallback={
      <div className="min-h-screen bg-[#0a0a0f] text-white flex items-center justify-center">
        <div className="text-center">
          <div className="w-8 h-8 border-2 border-white/20 border-t-white rounded-full animate-spin mx-auto mb-4" />
          <p className="text-white/50">Loading checkout...</p>
        </div>
      </div>
    }>
      <CheckoutContent />
    </Suspense>
  )
}
