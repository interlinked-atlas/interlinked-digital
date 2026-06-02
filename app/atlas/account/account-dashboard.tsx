"use client"

import { useState } from "react"
import { createClient } from "@/lib/supabase/client"
import { useRouter } from "next/navigation"
import Link from "next/link"
import type { User } from "@supabase/supabase-js"

interface Subscription {
  id: string; plan: string; status: string
  current_period_end: string | null
  cancel_at_period_end: boolean
  stripe_subscription_id: string | null
}
interface Profile { plan: string; subscription_status: string }
interface Device {
  id: string; device_name: string; hardware_uuid: string
  last_seen: string; created_at: string
}
interface LogEntry {
  id: string; log_type: string; app_name: string | null
  filename: string; content: string
  device_name: string | null; hardware_uuid: string | null
  created_at: string
}
interface Props {
  user: User
  subscription: Subscription | null
  profile: Profile | null
  devices: Device[]
  logs: LogEntry[]
  isAdmin: boolean
}

export default function AccountDashboard({ user, subscription, profile, devices, logs, isAdmin }: Props) {
  const [loading, setLoading] = useState<string | null>(null)
  const [showCancelConfirm, setShowCancelConfirm] = useState(false)
  const [cancelError, setCancelError] = useState("")
  const [emailNotifs, setEmailNotifs] = useState(true)
  const [expandedLog, setExpandedLog] = useState<string | null>(null)
  const router = useRouter()
  const supabase = createClient()

  const isPro = profile?.plan === "pro" || subscription?.plan === "pro"
  const isActive = profile?.subscription_status === "active" || subscription?.status === "active" || subscription?.status === "trialing"
  const isCancelled = profile?.subscription_status === "cancelled" || subscription?.status === "canceled"
  const isPastDue = profile?.subscription_status === "payment_failed" || subscription?.status === "past_due"
  const maxDevices = isPro ? 3 : 1
  const planName = isPro ? "Pro" : "Standard"
  const planPrice = isPro ? "$29.99" : "$14.99"
  const periodEnd = subscription?.current_period_end
    ? new Date(subscription.current_period_end).toLocaleDateString("en-US", { year: "numeric", month: "long", day: "numeric" })
    : null
  const statusColor = isCancelled ? "text-red-400 bg-red-500/15" : isPastDue ? "text-yellow-400 bg-yellow-500/15" : isActive ? "text-emerald-400 bg-emerald-500/15" : "text-white/40 bg-white/10"
  const statusLabel = isCancelled ? "Cancelled" : isPastDue ? "Payment Failed" : isActive ? "Active" : "Inactive"

  async function handleSignOut() {
    setLoading("signout")
    await supabase.auth.signOut()
    router.push("/")
  }

  async function handleCancelSubscription() {
    setLoading("cancel"); setCancelError("")
    const { data: { session } } = await supabase.auth.getSession()
    if (!session) { setLoading(null); return }
    try {
      const res = await fetch("/api/atlas/cancel", { method: "POST", headers: { Authorization: `Bearer ${session.access_token}` } })
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
    const { error } = await supabase.from("devices").delete().eq("id", deviceId).eq("user_id", user.id)
    if (!error) router.refresh()
    setLoading(null)
  }

  const logTypeColor = (t: string) => t === "install" ? "#3ECFB2" : t === "failed" ? "#E05555" : t === "uninstall" ? "#5B8DEF" : "#F0A030"
  const logTypeBg   = (t: string) => t === "install" ? "rgba(62,207,178,0.08)" : t === "failed" ? "rgba(224,85,85,0.08)" : t === "uninstall" ? "rgba(91,141,239,0.08)" : "rgba(240,160,48,0.08)"

  return (
    <div className="min-h-screen" style={{ background: "#07080F", color: "#E8ECFF" }}>
      {/* ── Header ── */}
      <header style={{
        borderBottom: "1px solid #1E2240", position: "sticky", top: 0, zIndex: 50,
        background: "rgba(7,8,15,0.92)", backdropFilter: "blur(12px)",
      }}>
        <div style={{ maxWidth: "900px", margin: "0 auto", padding: "14px 24px", display: "flex", alignItems: "center", justifyContent: "space-between" }}>
          <Link href="/atlas" style={{ display: "flex", alignItems: "center", gap: "10px", textDecoration: "none" }}>
            <span className="atlas-text" style={{ fontSize: "18px", letterSpacing: "6px" }}>ATLAS</span>
            <span style={{ fontSize: "10px", color: "#252845", letterSpacing: "2px" }}>by InterLinked</span>
          </Link>
          <div style={{ display: "flex", alignItems: "center", gap: "16px" }}>
            {isAdmin && (
              <Link href="/atlas/admin" style={{
                fontSize: "9px", letterSpacing: "2px", color: "#F0A030",
                textDecoration: "none", padding: "4px 10px",
                border: "1px solid rgba(240,160,48,0.3)", borderRadius: "5px",
                background: "rgba(240,160,48,0.06)",
              }}>ADMIN</Link>
            )}
            <span style={{ fontSize: "11px", color: "#4A5280" }}>{user.email}</span>
            <button onClick={handleSignOut} disabled={loading === "signout"}
              style={{ fontSize: "11px", color: "#353860", background: "none", border: "none", cursor: "pointer" }}>
              Sign Out
            </button>
          </div>
        </div>
      </header>

      <main style={{ maxWidth: "900px", margin: "0 auto", padding: "32px 24px", display: "flex", flexDirection: "column", gap: "16px" }}>
        <h1 style={{ fontSize: "20px", fontWeight: 600, color: "#C0C8E8", marginBottom: "4px" }}>Account</h1>

        {/* ── Subscription ── */}
        <section style={{ background: "#0C0E1C", borderRadius: "14px", border: "1px solid #1E2240", overflow: "hidden" }}>
          <div style={{ padding: "18px 22px 14px", borderBottom: "1px solid #1A1D30" }}>
            <p style={{ fontSize: "10px", fontWeight: 700, letterSpacing: "2px", color: "#353860", textTransform: "uppercase", marginBottom: "10px" }}>Subscription</p>
            <div style={{ display: "flex", alignItems: "flex-start", justifyContent: "space-between", gap: "16px" }}>
              <div>
                <div style={{ display: "flex", alignItems: "center", gap: "10px", marginBottom: "4px" }}>
                  <span style={{ fontSize: "18px", fontWeight: 700, color: isPro ? "#F0A030" : "#5B8DEF" }}>
                    <span className="atlas-text" style={{ fontSize: "14px", letterSpacing: "4px", marginRight: "6px" }}>ATLAS</span>{planName}
                  </span>
                  <span className={`text-[11px] font-semibold px-2.5 py-0.5 rounded-full ${statusColor}`}>{statusLabel}</span>
                </div>
                <p style={{ fontSize: "12px", color: "#6B7399" }}>
                  {planPrice}/month{periodEnd && !isCancelled && <> · {subscription?.cancel_at_period_end ? "Cancels" : "Renews"} {periodEnd}</>}{isCancelled && " · Access ended"}
                </p>
              </div>
              <div style={{
                padding: "4px 10px", borderRadius: "8px", fontSize: "10px", fontWeight: 800, letterSpacing: "2px",
                border: `1px solid ${isPro ? "rgba(240,160,48,0.3)" : "rgba(91,141,239,0.3)"}`,
                background: isPro ? "rgba(240,160,48,0.07)" : "rgba(91,141,239,0.07)",
                color: isPro ? "#F0A030" : "#5B8DEF",
              }}>{planName.toUpperCase()}</div>
            </div>
          </div>
          <div style={{ padding: "12px 22px", display: "flex", flexWrap: "wrap", gap: "10px", alignItems: "center" }}>
            {!isPro && isActive && (
              <Link href="/atlas/checkout?plan=pro" style={{
                display: "inline-flex", alignItems: "center", gap: "6px",
                padding: "8px 16px", borderRadius: "8px",
                background: "linear-gradient(135deg, #F0A030, #E07820)",
                color: "#07080F", fontSize: "11px", fontWeight: 700, textDecoration: "none",
              }}>↑ Upgrade to Pro</Link>
            )}
            {isCancelled && (
              <Link href="/atlas" style={{
                display: "inline-flex", alignItems: "center", gap: "6px",
                padding: "8px 16px", borderRadius: "8px",
                background: "linear-gradient(135deg, #3ECFB2, #2ABEAA)",
                color: "#07080F", fontSize: "11px", fontWeight: 700, textDecoration: "none",
              }}>↺ Re-subscribe</Link>
            )}
            {isActive && !isCancelled && (
              <button onClick={() => setShowCancelConfirm(true)} style={{
                padding: "8px 16px", borderRadius: "8px",
                border: "1px solid rgba(224,85,85,0.25)", color: "#E05555",
                fontSize: "11px", background: "none", cursor: "pointer",
              }}>Cancel Subscription</button>
            )}
            {cancelError && <p style={{ fontSize: "11px", color: "#E05555" }}>{cancelError}</p>}
          </div>
        </section>

        {/* ── Plan Features ── */}
        <section style={{ background: "#0C0E1C", borderRadius: "14px", border: "1px solid #1E2240", padding: "18px 22px" }}>
          <p style={{ fontSize: "10px", fontWeight: 700, letterSpacing: "2px", color: "#353860", textTransform: "uppercase", marginBottom: "14px" }}>Your Plan Features</p>
          <div style={{ display: "grid", gridTemplateColumns: "repeat(3, 1fr)", gap: "10px" }}>
            <FeatureCell label="Devices"            value={isPro ? "Up to 3" : "1 device"}   active />
            <FeatureCell label="Daily Installs"     value={isPro ? "Unlimited" : "3 per day"} active />
            <FeatureCell label="Bulk Queue"         value={isPro ? "Enabled" : "Unavailable"} active={isPro} />
            <FeatureCell label="Uninstall & Rollback" value={isPro ? "Enabled" : "Unavailable"} active={isPro} />
            <FeatureCell label="TITAN CORE™"        value={isPro ? "Enabled" : "Unavailable"} active={isPro} />
            <FeatureCell label="Smart Storage"      value={isPro ? "Enabled" : "Unavailable"} active={isPro} />
          </div>
          {!isPro && isActive && (
            <div style={{ marginTop: "12px", padding: "10px 14px", borderRadius: "10px", background: "rgba(240,160,48,0.05)", border: "1px solid rgba(240,160,48,0.15)" }}>
              <p style={{ fontSize: "12px", color: "rgba(240,160,48,0.8)" }}>
                Upgrade to <strong>Pro</strong> for unlimited installs, bulk queue, TITAN CORE™, rollback, and up to 3 devices.
              </p>
            </div>
          )}
        </section>

        {/* ── Activated Devices ── */}
        <section style={{ background: "#0C0E1C", borderRadius: "14px", border: "1px solid #1E2240", overflow: "hidden" }}>
          <div style={{ padding: "18px 22px 14px", borderBottom: "1px solid #1A1D30" }}>
            <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", marginBottom: "4px" }}>
              <p style={{ fontSize: "10px", fontWeight: 700, letterSpacing: "2px", color: "#353860", textTransform: "uppercase" }}>Activated Devices</p>
              <div style={{ display: "flex", alignItems: "center", gap: "8px" }}>
                <div style={{ display: "flex", gap: "4px" }}>
                  {Array.from({ length: maxDevices }).map((_, i) => (
                    <div key={i} style={{ width: "8px", height: "8px", borderRadius: "50%", background: i < devices.length ? (isPro ? "#F0A030" : "#5B8DEF") : "#1E2240" }} />
                  ))}
                </div>
                <span style={{ fontSize: "11px", color: "#4A5280", fontWeight: 600 }}>{devices.length} / {maxDevices}</span>
              </div>
            </div>
            <p style={{ fontSize: "11px", color: "#252845", marginTop: "2px" }}>
              Each device is identified by its unique Mac hardware ID.
              {devices.length >= maxDevices && <span style={{ color: "rgba(240,160,48,0.6)" }}> Limit reached — remove a device to activate a new one.</span>}
            </p>
          </div>
          <div>
            {devices.length === 0 ? (
              <div style={{ padding: "32px 22px", textAlign: "center" }}>
                <p style={{ fontSize: "13px", color: "#353860" }}>No devices activated yet.</p>
                <p style={{ fontSize: "11px", color: "#252845", marginTop: "4px" }}>Download ATLAS and sign in to activate this Mac.</p>
              </div>
            ) : devices.map((device, idx) => (
              <div key={device.id} style={{ padding: "14px 22px", display: "flex", alignItems: "flex-start", gap: "14px", borderBottom: "1px solid #0F1020" }}>
                <div style={{ width: "36px", height: "36px", borderRadius: "8px", background: "#0A0D1C", border: "1px solid #1E2240", display: "flex", alignItems: "center", justifyContent: "center", flexShrink: 0 }}>
                  <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="#4A5280" strokeWidth="1.5">
                    <path strokeLinecap="round" strokeLinejoin="round" d="M9 17.25v1.007a3 3 0 01-.879 2.122L7.5 21h9l-.621-.621A3 3 0 0115 18.257V17.25m6-12V15a2.25 2.25 0 01-2.25 2.25H5.25A2.25 2.25 0 013 15V5.25A2.25 2.25 0 015.25 3h13.5A2.25 2.25 0 0121 5.25z" />
                  </svg>
                </div>
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div style={{ display: "flex", alignItems: "center", gap: "8px" }}>
                    <p style={{ fontSize: "13px", fontWeight: 500, color: "#D0D8F0" }}>{device.device_name || "Unknown Mac"}</p>
                    {idx === 0 && <span style={{ fontSize: "8px", fontWeight: 800, letterSpacing: "1.5px", padding: "2px 6px", borderRadius: "3px", background: "#0A0D1C", border: "1px solid #1E2240", color: "#353860" }}>MOST RECENT</span>}
                  </div>
                  <p style={{ fontSize: "11px", color: "#353860", fontFamily: "monospace", marginTop: "2px" }}>
                    ID: {device.hardware_uuid.slice(0, 8).toUpperCase()}···
                  </p>
                  <p style={{ fontSize: "11px", color: "#252845", marginTop: "2px" }}>
                    Last active {new Date(device.last_seen).toLocaleDateString("en-US", { month: "short", day: "numeric", year: "numeric" })}
                    {" · "}Registered {new Date(device.created_at).toLocaleDateString("en-US", { month: "short", day: "numeric", year: "numeric" })}
                  </p>
                </div>
                <button onClick={() => handleRemoveDevice(device.id)} disabled={loading === device.id}
                  style={{ fontSize: "11px", color: "#252845", background: "none", border: "none", cursor: "pointer", flexShrink: 0, marginTop: "2px" }}
                  onMouseEnter={e => (e.currentTarget.style.color = "#E05555")}
                  onMouseLeave={e => (e.currentTarget.style.color = "#252845")}>
                  {loading === device.id ? "Removing…" : "Remove"}
                </button>
              </div>
            ))}
          </div>
          <div style={{ padding: "10px 22px", borderTop: "1px solid #0F1020", background: "rgba(255,255,255,0.005)" }}>
            <p style={{ fontSize: "10px", color: "#1E2240", lineHeight: 1.6 }}>
              When you sign in to ATLAS, your Mac&apos;s hardware identifier is registered here. ATLAS will not open on a new Mac if your plan&apos;s device limit is reached. Remove an existing device to free up a slot.
            </p>
          </div>
        </section>

        {/* ── Installation Logs ── */}
        <section style={{ background: "#0C0E1C", borderRadius: "14px", border: "1px solid #1E2240", overflow: "hidden" }}>
          <div style={{ padding: "18px 22px 14px", borderBottom: "1px solid #1A1D30" }}>
            <p style={{ fontSize: "10px", fontWeight: 700, letterSpacing: "2px", color: "#353860", textTransform: "uppercase", marginBottom: "4px" }}>Installation Logs</p>
            <p style={{ fontSize: "11px", color: "#252845" }}>
              Synced automatically from ATLAS · Most recent first
            </p>
          </div>
          {logs.length === 0 ? (
            <div style={{ padding: "32px 22px", textAlign: "center" }}>
              <p style={{ fontSize: "13px", color: "#353860" }}>No logs synced yet.</p>
              <p style={{ fontSize: "11px", color: "#252845", marginTop: "4px" }}>
                ATLAS syncs your installation logs automatically when you&apos;re connected.
              </p>
            </div>
          ) : (
            <div>
              {logs.map(log => (
                <div key={log.id} style={{ borderBottom: "1px solid #0F1020" }}>
                  {/* Log header row */}
                  <button
                    onClick={() => setExpandedLog(expandedLog === log.id ? null : log.id)}
                    style={{
                      width: "100%", padding: "12px 22px", background: "none", border: "none",
                      cursor: "pointer", display: "flex", alignItems: "center", gap: "10px", textAlign: "left",
                    }}
                  >
                    <span style={{
                      fontSize: "8px", fontWeight: 800, letterSpacing: "1.5px",
                      padding: "2px 7px", borderRadius: "3px", flexShrink: 0,
                      background: logTypeBg(log.log_type), color: logTypeColor(log.log_type),
                    }}>
                      {log.log_type.toUpperCase()}
                    </span>
                    <span style={{ fontSize: "12px", color: "#A8B4D0", flex: 1, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>
                      {log.app_name || log.filename}
                    </span>
                    {log.device_name && (
                      <span style={{ fontSize: "10px", color: "#252845", flexShrink: 0 }}>{log.device_name}</span>
                    )}
                    <span style={{ fontSize: "10px", color: "#252845", flexShrink: 0 }}>
                      {new Date(log.created_at).toLocaleDateString("en-US", { month: "short", day: "numeric" })}
                    </span>
                    <span style={{ fontSize: "10px", color: expandedLog === log.id ? "#3ECFB2" : "#252845", transition: "color 0.15s", flexShrink: 0 }}>
                      {expandedLog === log.id ? "▲" : "▼"}
                    </span>
                  </button>
                  {/* Expanded log content */}
                  {expandedLog === log.id && (
                    <pre style={{
                      margin: 0, padding: "14px 22px",
                      background: "#07080F", color: "#6B7399",
                      fontSize: "10px", lineHeight: 1.65,
                      overflowX: "auto", whiteSpace: "pre-wrap",
                      wordBreak: "break-word", maxHeight: "360px",
                      overflowY: "auto", borderTop: "1px solid #13151F",
                    }}>
                      {log.content}
                    </pre>
                  )}
                </div>
              ))}
            </div>
          )}
        </section>

        {/* ── Notifications ── */}
        <section style={{ background: "#0C0E1C", borderRadius: "14px", border: "1px solid #1E2240", padding: "18px 22px" }}>
          <p style={{ fontSize: "10px", fontWeight: 700, letterSpacing: "2px", color: "#353860", textTransform: "uppercase", marginBottom: "14px" }}>Notifications</p>
          <div style={{ display: "flex", flexDirection: "column", gap: "12px" }}>
            <NotifRow label="Renewal reminders" description="Email when your subscription renews" enabled={emailNotifs} onChange={setEmailNotifs} />
            <NotifRow label="Payment alerts" description="Email if a payment fails" enabled={true} onChange={() => {}} locked />
          </div>
        </section>

        {/* ── Download ── */}
        <section style={{ background: "#0C0E1C", borderRadius: "14px", border: "1px solid #1E2240", padding: "18px 22px" }}>
          <p style={{ fontSize: "10px", fontWeight: 700, letterSpacing: "2px", color: "#353860", textTransform: "uppercase", marginBottom: "14px" }}>Download ATLAS</p>
          {isActive && !isCancelled ? (
            <a href="/downloads/ATLAS-latest.dmg" style={{
              display: "flex", alignItems: "center", gap: "14px",
              padding: "14px 16px", background: "#07080F", borderRadius: "10px",
              border: "1px solid #1E2240", textDecoration: "none",
              transition: "border-color 0.15s",
            }}
            onMouseEnter={e => (e.currentTarget.style.borderColor = "rgba(62,207,178,0.3)")}
            onMouseLeave={e => (e.currentTarget.style.borderColor = "#1E2240")}>
              <div style={{ width: "40px", height: "40px", borderRadius: "10px", background: "rgba(62,207,178,0.08)", display: "flex", alignItems: "center", justifyContent: "center", flexShrink: 0 }}>
                <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="#3ECFB2" strokeWidth="2">
                  <path strokeLinecap="round" strokeLinejoin="round" d="M3 16.5v2.25A2.25 2.25 0 005.25 21h13.5A2.25 2.25 0 0021 18.75V16.5M16.5 12L12 16.5m0 0L7.5 12m4.5 4.5V3" />
                </svg>
              </div>
              <div>
                <p style={{ fontSize: "13px", fontWeight: 600, color: "#D0D8F0" }}>ATLAS for macOS</p>
                <p style={{ fontSize: "11px", color: "#353860", marginTop: "2px" }}>Universal · Intel &amp; Apple Silicon</p>
              </div>
            </a>
          ) : (
            <p style={{ fontSize: "13px", color: "#353860" }}>
              {isCancelled ? "Re-subscribe to download ATLAS." : "Subscribe to download ATLAS."}
            </p>
          )}
        </section>

        {/* Footer */}
        <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", paddingBottom: "32px", paddingTop: "8px" }}>
          <p style={{ fontSize: "10px", color: "#1A1D30", letterSpacing: "1px" }}>INTERLINKED© · ALL RIGHTS RESERVED</p>
          <button onClick={handleSignOut} disabled={loading === "signout"}
            style={{ fontSize: "11px", color: "#252845", background: "none", border: "none", cursor: "pointer" }}
            onMouseEnter={e => (e.currentTarget.style.color = "#E05555")}
            onMouseLeave={e => (e.currentTarget.style.color = "#252845")}>
            Sign Out
          </button>
        </div>
      </main>

      {/* ── Cancel confirmation modal ── */}
      {showCancelConfirm && (
        <div className="backdrop-enter" style={{
          position: "fixed", inset: 0, background: "rgba(0,0,0,0.75)", backdropFilter: "blur(6px)",
          zIndex: 50, display: "flex", alignItems: "center", justifyContent: "center", padding: "16px",
        }}>
          <div className="modal-enter" style={{
            background: "#0C0E1C", border: "1px solid #1E2240", borderRadius: "16px",
            width: "100%", maxWidth: "360px", padding: "24px", boxShadow: "0 24px 80px rgba(0,0,0,0.6)",
          }}>
            <div style={{ width: "40px", height: "40px", borderRadius: "10px", background: "rgba(224,85,85,0.1)", display: "flex", alignItems: "center", justifyContent: "center", marginBottom: "16px" }}>
              <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="#E05555" strokeWidth="2">
                <path strokeLinecap="round" strokeLinejoin="round" d="M12 9v3.75m-9.303 3.376c-.866 1.5.217 3.374 1.948 3.374h14.71c1.73 0 2.813-1.874 1.948-3.374L13.949 3.378c-.866-1.5-3.032-1.5-3.898 0L2.697 16.126zM12 15.75h.007v.008H12v-.008z" />
              </svg>
            </div>
            <h2 style={{ fontSize: "15px", fontWeight: 700, marginBottom: "6px", color: "#E8ECFF" }}>Cancel subscription?</h2>
            <p style={{ fontSize: "12px", color: "#6B7399", marginBottom: "20px", lineHeight: 1.6 }}>
              Your subscription will be cancelled <strong style={{ color: "#A8B4D0" }}>immediately</strong>. You will lose access to ATLAS. You can re-subscribe at any time.
            </p>
            <div style={{ display: "flex", gap: "10px" }}>
              <button onClick={() => setShowCancelConfirm(false)} style={{
                flex: 1, padding: "10px", borderRadius: "10px",
                border: "1px solid #1E2240", color: "#A8B4D0",
                fontSize: "12px", background: "none", cursor: "pointer",
              }}>Keep Subscription</button>
              <button onClick={handleCancelSubscription} disabled={loading === "cancel"} style={{
                flex: 1, padding: "10px", borderRadius: "10px",
                background: "rgba(224,85,85,0.8)", color: "#fff",
                fontSize: "12px", fontWeight: 600, border: "none", cursor: "pointer",
              }}>
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
    <div style={{
      padding: "12px 14px", borderRadius: "10px",
      background: active ? "#0A0D1C" : "transparent",
      border: `1px solid ${active ? "#1E2240" : "#0F1020"}`,
    }}>
      <p style={{ fontSize: "9px", color: "#353860", marginBottom: "4px", letterSpacing: "1px", textTransform: "uppercase" }}>{label}</p>
      <p style={{ fontSize: "12px", fontWeight: 600, color: active ? "#D0D8F0" : "#1E2240" }}>{value}</p>
    </div>
  )
}

function NotifRow({ label, description, enabled, onChange, locked }: {
  label: string; description: string; enabled: boolean; onChange: (v: boolean) => void; locked?: boolean
}) {
  return (
    <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", gap: "16px", padding: "4px 0" }}>
      <div>
        <p style={{ fontSize: "12px", fontWeight: 500, color: "#D0D8F0" }}>{label}</p>
        <p style={{ fontSize: "11px", color: "#353860", marginTop: "1px" }}>{description}</p>
      </div>
      {locked ? (
        <span style={{ fontSize: "9px", color: "#252845", letterSpacing: "1px" }}>ALWAYS ON</span>
      ) : (
        <button onClick={() => onChange(!enabled)}
          style={{
            position: "relative", flexShrink: 0, borderRadius: "11px",
            width: "40px", height: "22px", border: "none", cursor: "pointer",
            background: enabled ? "#3ECFB2" : "#1E2240",
            transition: "background 0.2s",
          }}>
          <span style={{
            position: "absolute", top: "2px", borderRadius: "50%", background: "#fff",
            width: "18px", height: "18px", transition: "transform 0.2s",
            transform: enabled ? "translateX(20px)" : "translateX(2px)",
          }} />
        </button>
      )}
    </div>
  )
}
