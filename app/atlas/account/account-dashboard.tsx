"use client"

import { useState } from "react"
import { createClient } from "@/lib/supabase/client"
import { useRouter } from "next/navigation"
import Link from "next/link"
import Image from "next/image"
import type { User } from "@supabase/supabase-js"

interface Subscription {
  id: string
  plan: string
  status: string
  current_period_end: string
  cancel_at_period_end: boolean
  stripe_subscription_id: string
}

interface DeviceActivation {
  id: string
  device_name: string
  machine_uuid: string
  activated_at: string
  last_seen_at: string
}

interface AccountDashboardProps {
  user: User
  subscription: Subscription | null
  activations: DeviceActivation[]
}

export default function AccountDashboard({ user, subscription, activations }: AccountDashboardProps) {
  const [loading, setLoading] = useState<string | null>(null)
  const router = useRouter()
  const supabase = createClient()

  const handleSignOut = async () => {
    setLoading("signout")
    await supabase.auth.signOut()
    router.push("/")
    router.refresh()
  }

  const handleDeactivateDevice = async (machineUuid: string) => {
    setLoading(machineUuid)
    
    const { data: { session } } = await supabase.auth.getSession()
    if (!session) return

    try {
      const response = await fetch("/api/atlas/activate", {
        method: "DELETE",
        headers: {
          "Content-Type": "application/json",
          "Authorization": `Bearer ${session.access_token}`,
        },
        body: JSON.stringify({ machine_uuid: machineUuid }),
      })

      if (response.ok) {
        router.refresh()
      }
    } catch (error) {
      console.error("Failed to deactivate device:", error)
    }
    
    setLoading(null)
  }

  const maxDevices = subscription?.plan === "pro" ? 3 : 1
  const periodEnd = subscription?.current_period_end 
    ? new Date(subscription.current_period_end).toLocaleDateString("en-US", {
        year: "numeric",
        month: "long",
        day: "numeric",
      })
    : null

  return (
    <div className="min-h-screen bg-[#0a0a0f] text-white">
      {/* Header */}
      <header className="border-b border-white/5 bg-[#0a0a0f]/80 backdrop-blur-xl sticky top-0 z-50">
        <div className="max-w-5xl mx-auto px-4 sm:px-6 lg:px-8 py-4">
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
            <div className="flex items-center gap-4">
              <span className="text-sm text-white/50">{user.email}</span>
              <button
                onClick={handleSignOut}
                disabled={loading === "signout"}
                className="text-sm text-white/60 hover:text-white transition-colors disabled:opacity-50"
              >
                Sign Out
              </button>
            </div>
          </div>
        </div>
      </header>

      <main className="max-w-5xl mx-auto px-4 sm:px-6 lg:px-8 py-12">
        <h1 className="text-3xl font-bold mb-8">Account Dashboard</h1>

        <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
          {/* Subscription Card */}
          <div className="lg:col-span-2 bg-[#1a1a2e] rounded-2xl border border-white/10 p-6">
            <h2 className="text-lg font-semibold mb-4">Subscription</h2>
            
            {subscription ? (
              <div>
                <div className="flex items-center gap-3 mb-4">
                  <span className={`px-3 py-1 rounded-full text-sm font-medium ${
                    subscription.plan === "pro" 
                      ? "bg-gradient-to-r from-[#7c6fee] to-[#4ecdc4] text-white" 
                      : "bg-white/10 text-white/70"
                  }`}>
                    {subscription.plan === "pro" ? "Pro" : "Basic"}
                  </span>
                  <span className={`px-3 py-1 rounded-full text-sm ${
                    subscription.status === "active" 
                      ? "bg-green-500/20 text-green-400" 
                      : subscription.status === "past_due"
                      ? "bg-yellow-500/20 text-yellow-400"
                      : "bg-red-500/20 text-red-400"
                  }`}>
                    {subscription.status === "active" ? "Active" : 
                     subscription.status === "past_due" ? "Past Due" : 
                     subscription.status.charAt(0).toUpperCase() + subscription.status.slice(1)}
                  </span>
                </div>

                <div className="space-y-2 text-sm text-white/60 mb-6">
                  <p>
                    {subscription.cancel_at_period_end 
                      ? `Cancels on ${periodEnd}` 
                      : `Renews on ${periodEnd}`}
                  </p>
                  <p>
                    {subscription.plan === "pro" 
                      ? "$29.99/month" 
                      : "$14.99/month"}
                  </p>
                </div>

                <div className="flex flex-wrap gap-3">
                  {subscription.plan === "basic" && (
                    <Link
                      href="/atlas/checkout?plan=atlas-pro"
                      className="px-4 py-2 bg-gradient-to-r from-[#7c6fee] to-[#4ecdc4] rounded-lg text-sm font-medium hover:opacity-90 transition-opacity"
                    >
                      Upgrade to Pro
                    </Link>
                  )}
                  <a
                    href="https://billing.stripe.com/p/login/test_xxx"
                    target="_blank"
                    rel="noopener noreferrer"
                    className="px-4 py-2 border border-white/20 rounded-lg text-sm hover:bg-white/5 transition-colors"
                  >
                    Manage Billing
                  </a>
                </div>
              </div>
            ) : (
              <div className="text-center py-8">
                <p className="text-white/50 mb-4">No active subscription</p>
                <Link
                  href="/atlas#pricing"
                  className="inline-block px-6 py-3 bg-gradient-to-r from-[#7c6fee] to-[#4ecdc4] rounded-xl font-medium hover:opacity-90 transition-opacity"
                >
                  Subscribe to ATLAS
                </Link>
              </div>
            )}
          </div>

          {/* Download Card */}
          <div className="bg-[#1a1a2e] rounded-2xl border border-white/10 p-6">
            <h2 className="text-lg font-semibold mb-4">Download</h2>
            
            {subscription && subscription.status === "active" ? (
              <div className="space-y-4">
                <a
                  href="/downloads/ATLAS-latest.dmg"
                  className="flex items-center gap-3 p-4 bg-[#0a0a0f] rounded-xl border border-white/5 hover:border-[#7c6fee]/30 transition-colors group"
                >
                  <div className="w-10 h-10 rounded-lg bg-white/5 flex items-center justify-center group-hover:bg-[#7c6fee]/20 transition-colors">
                    <svg className="w-5 h-5" viewBox="0 0 24 24" fill="currentColor">
                      <path d="M18.71 19.5c-.83 1.24-1.71 2.45-3.05 2.47-1.34.03-1.77-.79-3.29-.79-1.53 0-2 .77-3.27.82-1.31.05-2.3-1.32-3.14-2.53C4.25 17 2.94 12.45 4.7 9.39c.87-1.52 2.43-2.48 4.12-2.51 1.28-.02 2.5.87 3.29.87.78 0 2.26-1.07 3.81-.91.65.03 2.47.26 3.64 1.98-.09.06-2.17 1.28-2.15 3.81.03 3.02 2.65 4.03 2.68 4.04-.03.07-.42 1.44-1.38 2.83M13 3.5c.73-.83 1.94-1.46 2.94-1.5.13 1.17-.34 2.35-1.04 3.19-.69.85-1.83 1.51-2.95 1.42-.15-1.15.41-2.35 1.05-3.11z"/>
                    </svg>
                  </div>
                  <div>
                    <p className="font-medium">macOS</p>
                    <p className="text-xs text-white/40">Intel & Apple Silicon</p>
                  </div>
                </a>
                <p className="text-xs text-white/40 text-center">
                  Windows coming soon
                </p>
              </div>
            ) : (
              <p className="text-white/50 text-sm">
                Subscribe to download ATLAS
              </p>
            )}
          </div>
        </div>

        {/* Devices Section */}
        <div className="mt-6 bg-[#1a1a2e] rounded-2xl border border-white/10 p-6">
          <div className="flex items-center justify-between mb-4">
            <h2 className="text-lg font-semibold">Activated Devices</h2>
            <span className="text-sm text-white/50">
              {activations.length} / {maxDevices} devices
            </span>
          </div>

          {activations.length > 0 ? (
            <div className="space-y-3">
              {activations.map((device) => (
                <div 
                  key={device.id}
                  className="flex items-center justify-between p-4 bg-[#0a0a0f] rounded-xl border border-white/5"
                >
                  <div className="flex items-center gap-3">
                    <div className="w-10 h-10 rounded-lg bg-white/5 flex items-center justify-center">
                      <svg className="w-5 h-5 text-white/60" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9.75 17L9 20l-1 1h8l-1-1-.75-3M3 13h18M5 17h14a2 2 0 002-2V5a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z" />
                      </svg>
                    </div>
                    <div>
                      <p className="font-medium">{device.device_name || "Unknown Device"}</p>
                      <p className="text-xs text-white/40">
                        Activated {new Date(device.activated_at).toLocaleDateString()}
                      </p>
                    </div>
                  </div>
                  <button
                    onClick={() => handleDeactivateDevice(device.machine_uuid)}
                    disabled={loading === device.machine_uuid}
                    className="text-sm text-red-400 hover:text-red-300 transition-colors disabled:opacity-50"
                  >
                    {loading === device.machine_uuid ? "Removing..." : "Remove"}
                  </button>
                </div>
              ))}
            </div>
          ) : (
            <p className="text-white/50 text-sm py-4 text-center">
              No devices activated yet. Download ATLAS and sign in to activate.
            </p>
          )}
        </div>

        {/* Plan Features */}
        {subscription && (
          <div className="mt-6 bg-[#1a1a2e] rounded-2xl border border-white/10 p-6">
            <h2 className="text-lg font-semibold mb-4">Your Plan Features</h2>
            <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
              <FeatureItem 
                label="Installations" 
                value={subscription.plan === "pro" ? "Unlimited" : "3 per day"} 
              />
              <FeatureItem 
                label="Devices" 
                value={subscription.plan === "pro" ? "Up to 3" : "1 device"} 
              />
              <FeatureItem 
                label="Bulk Queue" 
                value={subscription.plan === "pro" ? "Enabled" : "Disabled"} 
                enabled={subscription.plan === "pro"}
              />
              <FeatureItem 
                label="Uninstall Manager" 
                value={subscription.plan === "pro" ? "Enabled" : "Disabled"} 
                enabled={subscription.plan === "pro"}
              />
              <FeatureItem 
                label="Recovery System" 
                value={subscription.plan === "pro" ? "Enabled" : "Disabled"} 
                enabled={subscription.plan === "pro"}
              />
            </div>
          </div>
        )}
      </main>
    </div>
  )
}

function FeatureItem({ label, value, enabled = true }: { label: string; value: string; enabled?: boolean }) {
  return (
    <div className="p-4 bg-[#0a0a0f] rounded-xl border border-white/5">
      <p className="text-xs text-white/40 mb-1">{label}</p>
      <p className={`font-medium ${enabled ? "text-white" : "text-white/40"}`}>{value}</p>
    </div>
  )
}
