'use client'

import { Suspense, useEffect, useState } from 'react'
import { useSearchParams } from 'next/navigation'
import Link from 'next/link'
import Image from 'next/image'
import { PRODUCTS } from '@/lib/products'
import { startCheckoutSession } from '@/app/actions/stripe'

function CheckoutContent() {
  const searchParams = useSearchParams()
  const planId = searchParams.get('plan')
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState('')

  const product = PRODUCTS.find(p => p.id === planId)

  useEffect(() => {
    if (!planId || !product) return
    setLoading(true)
    startCheckoutSession(planId)
      .then(url => { window.location.href = url })
      .catch(err => {
        if (err.message === 'ALREADY_SUBSCRIBED') {
          window.location.href = '/atlas/account'
        } else {
          setError(err.message)
          setLoading(false)
        }
      })
  }, [planId])

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
    <div className="min-h-screen bg-[#0a0a0f] text-white flex items-center justify-center">
      <div className="text-center">
        {error ? (
          <>
            <p className="text-red-400 mb-4">{error}</p>
            <Link href="/atlas#pricing" className="text-white/60 hover:text-white underline text-sm">
              Back to Plans
            </Link>
          </>
        ) : (
          <>
            <div className="w-8 h-8 border-2 border-white/20 border-t-white rounded-full animate-spin mx-auto mb-4" />
            <p className="text-white/50">Redirecting to secure checkout…</p>
            <p className="text-white/30 text-sm mt-2">
              {product.name} — ${(product.priceInCents / 100).toFixed(2)}/month
            </p>
          </>
        )}
      </div>
    </div>
  )
}

export default function CheckoutPage() {
  return (
    <Suspense fallback={
      <div className="min-h-screen bg-[#0a0a0f] text-white flex items-center justify-center">
        <div className="w-8 h-8 border-2 border-white/20 border-t-white rounded-full animate-spin mx-auto" />
      </div>
    }>
      <CheckoutContent />
    </Suspense>
  )
}
