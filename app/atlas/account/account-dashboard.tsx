"use client"

import { useState } from "react"
import { createClient } from "@/lib/supabase/client"
import { useRouter } from "next/navigation"
import Link from "next/link"
import type { User } from "@supabase/supabase-js"

interface Subscription {
  id: string
  plan: string
  status: string
  current_period_end: string | null
  cancel_at_period_end: boolean
  stripe_subscription_id: string | null
}

interface Profile {
  plan: string
  subscription_status: string
}

interface Device {
  id: string
  device_name: string
  hardware_uuid: string
  last_seen: string
  created_at: string
}

interface Props {
  user: User
  subscription: Subscription | null
  profile: Profile | null
  devices: Device[]
}

export default function AccountDashboard({ user, subscription, profile, devices }: Props) {
  const [loading, setLoading] = useState<string | null>(null)
  const [showCancelConfirm, setShowCancelConfirm] = useState(false)
  const [cancelError, setCancelError] = useState("")
  const [emailNotifs, setEmailNotifs] = useState(true)
  const router = useRouter()
  const supabase = createClient()

  const isPro = profile?.plan === "pro" || subscription?.plan === "pro"
  const isActive = profile?.subscription_status === "active"
    || subscription?.status === "active"
    || subscription?.status === "trialing"
  const isCancelled = profile?.subscription_status === "cancelled"
    || subscription?.status === "canceled"
  const isPastDue = profile?.subscription_status === "payment_failed"
    || subscription?.status === "past_due"

  const maxDevices = isPro ? 3 : 1
  const planName = isPro ? "Pro" : "Standard"
  const planPrice = isPro ? "$29.99" : "$14.99"
  const periodEnd = subscription?.current_period_end
    ? new Date(subscription.current_period_end).toLocaleDateString("en-US", {
        year: "numeric", month: "long", day: "numeric",
      })
    : null

  const statusColor = isCancelled ? "text-red-400 bg-red-500/15"
    : isPastDue    ? "text-yellow-400 bg-yellow-500/15"
    : isActive     ? "text-emerald-400 bg-emerald-500/15"
    : "text-white/40 bg-white/10"

  const statusLabel = isCancelled ? "Cancelled"
    : isPastDue    ? "Payment Failed"
    : isActive     ? "Active"
    : "Inactive"

  async function handleSignOut() {
    setLoading("signout")
    await supabase.auth.signOut()
    router.push("/")
  }

  async function handleCancelSubscription() {
    setLoading("cancel")
    setCancelError("")
    const { data: { session } } = await supabase.auth.getSession()
    if (!session) { setLoading(null); return }
    try {
      const res = await fetch("/api/atlas/cancel", {
        method: "POST",
        headers: { Authorization: `Bearer ${session.access_token}` },
      })
      const json = await res.json()
      if (!res.ok) throw new Error(json.error || "Failed to cancel")
      await supabase.auth.signOut()
      router.push("/atlas?cancelled=1")
    } catch (err: unknown) {
      setCancelError(err instanceof Error ? err.message : "Unknown error")
      setLoading(null)
    }
    setShowCancelConfirm(false)
  }

  async function handleRemoveDevice(deviceId: string) {
    setLoading(deviceId)
    const { error } = await supabase
      .from("devices")
      .delete()
      .eq("id", deviceId)
      .eq("user_id", user.id)
    if (!error) router.refresh()
    setLoading(null)
  }

  return (
    <div className="min-h-screen bg-[#07080F] text-white">

      {/* Header */}
      <header className="border-b border-white/[0.06] sticky top-0 z-50 bg-[#07080F]/90 backdrop-blur-xl">
        <div className="max-w-4xl mx-auto px-6 py-4 flex items-center justify-between">
          <Link href="/atlas" className="flex items-center gap-2">
            <span className="text-[16px] font-semibold tracking-[0.25em] text-white/90"
              style={{ fontFamily: "'Bezmiar', sans-serif", fontWeight: 'normal' }}>ATLAS</span>
            <span className="text-[11px] text-white/30 ml-1">by InterLinked</span>
          </Link>
          <div className="flex items-center gap-4">
            <span className="text-[12px] text-white/40 hidden sm:block">{user.email}</span>
            <button onClick={handleSignOut} disabled={loading === "signout"}
              className="text-[12px] text-white/50 hover:text-white transition-colors">
              Sign Out
            </button>
          </div>
        </div>
      </header>

      <main className="max-w-4xl mx-auto px-6 py-10 space-y-5">

        <h1 className="text-[22px] font-bold tracking-tight">Account</h1>

        {/* ── Subscription ── */}
        <section className="bg-[#111220] rounded-2xl border border-white/[0.07] overflow-hidden">
          <div className="px-6 pt-5 pb-4 border-b border-white/[0.06]">
            <p className="text-[11px] font-semibold tracking-[0.1em] uppercase text-white/30 mb-3">Subscription</p>
            <div className="flex items-start justify-between gap-4">
              <div>
                <div className="flex items-center gap-2.5 mb-1">
                  <span className={`text-[20px] font-bold ${isPro ? "text-[#F0A030]" : "text-[#5B8DEF]"}`}>
                    ATLAS {planName}
                  </span>
                  <span className={`text-[11px] font-semibold px-2.5 py-0.5 rounded-full ${statusColor}`}>
                    {statusLabel}
                  </span>
                </div>
                <p className="text-[13px] text-white/40">
                  {planPrice}/month
                  {periodEnd && !isCancelled && (
                    <> · {subscription?.cancel_at_period_end ? "Cancels" : "Renews"} {periodEnd}</>
                  )}
                  {isCancelled && " · Access ended"}
                </p>
              </div>
              <div className={`shrink-0 px-3 py-1 rounded-lg text-[11px] font-black tracking-[0.15em] border ${
                isPro
                  ? "border-[#F0A030]/30 bg-[#F0A030]/08 text-[#F0A030]"
                  : "border-[#5B8DEF]/30 bg-[#5B8DEF]/08 text-[#5B8DEF]"
              }`}>{planName.toUpperCase()}</div>
            </div>
          </div>
          <div className="px-6 py-4 flex flex-wrap items-center gap-3">
            {!isPro && isActive && (
              <Link href="/atlas/checkout?plan=pro"
                className="inline-flex items-center gap-1.5 px-4 py-2 rounded-lg bg-gradient-to-r from-[#F0A030] to-[#E07820] text-[#07080F] text-[12px] font-bold hover:opacity-90 transition-opacity">
                ↑ Upgrade to Pro
              </Link>
            )}
            {isCancelled && (
              <Link href="/atlas"
                className="inline-flex items-center gap-1.5 px-4 py-2 rounded-lg bg-gradient-to-r from-[#3ECFB2] to-[#2ABEAA] text-[#07080F] text-[12px] font-bold hover:opacity-90 transition-opacity">
                ↺ Re-subscribe
              </Link>
            )}
            {isActive && !isCancelled && (
              <button onClick={() => setShowCancelConfirm(true)}
                className="px-4 py-2 rounded-lg border border-red-500/25 text-red-400 text-[12px] hover:bg-red-500/08 transition-colors">
                Cancel Subscription
              </button>
            )}
            {cancelError && <p className="text-[11px] text-red-400">{cancelError}</p>}
          </div>
        </section>

        {/* ── Plan Features ── */}
        <section className="bg-[#111220] rounded-2xl border border-white/[0.07] p-6">
          <p className="text-[11px] font-semibold tracking-[0.1em] uppercase text-white/30 mb-4">Your Plan Features</p>
          <div className="grid grid-cols-2 sm:grid-cols-3 gap-3">
            <FeatureCell label="Devices" value={isPro ? "Up to 3" : "1 device"} active />
            <FeatureCell label="Daily Installs" value={isPro ? "Unlimited" : "3 per day"} active />
            <FeatureCell label="Bulk Queue" value={isPro ? "Enabled" : "Unavailable"} active={isPro} />
            <FeatureCell label="Uninstall & Rollback" value={isPro ? "Enabled" : "Unavailable"} active={isPro} />
            <FeatureCell label="TITAN CORE™" value={isPro ? "Enabled" : "Unavailable"} active={isPro} />
            <FeatureCell label="Smart Storage" value={isPro ? "Enabled" : "Unavailable"} active={isPro} />
          </div>
          {!isPro && isActive && (
            <div className="mt-4 p-3 rounded-xl bg-[#F0A030]/06 border border-[#F0A030]/15">
              <p className="text-[12px] text-[#F0A030]/80">
                Upgrade to <strong>Pro</strong> for unlimited installs, bulk queue, TITAN CORE™, rollback, and up to 3 devices.
              </p>
            </div>
          )}
        </section>

        {/* ── Activated Devices ── */}
        <section className="bg-[#111220] rounded-2xl border border-white/[0.07] overflow-hidden">
          <div className="px-6 pt-5 pb-4 border-b border-white/[0.06]">
            <div className="flex items-center justify-between mb-1">
              <p className="text-[11px] font-semibold tracking-[0.1em] uppercase text-white/30">
                Activated Devices
              </p>
              <div className="flex items-center gap-2">
                <div className="flex gap-1">
                  {Array.from({ length: maxDevices }).map((_, i) => (
                    <div key={i} className={`w-2 h-2 rounded-full ${
                      i < devices.length
                        ? isPro ? "bg-[#F0A030]" : "bg-[#5B8DEF]"
                        : "bg-white/10"
                    }`} />
                  ))}
                </div>
                <span className="text-[12px] text-white/40 font-semibold">
                  {devices.length} / {maxDevices}
                </span>
              </div>
            </div>
            <p className="text-[11px] text-white/25 mt-1">
              Each device is identified by its unique Mac hardware ID.
              {devices.length >= maxDevices && (
                <span className="text-yellow-400/70"> Limit reached — remove a device to activate a new one.</span>
              )}
            </p>
          </div>

          <div className="divide-y divide-white/[0.04]">
            {devices.length === 0 ? (
              <div className="px-6 py-8 text-center">
                <p className="text-[13px] text-white/30">No devices activated yet.</p>
                <p className="text-[12px] text-white/20 mt-1">Download ATLAS and sign in to activate this Mac.</p>
              </div>
            ) : (
              devices.map((device, idx) => (
                <div key={device.id} className="px-6 py-4 flex items-start gap-4">
                  {/* Mac icon */}
                  <div className="w-9 h-9 rounded-lg bg-white/[0.05] flex items-center justify-center shrink-0 mt-0.5">
                    <svg className="w-4 h-4 text-white/40" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={1.5}>
                      <path strokeLinecap="round" strokeLinejoin="round" d="M9 17.25v1.007a3 3 0 01-.879 2.122L7.5 21h9l-.621-.621A3 3 0 0115 18.257V17.25m6-12V15a2.25 2.25 0 01-2.25 2.25H5.25A2.25 2.25 0 013 15V5.25A2.25 2.25 0 015.25 3h13.5A2.25 2.25 0 0121 5.25z" />
                    </svg>
                  </div>
                  {/* Device info */}
                  <div className="flex-1 min-w-0">
                    <div className="flex items-center gap-2">
                      <p className="text-[13px] font-medium truncate">{device.device_name || "Unknown Mac"}</p>
                      {idx === 0 && devices.length > 0 && (
                        <span className="shrink-0 text-[9px] font-bold px-1.5 py-0.5 rounded bg-white/[0.06] text-white/30 tracking-wide">
                          MOST RECENT
                        </span>
                      )}
                    </div>
                    <p className="text-[11px] text-white/30 mt-0.5 font-mono">
                      ID: {device.hardware_uuid.slice(0, 8).toUpperCase()}···
                    </p>
                    <p className="text-[11px] text-white/25 mt-0.5">
                      Last active {new Date(device.last_seen).toLocaleDateString("en-US", {
                        month: "short", day: "numeric", year: "numeric"
                      })}
                      {" · "}Registered {new Date(device.created_at).toLocaleDateString("en-US", {
                        month: "short", day: "numeric", year: "numeric"
                      })}
                    </p>
                  </div>
                  {/* Remove button */}
                  <button
                    onClick={() => handleRemoveDevice(device.id)}
                    disabled={loading === device.id}
                    className="shrink-0 text-[12px] text-white/20 hover:text-red-400 transition-colors disabled:opacity-40 mt-0.5"
                  >
                    {loading === device.id ? "Removing…" : "Remove"}
                  </button>
                </div>
              ))
            )}
          </div>

          {/* How it works note */}
          <div className="px-6 py-3 border-t border-white/[0.04] bg-white/[0.01]">
            <p className="text-[10px] text-white/20 leading-relaxed">
              When you sign in to ATLAS, your Mac&apos;s hardware identifier is registered here.
              ATLAS will not open on a new Mac if your plan&apos;s device limit is reached.
              Remove an existing device to free up a slot.
            </p>
          </div>
        </section>

        {/* ── Notifications ── */}
        <section className="bg-[#111220] rounded-2xl border border-white/[0.07] p-6">
          <p className="text-[11px] font-semibold tracking-[0.1em] uppercase text-white/30 mb-4">Notifications</p>
          <div className="space-y-3">
            <NotifRow label="Renewal reminders" description="Email when your subscription renews"
              enabled={emailNotifs} onChange={setEmailNotifs} />
            <NotifRow label="Payment alerts" description="Email if a payment fails"
              enabled={true} onChange={() => {}} locked />
          </div>
        </section>

        {/* ── Download ── */}
        <section className="bg-[#111220] rounded-2xl border border-white/[0.07] p-6">
          <p className="text-[11px] font-semibold tracking-[0.1em] uppercase text-white/30 mb-4">Download ATLAS</p>
          {isActive && !isCancelled ? (
            <a href="/downloads/ATLAS-latest.dmg"
              className="flex items-center gap-4 p-4 bg-white/[0.03] rounded-xl border border-white/[0.06] hover:border-white/[0.12] transition-colors group">
              <div className="w-10 h-10 rounded-xl bg-[#3ECFB2]/10 flex items-center justify-center">
                <svg className="w-5 h-5 text-[#3ECFB2]" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
                  <path strokeLinecap="round" strokeLinejoin="round" d="M3 16.5v2.25A2.25 2.25 0 005.25 21h13.5A2.25 2.25 0 0021 18.75V16.5M16.5 12L12 16.5m0 0L7.5 12m4.5 4.5V3" />
                </svg>
              </div>
              <div>
                <p className="text-[13px] font-semibold">ATLAS for macOS</p>
                <p className="text-[11px] text-white/35">Universal · Intel &amp; Apple Silicon</p>
              </div>
              <svg className="w-4 h-4 text-white/20 group-hover:text-white/50 transition-colors ml-auto" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
                <path strokeLinecap="round" strokeLinejoin="round" d="M13.5 4.5L21 12m0 0l-7.5 7.5M21 12H3" />
              </svg>
            </a>
          ) : (
            <p className="text-[13px] text-white/30">
              {isCancelled ? "Re-subscribe to download ATLAS." : "Subscribe to download ATLAS."}
            </p>
          )}
        </section>

        {/* Footer */}
        <div className="flex items-center justify-between pt-2 pb-8">
          <p className="text-[11px] text-white/20">InterLinked© · All rights reserved</p>
          <button onClick={handleSignOut} disabled={loading === "signout"}
            className="text-[12px] text-white/30 hover:text-red-400 transition-colors">
            Sign Out
          </button>
        </div>
      </main>

      {/* Cancel confirmation modal */}
      {showCancelConfirm && (
        <div className="fixed inset-0 bg-black/70 backdrop-blur-sm z-50 flex items-center justify-center p-4">
          <div className="bg-[#111220] border border-white/10 rounded-2xl w-full max-w-sm p-6 shadow-2xl">
            <div className="w-10 h-10 rounded-xl bg-red-500/10 flex items-center justify-center mb-4">
              <svg className="w-5 h-5 text-red-400" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
                <path strokeLinecap="round" strokeLinejoin="round" d="M12 9v3.75m-9.303 3.376c-.866 1.5.217 3.374 1.948 3.374h14.71c1.73 0 2.813-1.874 1.948-3.374L13.949 3.378c-.866-1.5-3.032-1.5-3.898 0L2.697 16.126zM12 15.75h.007v.008H12v-.008z" />
              </svg>
            </div>
            <h2 className="text-[16px] font-bold mb-1">Cancel subscription?</h2>
            <p className="text-[13px] text-white/50 mb-5">
              Your subscription will be cancelled <strong className="text-white/70">immediately</strong>.
              You will lose access to ATLAS. You can re-subscribe at any time.
            </p>
            <div className="flex gap-3">
              <button onClick={() => setShowCancelConfirm(false)}
                className="flex-1 py-2.5 rounded-xl border border-white/10 text-[13px] hover:bg-white/05 transition-colors">
                Keep Subscription
              </button>
              <button onClick={handleCancelSubscription} disabled={loading === "cancel"}
                className="flex-1 py-2.5 rounded-xl bg-red-500/80 text-white text-[13px] font-semibold hover:bg-red-500 transition-colors disabled:opacity-50">
                {loading === "cancel" ? "Cancelling…" : "Yes, Cancel"}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}

function FeatureCell({ label, value, active }: { label: string; value: string; active: boolean }) {
  return (
    <div className={`p-3.5 rounded-xl border ${active ? "bg-white/[0.03] border-white/[0.07]" : "bg-white/[0.01] border-white/[0.03]"}`}>
      <p className="text-[10px] text-white/35 mb-1">{label}</p>
      <p className={`text-[13px] font-semibold ${active ? "text-white" : "text-white/25"}`}>{value}</p>
    </div>
  )
}

function NotifRow({ label, description, enabled, onChange, locked }: {
  label: string; description: string; enabled: boolean; onChange: (v: boolean) => void; locked?: boolean
}) {
  return (
    <div className="flex items-center justify-between gap-4 py-1">
      <div>
        <p className="text-[13px] font-medium">{label}</p>
        <p className="text-[11px] text-white/35">{description}</p>
      </div>
      {locked ? (
        <span className="text-[10px] text-white/25 font-medium">Always on</span>
      ) : (
        <button onClick={() => onChange(!enabled)}
          className={`relative shrink-0 rounded-full transition-colors ${enabled ? "bg-[#3ECFB2]" : "bg-white/10"}`}
          style={{ width: 40, height: 22 }}>
          <span className={`absolute top-0.5 bg-white rounded-full shadow transition-transform ${enabled ? "translate-x-[18px]" : "translate-x-0.5"}`}
            style={{ width: 18, height: 18 }} />
        </button>
      )}
    </div>
  )
}
