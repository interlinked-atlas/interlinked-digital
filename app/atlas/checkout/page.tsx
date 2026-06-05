'use client'

import { Suspense } from 'react'
import { useSearchParams } from 'next/navigation'
import Link from 'next/link'
import Image from 'next/image'
import Checkout from '@/components/checkout'
import { PRODUCTS } from '@/lib/products'

function CheckoutContent() {
  const searchParams = useSearchParams()
  const planId = searchParams.get('plan')
  
  const product = PRODUCTS.find(p => p.id === planId)
  
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
        <div className="text-center mb-8">
          <h1 className="text-3xl font-bold mb-2">Complete Your Subscription</h1>
          <p className="text-white/50">
            You&apos;re subscribing to <span className="text-white font-medium">{product.name}</span> at{' '}
            <span className="text-white font-medium">${(product.priceInCents / 100).toFixed(2)}/month</span>
          </p>
        </div>
        
        <div className="bg-[#1a1a2e] rounded-2xl border border-white/10 overflow-hidden">
          <Checkout productId={planId} />
        </div>
        
        <p className="text-center text-white/40 text-sm mt-6">
          Secure checkout powered by Stripe. Cancel anytime.
        </p>
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
