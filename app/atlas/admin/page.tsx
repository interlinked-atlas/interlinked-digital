"use client"

import { useState, useEffect } from "react"
import Link from "next/link"
import { useRouter } from "next/navigation"
import { createClient as createBrowserClient } from "@/lib/supabase/client"

const ADMIN_EMAIL = "titantinstaller@gmail.com"

type Tab = "subscribers" | "devices" | "logs" | "support" | "failures" | "patterns" | "recovery-kits" | "suspended" | "feedback"

const planColor    = (p: string) => p === "atlas" ? "#3ECFB2" : "var(--text-muted)"
const statusColor  = (s: string) => s === "active" ? "#3ECFB2" : s === "cancelled" || s === "canceled" ? "#E05555" : s === "past_due" ? "#F0A030" : "var(--text-muted)"
const logTypeColor = (t: string) => t === "install" ? "#3ECFB2" : t === "failed" ? "#E05555" : t === "uninstall" ? "#5B8DEF" : t === "confirmed-success" ? "#A855F7" : "#F0A030"
const logTypeBg    = (t: string) => t === "install" ? "rgba(62,207,178,0.1)" : t === "failed" ? "rgba(224,85,85,0.1)" : t === "uninstall" ? "rgba(91,141,239,0.1)" : t === "confirmed-success" ? "rgba(168,85,247,0.1)" : "rgba(240,160,48,0.1)"
const fixStatusColor = (s: string) => s === "fixed" ? "#3ECFB2" : s === "investigating" ? "#F0A030" : s === "wont_fix" ? "var(--text-muted)" : "#E05555"
const failTypeColor  = (t: string) => ({ pkg:"#E05555", script:"#F0A030", binary:"#F0A030", verify:"#5B8DEF", demo:"#F0A030", cancelled:"var(--text-muted)", scan:"#A855F7" } as any)[t] ?? "var(--text-muted)"

function fmt(d: string | null | undefined) {
  if (!d) return "—"
  return new Date(d).toLocaleDateString("en-US", { month: "short", day: "numeric", year: "numeric" })
}
function fmtShort(d: string | null | undefined) {
  if (!d) return "—"
  return new Date(d).toLocaleDateString("en-US", { month: "short", day: "numeric" })
}
function fmtDateTime(d: string | null | undefined) {
  if (!d) return "—"
  return new Date(d).toLocaleString("en-US", { month: "short", day: "numeric", year: "numeric", hour: "2-digit", minute: "2-digit" })
}

export default function AdminPage() {
  const [tab, setTab]             = useState<Tab>("subscribers")
  const [authed, setAuthed]       = useState(false)
  const [loading, setLoading]     = useState(true)
  const [users, setUsers]         = useState<any[]>([])
  const [subscriptions, setSubscriptions] = useState<any[]>([])
  const [devices, setDevices]     = useState<any[]>([])
  const [logs, setLogs]           = useState<any[]>([])
  const [tickets, setTickets]     = useState<any[]>([])
  const [failures, setFailures]   = useState<any[]>([])
  const [patterns, setPatterns]   = useState<any[]>([])
  const [auditLog, setAuditLog] = useState<any[]>([])
  const cancellationFeedback = auditLog.filter(a => a.event === 'subscription.cancellation_feedback')
  const [monthlyUsage, setMonthlyUsage] = useState<any[]>([])
  const [gateUsage, setGateUsage]       = useState<any[]>([])
  const [expandedTicket, setExpandedTicket]   = useState<string | null>(null)
  const [expandedUser, setExpandedUser]       = useState<string | null>(null)
  const [userProfileTab, setUserProfileTab]   = useState<Record<string, string>>({})
  const [expandedLog, setExpandedLog]         = useState<string | null>(null)
  const [expandedFailure, setExpandedFailure] = useState<string | null>(null)
  const [logFilter, setLogFilter]       = useState("all")
  const [failureFilter, setFailureFilter] = useState("all")
  const [subSearch, setSubSearch]       = useState("")
  const [userEmail, setUserEmail]       = useState("")

  const [limitInput, setLimitInput]   = useState<Record<string, string>>({})
  const [limitSavingId, setLimitSavingId] = useState<string | null>(null)
  const [resettingId, setResettingId]     = useState<string | null>(null)
  const [bulkLimitInput, setBulkLimitInput] = useState("")
  const [bulkSaving, setBulkSaving]         = useState(false)
  const [bulkResetting, setBulkResetting]   = useState(false)

  const [pushVersionInput, setPushVersionInput]   = useState<Record<string, string>>({})
  const [pushingId, setPushingId]                 = useState<string | null>(null)
  const [bulkPushVersionInput, setBulkPushVersionInput] = useState("")
  const [bulkPushing, setBulkPushing]             = useState(false)
  const [kickingDeviceId, setKickingDeviceId]     = useState<string | null>(null)
  const [suspendingId, setSuspendingId]           = useState<string | null>(null)
  const [grantingId, setGrantingId]               = useState<string | null>(null)
  const [resettingGraceId, setResettingGraceId]   = useState<string | null>(null)

  const [fixingId, setFixingId]   = useState<string | null>(null)
  const [fixNote, setFixNote]     = useState("")
  const [fixStatus, setFixStatus] = useState("investigating")
  const [fixSaving, setFixSaving] = useState(false)

  const [editingPattern, setEditingPattern] = useState<any | null>(null)
  const [newPattern, setNewPattern]         = useState(false)
  const [patternSaving, setPatternSaving]   = useState(false)
  const [patternDraft, setPatternDraft]     = useState<any>({})
  const [titanMemory, setTitanMemory]       = useState<any[]>([])
  const [promotingId, setPromotingId]       = useState<string | null>(null)
  const [toastMsg, setToastMsg]             = useState<string | null>(null)

  // Recovery Kits admin state
  const [rkSubscribers, setRkSubscribers]   = useState<any[]>([])
  const [rkSubscribersLoading, setRkSubscribersLoading] = useState(false)
  const [expandedRkUser, setExpandedRkUser] = useState<string | null>(null)
  const [rkUserKits, setRkUserKits]         = useState<Record<string, any[]>>({})
  const [rkUserKitsLoading, setRkUserKitsLoading] = useState<string | null>(null)
  const [rkDownloading, setRkDownloading]   = useState<string | null>(null)

  const router = useRouter()
  const supabase = createBrowserClient()

  useEffect(() => {
    supabase.auth.getUser().then(({ data: { user } }) => {
      if (!user || user.email?.toLowerCase() !== ADMIN_EMAIL.toLowerCase()) {
        router.replace("/atlas/account"); return
      }
      setUserEmail(user.email ?? "")
      setAuthed(true)
      loadAll()
    })
  }, [])

  async function authHeader() {
    const { data: { session } } = await supabase.auth.getSession()
    return { Authorization: `Bearer ${session?.access_token ?? ""}` }
  }

  useEffect(() => {
    if (tab === "recovery-kits" && rkSubscribers.length === 0 && !rkSubscribersLoading) {
      loadRkSubscribers()
    }
  }, [tab])

  async function loadRkSubscribers() {
    setRkSubscribersLoading(true)
    try {
      const headers = await authHeader()
      const res = await fetch("/api/atlas/recovery-kit/admin/subscribers", { headers })
      if (!res.ok) throw new Error(`HTTP ${res.status}`)
      const json = await res.json()
      setRkSubscribers(json.subscribers ?? [])
    } catch { /* silently fail */ } finally {
      setRkSubscribersLoading(false)
    }
  }

  async function loadRkUserKits(userId: string) {
    setRkUserKitsLoading(userId)
    try {
      const headers = await authHeader()
      const res = await fetch(`/api/atlas/recovery-kit/admin/kits?user_id=${userId}`, { headers })
      if (!res.ok) throw new Error(`HTTP ${res.status}`)
      const json = await res.json()
      setRkUserKits(prev => ({ ...prev, [userId]: json.kits ?? [] }))
    } catch { /* silently fail */ } finally {
      setRkUserKitsLoading(null)
    }
  }

  async function adminDownloadKit(kitId: string, fileType: "atlaskit" | "txt") {
    setRkDownloading(`${kitId}-${fileType}`)
    try {
      const headers = await authHeader()
      const res = await fetch(`/api/atlas/recovery-kit/admin/download?kit_id=${kitId}&file=${fileType}`, { headers })
      if (!res.ok) throw new Error(`HTTP ${res.status}`)
      const blob = await res.blob()
      const url = URL.createObjectURL(blob)
      const a = document.createElement("a")
      a.href = url
      a.download = fileType === "atlaskit" ? "kit.atlaskit" : "kit.txt"
      a.click()
      URL.revokeObjectURL(url)
    } catch { /* silently fail */ } finally {
      setRkDownloading(null)
    }
  }

  async function loadAll() {
    setLoading(true)
    const headers = await authHeader()
    const [profRes, subRes, devRes, logRes, tickRes, usageRes, gateRes, failRes, patRes, auditRes] = await Promise.all([
      supabase.from("profiles").select("id,email,plan,subscription_status,created_at,privacy_consent,billing_interval,billing_anchor_day,monthly_install_limit,atlas_forced_update_version,atlas_suspended,atlas_suspended_reason,grace_period_used_at").order("created_at", { ascending: false }),
      supabase.from("subscriptions").select("id,user_id,stripe_customer_id,stripe_subscription_id,plan,status,current_period_start,current_period_end,cancel_at_period_end,admin_granted_access,created_at,updated_at").order("created_at", { ascending: false }),
      supabase.from("devices").select("id,user_id,device_name,hardware_uuid,last_seen,created_at").order("last_seen", { ascending: false }),
      supabase.from("install_logs").select("id,user_id,app_name,log_type,filename,content,device_name,hardware_uuid,installed_at").order("installed_at", { ascending: false }).limit(500),
      supabase.from("support_tickets").select("id,user_id,email,issue_type,message,status,created_at,attached_log_content,product_name,product_status").order("created_at", { ascending: false }),
      supabase.from("monthly_install_counts").select("user_id,period_start,period_end,count").order("period_start", { ascending: false }),
      // install_counts is service-role-only at the database level (it's the live reservation-gate
      // table behind reserve_install_slot/etc) — read through the admin-authorized server route
      // instead of the anon-key client, which RLS would otherwise return nothing for.
      fetch("/api/atlas/admin/install-counts", { headers }).then(r => r.json()).catch(() => ({ counts: [] })),
      fetch("/api/atlas/admin/failures", { headers }).then(r => r.json()).catch(() => []),
      fetch("/api/atlas/admin/patterns",  { headers }).then(r => r.json()).catch(() => []),
      fetch("/api/atlas/admin/audit-log", { headers }).then(r => r.json()).catch(() => []),
    ])
    setUsers(profRes.data ?? [])
    setSubscriptions(subRes.data ?? [])
    setDevices(devRes.data ?? [])
    setLogs(logRes.data ?? [])
    setTickets(tickRes.data ?? [])
    setMonthlyUsage(usageRes.data ?? [])
    setGateUsage(Array.isArray(gateRes?.counts) ? gateRes.counts : [])
    setFailures(Array.isArray(failRes) ? failRes : [])
    setPatterns(Array.isArray(patRes) ? patRes : [])
    setAuditLog(Array.isArray(auditRes) ? auditRes : [])

    // Load titan_memory directly (admin only)
    const { data: tmData } = await supabase
      .from("titan_memory")
      .select("id, product_name, steps, hosts_entries, confirmed_by, confirmed_at, platform")
      .or("platform.eq.mac,platform.is.null")
      .order("confirmed_at", { ascending: false })
    setTitanMemory(tmData ?? [])

    setLoading(false)
  }

  async function resolveTicket(id: string) {
    const headers = { ...(await authHeader()), "Content-Type": "application/json" }
    const res = await fetch("/api/atlas/admin/support", {
      method: "PATCH",
      headers,
      body: JSON.stringify({ id, status: "resolved" }),
    })
    if (!res.ok) {
      const body = await res.json().catch(() => ({}))
      alert(`Failed to resolve ticket: ${body.error || res.statusText}`)
      return
    }
    setTickets(t => t.map((x: any) => x.id === id ? { ...x, status: "resolved" } : x))
    if (expandedTicket === id) setExpandedTicket(null)
  }

  async function saveInstallLimit(userID: string) {
    const raw = limitInput[userID]?.trim() ?? ""
    const limit = raw === "" ? null : parseInt(raw, 10)
    if (limit !== null && (!Number.isInteger(limit) || limit < 1)) {
      showToast("Enter a positive number, or leave blank for the standard 25")
      return
    }
    setLimitSavingId(userID)
    const headers = { ...(await authHeader()), "Content-Type": "application/json" }
    const res = await fetch("/api/atlas/admin/install-limit", {
      method: "PATCH", headers,
      body: JSON.stringify({ user_id: userID, monthly_install_limit: limit }),
    })
    setLimitSavingId(null)
    if (!res.ok) { showToast("Failed to save limit"); return }
    setUsers(u => u.map(x => x.id === userID ? { ...x, monthly_install_limit: limit } : x))
    showToast(limit === null ? "Reverted to standard 25/month" : `Limit set to ${limit}/month`)
  }

  async function resetInstallUsage(userID: string) {
    if (!confirm("Reset this client's install count to 0 for the current period? This lets them install again immediately.")) return
    setResettingId(userID)
    const headers = { ...(await authHeader()), "Content-Type": "application/json" }
    const res = await fetch("/api/atlas/admin/install-limit", {
      method: "PATCH", headers,
      body: JSON.stringify({ user_id: userID, reset_usage: true }),
    })
    setResettingId(null)
    if (!res.ok) { showToast("Failed to reset usage"); return }
    setGateUsage(g => g.map(row => row.user_id === userID ? { ...row, installs_this_month: 0 } : row))
    showToast("Usage reset — they can install again now")
  }

  async function bulkSetLimit() {
    const raw = bulkLimitInput.trim()
    const limit = raw === "" ? null : parseInt(raw, 10)
    if (limit !== null && (!Number.isInteger(limit) || limit < 1)) {
      showToast("Enter a positive number, or leave blank to revert everyone to the standard 25")
      return
    }
    const label = limit === null ? "revert every active subscriber back to the standard 25/month" : `set every active subscriber's install limit to ${limit}/month`
    if (!confirm(`This will ${label} (${activeUsers.length} active subscriber${activeUsers.length === 1 ? "" : "s"}). Continue?`)) return
    setBulkSaving(true)
    const headers = { ...(await authHeader()), "Content-Type": "application/json" }
    const res = await fetch("/api/atlas/admin/install-limit", {
      method: "PATCH", headers,
      body: JSON.stringify({ scope: "all_active", monthly_install_limit: limit }),
    })
    const data = await res.json().catch(() => ({}))
    setBulkSaving(false)
    if (!res.ok) { showToast(data?.error ? `Failed: ${data.error}` : "Failed to apply bulk limit"); return }
    const activeIDs = new Set(activeUsers.map(u => u.id))
    setUsers(u => u.map(x => activeIDs.has(x.id) ? { ...x, monthly_install_limit: limit } : x))
    showToast(`Applied to ${data.affected ?? activeUsers.length} active subscriber${(data.affected ?? activeUsers.length) === 1 ? "" : "s"}`)
  }

  async function bulkResetUsage() {
    if (!confirm(`Reset install usage to 0 for ALL ${activeUsers.length} active subscribers? This unlocks every one of them for the current period immediately.`)) return
    setBulkResetting(true)
    const headers = { ...(await authHeader()), "Content-Type": "application/json" }
    const res = await fetch("/api/atlas/admin/install-limit", {
      method: "PATCH", headers,
      body: JSON.stringify({ scope: "all_active", reset_usage: true }),
    })
    const data = await res.json().catch(() => ({}))
    setBulkResetting(false)
    if (!res.ok) { showToast(data?.error ? `Failed: ${data.error}` : "Failed to reset usage"); return }
    const activeIDs = new Set(activeUsers.map(u => u.id))
    setGateUsage(g => g.map(row => activeIDs.has(row.user_id) ? { ...row, installs_this_month: 0 } : row))
    showToast(`Usage reset for ${data.affected ?? activeUsers.length} active subscriber${(data.affected ?? activeUsers.length) === 1 ? "" : "s"}`)
  }

  async function pushUpdate(userID: string) {
    const raw = pushVersionInput[userID]?.trim() ?? ""
    const version = raw === "" ? null : raw
    if (version !== null && !/^\d+(\.\d+){1,2}$/.test(version)) {
      showToast("Enter a version like 1.6, or leave blank to clear")
      return
    }
    if (version !== null && !confirm(`Force this client to update to v${version}? ATLAS will block with an update-required screen until they do.`)) return
    setPushingId(userID)
    const headers = { ...(await authHeader()), "Content-Type": "application/json" }
    const res = await fetch("/api/atlas/admin/push-update", {
      method: "PATCH", headers,
      body: JSON.stringify({ user_id: userID, forced_update_version: version }),
    })
    setPushingId(null)
    if (!res.ok) { showToast("Failed to push update"); return }
    setUsers(u => u.map(x => x.id === userID ? { ...x, atlas_forced_update_version: version } : x))
    showToast(version === null ? "Forced update cleared" : `Pushed v${version} — takes effect within ~18s`)
  }

  async function bulkPushUpdate() {
    const raw = bulkPushVersionInput.trim()
    const version = raw === "" ? null : raw
    if (version !== null && !/^\d+(\.\d+){1,2}$/.test(version)) {
      showToast("Enter a version like 1.6, or leave blank to clear everyone")
      return
    }
    const label = version === null ? "clear the forced update for every active subscriber" : `force every active subscriber to update to v${version}`
    if (!confirm(`This will ${label} (${activeUsers.length} active subscriber${activeUsers.length === 1 ? "" : "s"}). Continue?`)) return
    setBulkPushing(true)
    const headers = { ...(await authHeader()), "Content-Type": "application/json" }
    const res = await fetch("/api/atlas/admin/push-update", {
      method: "PATCH", headers,
      body: JSON.stringify({ scope: "all_active", forced_update_version: version }),
    })
    const data = await res.json().catch(() => ({}))
    setBulkPushing(false)
    if (!res.ok) { showToast(data?.error ? `Failed: ${data.error}` : "Failed to push update"); return }
    const activeIDs = new Set(activeUsers.map(u => u.id))
    setUsers(u => u.map(x => activeIDs.has(x.id) ? { ...x, atlas_forced_update_version: version } : x))
    showToast(version === null ? `Cleared for ${data.affected ?? activeUsers.length} subscriber(s)` : `Pushed v${version} to ${data.affected ?? activeUsers.length} subscriber(s)`)
  }

  async function kickDevice(deviceID: string, deviceName: string) {
    if (!confirm(`Remove "${deviceName || "this device"}" from the account? The client will be signed out automatically within a few seconds, with no app update needed.`)) return
    setKickingDeviceId(deviceID)
    const headers = { ...(await authHeader()), "Content-Type": "application/json" }
    const res = await fetch("/api/atlas/admin/devices", {
      method: "DELETE", headers,
      body: JSON.stringify({ device_id: deviceID }),
    })
    setKickingDeviceId(null)
    if (!res.ok) { showToast("Failed to remove device"); return }
    setDevices(d => d.filter(x => x.id !== deviceID))
    showToast("Device removed — client will be signed out within a few seconds")
  }

  async function setSuspended(userID: string, suspended: boolean) {
    const label = suspended
      ? "Suspend this account indefinitely? They'll be signed out on every device within seconds and can't sign back in on any device until you unsuspend them. This does not touch their billing/subscription."
      : "Lift the suspension on this account? They'll be able to sign in again immediately."
    if (!confirm(label)) return
    setSuspendingId(userID)
    const headers = { ...(await authHeader()), "Content-Type": "application/json" }
    const res = await fetch("/api/atlas/admin/suspend", {
      method: "PATCH", headers,
      body: JSON.stringify({ user_id: userID, suspended }),
    })
    setSuspendingId(null)
    if (!res.ok) { showToast(suspended ? "Failed to suspend account" : "Failed to lift suspension"); return }
    setUsers(u => u.map(x => x.id === userID ? { ...x, atlas_suspended: suspended, atlas_suspended_reason: suspended ? 'admin' : null } : x))
    showToast(suspended ? "Account suspended — signed out everywhere within seconds" : "Suspension lifted")
  }

  async function setGrantedAccess(userID: string, granted: boolean) {
    const label = granted
      ? "Grant this account free ATLAS access despite no active subscription? This is a pure local override — it never touches Stripe, never charges them, and doesn't affect their once-per-lifetime cancellation grace period. They'll be able to sign in and use ATLAS normally within seconds."
      : "Revoke this admin-granted access? They'll go back to a plain cancelled state (not suspended) and can resubscribe normally."
    if (!confirm(label)) return
    setGrantingId(userID)
    const headers = { ...(await authHeader()), "Content-Type": "application/json" }
    const res = await fetch("/api/atlas/admin/grant-access", {
      method: "PATCH", headers,
      body: JSON.stringify({ user_id: userID, granted }),
    })
    setGrantingId(null)
    if (!res.ok) { showToast(granted ? "Failed to grant access" : "Failed to revoke access"); return }
    setUsers(u => u.map(x => x.id === userID ? { ...x, subscription_status: granted ? 'active' : 'cancelled' } : x))
    setSubscriptions(s => s.map(x => x.user_id === userID ? { ...x, status: granted ? 'active' : 'canceled', admin_granted_access: granted } : x))
    showToast(granted ? "Access granted — they can sign in now" : "Access revoked")
  }

  async function resetGracePeriod(userID: string) {
    if (!confirm("Let this account use the 10-day free-reactivation grace period again, as a one-time exception? This doesn't reactivate or charge anything now — it just means the NEXT time they cancel, they get the full grace flow again instead of an immediate final cancellation.")) return
    setResettingGraceId(userID)
    const headers = { ...(await authHeader()), "Content-Type": "application/json" }
    const res = await fetch("/api/atlas/admin/reset-grace-period", {
      method: "PATCH", headers,
      body: JSON.stringify({ user_id: userID }),
    })
    setResettingGraceId(null)
    if (!res.ok) { showToast("Failed to reset grace period"); return }
    setUsers(u => u.map(x => x.id === userID ? { ...x, grace_period_used_at: null } : x))
    showToast("Grace period reset — they'll get the full 10-day flow next time they cancel")
  }

  async function saveFailureFix() {
    if (!fixingId) return
    setFixSaving(true)
    const headers = { ...(await authHeader()), "Content-Type": "application/json" }
    await fetch("/api/atlas/admin/failures", {
      method: "PATCH", headers,
      body: JSON.stringify({ id: fixingId, admin_note: fixNote, admin_fix_status: fixStatus }),
    })
    setFailures(f => f.map((x: any) => x.id === fixingId ? { ...x, admin_note: fixNote, admin_fix_status: fixStatus } : x))
    setFixingId(null); setFixNote(""); setFixSaving(false)
  }

  async function savePattern() {
    setPatternSaving(true)
    const headers = { ...(await authHeader()), "Content-Type": "application/json" }
    const parseArr = (s: string) => s.split("\n").map(x => x.trim()).filter(Boolean)
    const body = {
      ...patternDraft,
      match_patterns:  parseArr(patternDraft.match_patterns_text  ?? ""),
      pkg_receipt_ids: parseArr(patternDraft.pkg_receipt_ids_text ?? ""),
      installed_paths: parseArr(patternDraft.installed_paths_text ?? ""),
      hosts_entries:   parseArr(patternDraft.hosts_entries_text   ?? ""),
    }
    if (newPattern) {
      await fetch("/api/atlas/admin/patterns", { method: "POST", headers, body: JSON.stringify(body) })
    } else {
      await fetch("/api/atlas/admin/patterns", { method: "PATCH", headers, body: JSON.stringify({ id: editingPattern.id, ...body }) })
    }
    const patRes = await fetch("/api/atlas/admin/patterns", { headers: await authHeader() }).then(r => r.json()).catch(() => [])
    setPatterns(Array.isArray(patRes) ? patRes : [])
    setEditingPattern(null); setNewPattern(false); setPatternSaving(false)
  }

  async function deletePattern(id: string) {
    if (!confirm("Delete this pattern? This cannot be undone.")) return
    const headers = { ...(await authHeader()), "Content-Type": "application/json" }
    await fetch("/api/atlas/admin/patterns", { method: "DELETE", headers, body: JSON.stringify({ id }) })
    setPatterns(p => p.filter((x: any) => x.id !== id))
  }

  function showToast(msg: string) {
    setToastMsg(msg)
    setTimeout(() => setToastMsg(null), 3500)
  }

  async function promoteToPattern(tm: any) {
    setPromotingId(tm.id)
    try {
      const headers = { ...(await authHeader()), "Content-Type": "application/json" }

      // Build installed_paths from steps
      const extToDir: Record<string, string> = {
        ".component": "/Library/Audio/Plug-Ins/Components/",
        ".vst3":      "/Library/Audio/Plug-Ins/VST3/",
        ".vst":       "/Library/Audio/Plug-Ins/VST/",
        ".aaxplugin": "/Library/Application Support/Avid/Audio/Plug-Ins/",
        ".app":       "/Applications/",
      }
      const steps: any[] = Array.isArray(tm.steps) ? tm.steps : []
      const installedPaths: string[] = []
      for (const step of steps) {
        if (step.type === "plugin" && step.file) {
          const ext = Object.keys(extToDir).find(e => step.file.toLowerCase().endsWith(e))
          if (ext) installedPaths.push(extToDir[ext] + step.file)
        }
      }

      // Build match_patterns
      const base = tm.product_name.toLowerCase()
        .replace(/v\d[\d.]+/g, "")
        .replace(/[^a-z0-9\s]/g, " ")
        .replace(/\s+/g, " ")
        .trim()
      const matchPatterns = Array.from(new Set([base, ...base.split(" ").filter((w: string) => w.length > 3)]))

      const body = {
        product_name:      tm.product_name,
        match_patterns:    matchPatterns,
        pkg_receipt_ids:   [],
        installed_paths:   installedPaths,
        hosts_entries:     Array.isArray(tm.hosts_entries) ? tm.hosts_entries : [],
      }

      const res = await fetch("/api/atlas/admin/patterns", { method: "POST", headers, body: JSON.stringify(body) })
      if (!res.ok) throw new Error(await res.text())

      // Refresh patterns list
      const patRes = await fetch("/api/atlas/admin/patterns", { headers: await authHeader() }).then(r => r.json()).catch(() => [])
      setPatterns(Array.isArray(patRes) ? patRes : [])
      showToast(`✓ Promoted "${tm.product_name}" to install_patterns`)
    } catch (err: any) {
      showToast(`Error: ${err.message ?? "Failed to promote"}`)
    } finally {
      setPromotingId(null)
    }
  }

  if (!authed) return null

  // ── Derived data ──────────────────────────────────────────────────────────

  const subByUser = Object.fromEntries(subscriptions.map(s => [s.user_id, s]))

  const atlasUsers   = users.filter(u => u.plan === "atlas")
  const freeUsers    = users.filter(u => u.plan === "free" || u.plan == null)
  const activeUsers  = users.filter(u => u.subscription_status === "active")
  const openTickets  = tickets.filter((t: any) => t.status === "open")
  const openFailures = failures.filter((f: any) => f.admin_fix_status === "open")
  const filteredLogs  = logFilter === "all" ? logs : logs.filter(l => l.log_type === logFilter)
  const filteredFails = failureFilter === "all" ? failures : failures.filter((f: any) => f.admin_fix_status === failureFilter)

  const cancelingSoon = subscriptions.filter(s => s.cancel_at_period_end && s.status === "active").length
  const pastDue = subscriptions.filter(s => s.status === "past_due").length

  const mrr = subscriptions
    .filter(s => s.status === "active")
    .reduce((sum, s) => {
      if (s.plan === "atlas") {
        const interval = users.find(u => u.id === s.user_id)?.billing_interval ?? "monthly"
        return sum + (interval === "annual" ? 25 : 30)
      }
      const LEGACY_PRICE: Record<string, number> = { standard: 9, pro: 19, advanced: 29, basic: 5 }
      return sum + (LEGACY_PRICE[s.plan] ?? 0)
    }, 0)

  const failuresByProduct: Record<string, any[]> = {}
  failures.forEach((f: any) => {
    const k = f.product_name ?? "Unknown"
    if (!failuresByProduct[k]) failuresByProduct[k] = []
    failuresByProduct[k].push(f)
  })

  function emailOf(uid: string) { return users.find(u => u.id === uid)?.email ?? uid.slice(0,8) + "…" }
  function userAuditLog(uid: string) { return auditLog.filter((a: any) => a.user_id === uid) }
  function userDevices(uid: string) { return devices.filter(d => d.user_id === uid) }
  function userLogs(uid: string) { return logs.filter(l => l.user_id === uid) }
  function userTickets(uid: string) { return tickets.filter((t: any) => t.user_id === uid) }
  function userCurrentUsage(uid: string) {
    const now = new Date()
    return monthlyUsage.find(m => m.user_id === uid && new Date(m.period_end) >= now)
  }
  function userGateCount(uid: string) {
    // 25 installs is a per-device limit (2026-11-05) — a user can have one
    // install_counts row per registered device, so this sums across all of
    // them for a rough "total across devices" figure.
    const rows = gateUsage.filter(g => g.user_id === uid)
    if (rows.length === 0) return undefined
    return { installs_this_month: rows.reduce((sum, r) => sum + (r.installs_this_month ?? 0), 0) }
  }
  function userDeviceUsage(uid: string) {
    // Per-device breakdown — matches how the limit is actually enforced
    // (reserve_install_slot gates per hardware_uuid, not per account), so this
    // is the figure that answers "is THIS device close to its cap," which the
    // blended userGateCount() total above cannot show for multi-device users.
    const devs = userDevices(uid)
    return gateUsage
      .filter(g => g.user_id === uid)
      .map(g => ({
        device_name: devs.find(d => d.hardware_uuid === g.hardware_uuid)?.device_name ?? g.hardware_uuid.slice(0, 8) + '…',
        installs_this_month: g.installs_this_month ?? 0,
      }))
  }

  const filteredUsers = subSearch.trim()
    ? users.filter(u => u.email?.toLowerCase().includes(subSearch.toLowerCase()))
    : users

  const card: React.CSSProperties = { background: "var(--atlas-card)", borderRadius: "12px", border: "1px solid var(--atlas-border-color)", overflow: "hidden" }
  const inputStyle: React.CSSProperties = { background: "var(--atlas-bg)", border: "1px solid var(--atlas-border-color)", borderRadius: "7px", color: "var(--atlas-text-body)", padding: "8px 12px", fontSize: "12px", width: "100%", outline: "none", boxSizing: "border-box" }
  const labelStyle: React.CSSProperties = { fontSize: "9px", fontWeight: 700, letterSpacing: "2px", color: "var(--atlas-text-label)", textTransform: "uppercase", display: "block", marginBottom: "5px" }

  return (
    <div style={{ minHeight: "100vh", background: "var(--atlas-bg)", color: "var(--atlas-fg)" }}>
      {/* Toast */}
      {toastMsg && (
        <div style={{ position:"fixed", bottom:"24px", left:"50%", transform:"translateX(-50%)", zIndex:999, background:"var(--atlas-border-color)", border:"1px solid #3ECFB2", borderRadius:"10px", padding:"10px 20px", fontSize:"12px", color:"var(--atlas-fg)", boxShadow:"0 4px 20px rgba(0,0,0,0.5)", whiteSpace:"nowrap" }}>
          {toastMsg}
        </div>
      )}

      {/* Header */}
      <header style={{ borderBottom: "1px solid var(--atlas-border-color)", position: "sticky", top: 0, zIndex: 50, background: "rgba(7,8,15,0.95)", backdropFilter: "blur(12px)", padding: "14px 28px", display: "flex", alignItems: "center", justifyContent: "space-between" }}>
        <div style={{ display: "flex", alignItems: "center", gap: "12px" }}>
          <Link href="/atlas/account" style={{ fontSize: "10px", letterSpacing: "1px", color: "var(--text-muted)", textDecoration: "none", padding: "5px 10px", border: "1px solid var(--atlas-border-color)", borderRadius: "6px" }}>← ACCOUNT</Link>
          <span style={{ fontSize: "18px", letterSpacing: "6px", fontFamily: "'SF-Intellivised', sans-serif" }}>ATLAS</span>
          <span style={{ fontSize: "9px", color: "#F0A030", letterSpacing: "3px", padding: "2px 8px", border: "1px solid rgba(240,160,48,0.3)", borderRadius: "4px", background: "rgba(240,160,48,0.06)" }}>ADMIN</span>
        </div>
        <div style={{ display: "flex", gap: "12px", alignItems: "center" }}>
          <span style={{ fontSize: "11px", color: "var(--atlas-text-mid)" }}>{userEmail}</span>
          <button onClick={loadAll} style={{ fontSize: "10px", color: "#3ECFB2", background: "none", border: "1px solid rgba(62,207,178,0.3)", borderRadius: "6px", padding: "4px 10px", cursor: "pointer" }}>
            {loading ? "Syncing…" : "↻ Refresh"}
          </button>
        </div>
      </header>

      <main style={{ maxWidth: "1140px", margin: "0 auto", padding: "28px 24px" }}>

        {/* Stats */}
        <div style={{ display: "flex", flexWrap: "wrap", gap: "10px", marginBottom: "24px" }}>
          {[
            { label: "Total Users",    val: users.length,           color: "var(--atlas-fg)" },
            { label: "Active",         val: activeUsers.length,     color: "#3ECFB2" },
            { label: "ATLAS",          val: atlasUsers.length,      color: "#3ECFB2" },
            { label: "Free / None",    val: freeUsers.length,       color: "#5B8DEF" },
            { label: "Est. MRR",       val: `$${mrr}`,              color: "#3ECFB2" },
            { label: "Past Due",       val: pastDue,                color: pastDue > 0 ? "#E05555" : "var(--atlas-text-label)" },
            { label: "Canceling Soon", val: cancelingSoon,          color: cancelingSoon > 0 ? "#F0A030" : "var(--atlas-text-label)" },
            { label: "Devices",        val: devices.length,         color: "var(--atlas-fg)" },
            { label: "Open Tickets",   val: openTickets.length,     color: openTickets.length  > 0 ? "#E05555" : "var(--atlas-text-label)" },
            { label: "Open Failures",  val: openFailures.length,    color: openFailures.length > 0 ? "#E05555" : "var(--atlas-text-label)" },
            { label: "Known Patterns", val: patterns.length,        color: "#3ECFB2" },
          ].map(s => (
            <div key={s.label} style={{ background: "var(--atlas-card)", border: "1px solid var(--atlas-border-color)", borderRadius: "10px", padding: "12px 18px", minWidth: "90px" }}>
              <p style={{ fontSize: "8px", color: "var(--atlas-text-label)", letterSpacing: "2px", marginBottom: "4px", textTransform: "uppercase" }}>{s.label}</p>
              <p style={{ fontSize: "20px", fontWeight: 700, color: s.color, margin: 0 }}>{s.val}</p>
            </div>
          ))}
        </div>

        {/* Tabs */}
        <div style={{ display: "flex", gap: "3px", marginBottom: "20px", background: "var(--atlas-card)", border: "1px solid var(--atlas-border-color)", borderRadius: "10px", padding: "4px", flexWrap: "wrap" }}>
          {(["subscribers","devices","suspended","feedback","logs","support","failures","patterns","recovery-kits"] as Tab[]).map(t => (
            <button key={t} onClick={() => setTab(t)} style={{ flex: 1, minWidth: "80px", padding: "8px 6px", borderRadius: "7px", border: "none", cursor: "pointer", fontSize: "11px", fontWeight: 600, letterSpacing: "0.5px", textTransform: "capitalize", background: tab === t ? "var(--atlas-border-color)" : "transparent", color: tab === t ? "var(--atlas-fg)" : "var(--atlas-text-label)", position: "relative" }}>
              {t}
              {t === "support"  && openTickets.length  > 0 && <span style={{ marginLeft:"5px", background:"#E05555", color:"#fff", fontSize:"8px", fontWeight:800, padding:"1px 4px", borderRadius:"8px" }}>{openTickets.length}</span>}
              {t === "failures" && openFailures.length > 0 && <span style={{ marginLeft:"5px", background:"#E05555", color:"#fff", fontSize:"8px", fontWeight:800, padding:"1px 4px", borderRadius:"8px" }}>{openFailures.length}</span>}
            </button>
          ))}
        </div>

        {/* ── SUBSCRIBERS ── */}
        {tab === "subscribers" && (
          <div style={{ display:"flex", flexDirection:"column", gap:"10px" }}>
            <div style={{ position: "relative" }}>
              <input
                type="text"
                placeholder="Search by email…"
                value={subSearch}
                onChange={e => setSubSearch(e.target.value)}
                style={{ ...inputStyle, paddingLeft: "32px" }}
              />
              <span style={{ position:"absolute", left:"11px", top:"50%", transform:"translateY(-50%)", fontSize:"14px", color:"var(--atlas-text-label)", pointerEvents:"none" }}>⌕</span>
              {subSearch && <button onClick={() => setSubSearch("")} style={{ position:"absolute", right:"10px", top:"50%", transform:"translateY(-50%)", background:"none", border:"none", color:"var(--atlas-text-label)", cursor:"pointer", fontSize:"16px", lineHeight:1 }}>×</button>}
            </div>

            <div style={{ ...card, padding: "14px 18px", border: "1px solid rgba(240,160,48,0.25)" }}>
              <span style={labelStyle}>Bulk: All {activeUsers.length} Active Subscribers</span>
              <div style={{ display:"flex", gap:"8px", alignItems:"center", flexWrap:"wrap", marginTop:"6px" }}>
                <input
                  type="number"
                  min={1}
                  placeholder="25 (standard)"
                  value={bulkLimitInput}
                  onChange={e => setBulkLimitInput(e.target.value)}
                  style={{ ...inputStyle, width: "110px" }}
                />
                <button
                  onClick={bulkSetLimit}
                  disabled={bulkSaving || activeUsers.length === 0}
                  style={{ fontSize:"11px", fontWeight:600, color:"#08090E", background:"#3ECFB2", border:"none", borderRadius:"7px", padding:"6px 14px", cursor:"pointer" }}
                >
                  {bulkSaving ? "Applying…" : "Apply Limit to All Active"}
                </button>
                <button
                  onClick={bulkResetUsage}
                  disabled={bulkResetting || activeUsers.length === 0}
                  style={{ fontSize:"11px", fontWeight:600, color:"#F0A030", background:"rgba(240,160,48,0.08)", border:"1px solid rgba(240,160,48,0.3)", borderRadius:"7px", padding:"6px 14px", cursor:"pointer" }}
                >
                  {bulkResetting ? "Resetting…" : "Reset Usage For All Active (Unlock Now)"}
                </button>
              </div>
              <p style={{ fontSize:"10px", color:"var(--atlas-text-label)", marginTop:"6px" }}>
                Applies only to subscribers with an active subscription right now — computed fresh from the subscriptions table, not from what's currently on screen. Leave the field blank and click Apply to revert everyone to the standard 25/month.
              </p>
            </div>

            <div style={{ ...card, padding: "14px 18px", border: "1px solid rgba(224,85,85,0.25)" }}>
              <span style={labelStyle}>Bulk: Force Update — All {activeUsers.length} Active Subscribers</span>
              <div style={{ display:"flex", gap:"8px", alignItems:"center", flexWrap:"wrap", marginTop:"6px" }}>
                <input
                  type="text"
                  placeholder="e.g. 1.6"
                  value={bulkPushVersionInput}
                  onChange={e => setBulkPushVersionInput(e.target.value)}
                  style={{ ...inputStyle, width: "110px" }}
                />
                <button
                  onClick={bulkPushUpdate}
                  disabled={bulkPushing || activeUsers.length === 0}
                  style={{ fontSize:"11px", fontWeight:600, color:"#fff", background:"#E05555", border:"none", borderRadius:"7px", padding:"6px 14px", cursor:"pointer" }}
                >
                  {bulkPushing ? "Pushing…" : "Force Update For All Active"}
                </button>
              </div>
              <p style={{ fontSize:"10px", color:"var(--atlas-text-label)", marginTop:"6px" }}>
                Blocks ATLAS with an update-required screen until the client updates to this version — takes effect within ~18 seconds via the app's live sync. Leave blank and click to clear the force for everyone.
              </p>
            </div>

            {filteredUsers.length === 0 && <div style={{...card,padding:"40px",textAlign:"center",color:"var(--atlas-text-label)"}}>{subSearch ? "No users match." : "No users yet."}</div>}
            {filteredUsers.map(u => {
              const sub      = subByUser[u.id]
              const uDevs    = userDevices(u.id)
              const uLogs    = userLogs(u.id)
              const uTickets = userTickets(u.id)
              const usage    = userCurrentUsage(u.id)
              const open     = expandedUser === u.id
              const confirmedInstalls = uLogs.filter(l => l.log_type === "confirmed-success")
              const isExpiring = sub?.cancel_at_period_end && sub?.status === "active"
              const isPastDue  = sub?.status === "past_due"

              return (
                <div key={u.id} style={{ ...card, border: isExpiring ? "1px solid rgba(240,160,48,0.4)" : isPastDue ? "1px solid rgba(224,85,85,0.4)" : "1px solid var(--atlas-border-color)" }}>
                  <button onClick={() => setExpandedUser(open ? null : u.id)} style={{ width:"100%", background:"none", border:"none", cursor:"pointer", padding:"14px 18px", display:"flex", alignItems:"center", gap:"12px", textAlign:"left" }}>
                    <div style={{ width:"8px", height:"8px", borderRadius:"50%", background:statusColor(u.subscription_status), boxShadow:`0 0 6px ${statusColor(u.subscription_status)}88`, flexShrink:0 }} />
                    <div style={{ flex:1, minWidth:0 }}>
                      <p style={{ fontSize:"13px", color:"var(--atlas-text-body)", fontWeight:500, margin:0, overflow:"hidden", textOverflow:"ellipsis", whiteSpace:"nowrap" }}>{u.email}</p>
                      <div style={{ display:"flex", gap:"8px", alignItems:"center", marginTop:"3px", flexWrap:"wrap" }}>
                        <span style={{ fontSize:"10px", color:"var(--atlas-text-label)" }}>Joined {fmt(u.created_at)}</span>
                        {u.privacy_consent && <span style={{ fontSize:"9px", color:"rgba(62,207,178,0.5)" }}>· sync on</span>}
                        {isExpiring && <span style={{ fontSize:"9px", fontWeight:700, color:"#F0A030" }}>· cancels {fmtShort(sub?.current_period_end)}</span>}
                        {isPastDue  && <span style={{ fontSize:"9px", fontWeight:700, color:"#E05555" }}>· PAST DUE</span>}
                      </div>
                    </div>
                    <div style={{ display:"flex", gap:"6px", alignItems:"center", flexShrink:0, flexWrap:"wrap", justifyContent:"flex-end" }}>
                      <span style={{ fontSize:"9px", fontWeight:800, padding:"3px 8px", borderRadius:"5px", border:`1px solid ${planColor(u.plan)}44`, color:planColor(u.plan), background:`${planColor(u.plan)}11` }}>{u.plan.toUpperCase()}</span>
                      <span style={{ fontSize:"9px", fontWeight:700, padding:"3px 8px", borderRadius:"5px", border:`1px solid ${statusColor(u.subscription_status)}44`, color:statusColor(u.subscription_status), background:`${statusColor(u.subscription_status)}11` }}>{u.subscription_status.toUpperCase()}</span>
                      <span style={{ fontSize:"10px", color:"var(--atlas-text-faint)" }}>{uDevs.length}d · {uLogs.length}l</span>
                      <span style={{ fontSize:"11px", color: open?"#3ECFB2":"var(--atlas-text-label)" }}>{open?"▲":"▼"}</span>
                    </div>
                  </button>

                  {open && (() => {
                    const activeProfileTab = userProfileTab[u.id] ?? "billing"
                    const setProfileTab = (t: string) => setUserProfileTab(prev => ({ ...prev, [u.id]: t }))
                    const profileTabs = [
                      { id: "billing",  label: "Billing",  count: null },
                      { id: "logs",     label: "Logs",     count: uLogs.length },
                      { id: "devices",  label: "Devices",  count: uDevs.length },
                      { id: "support",  label: "Support",  count: uTickets.length, alert: uTickets.filter((t:any)=>t.status==="open").length > 0 },
                    ]
                    return (
                      <div style={{ borderTop:"1px solid var(--atlas-divider)" }}>

                        {/* Inner tab bar */}
                        <div style={{ display:"flex", gap:"2px", padding:"8px 12px", borderBottom:"1px solid var(--atlas-divider)", background:"#08090F" }}>
                          {profileTabs.map(pt => (
                            <button key={pt.id} onClick={() => setProfileTab(pt.id)} style={{ padding:"5px 12px", borderRadius:"6px", border:"none", cursor:"pointer", fontSize:"11px", fontWeight:600, background: activeProfileTab===pt.id ? "var(--atlas-border-color)" : "transparent", color: activeProfileTab===pt.id ? "var(--atlas-fg)" : "var(--atlas-text-mid)", display:"flex", alignItems:"center", gap:"5px" }}>
                              {pt.label}
                              {pt.count !== null && pt.count > 0 && (
                                <span style={{ fontSize:"9px", fontWeight:800, padding:"1px 5px", borderRadius:"8px", background: pt.alert ? "#E05555" : "var(--atlas-border-color)", color: pt.alert ? "#fff" : "var(--text-muted)" }}>{pt.count}</span>
                              )}
                            </button>
                          ))}
                        </div>

                        {/* ── BILLING tab ── */}
                        {activeProfileTab === "billing" && (
                          <div style={{ padding:"16px 18px" }}>
                            <div style={{ display:"grid", gridTemplateColumns:"repeat(auto-fill, minmax(155px,1fr))", gap:"14px" }}>
                              {[
                                { label:"Plan",               val:(sub?.plan ?? u.plan).toUpperCase(), color:planColor(sub?.plan ?? u.plan), bold:true },
                                { label:"Billing Status",     val:(sub?.status ?? u.subscription_status).toUpperCase(), color:statusColor(sub?.status ?? u.subscription_status), bold:true },
                                { label:"Period Start",       val:fmt(sub?.current_period_start) },
                                { label:"Renewal Date",       val:fmt(sub?.current_period_end), color: isExpiring ? "#F0A030" : undefined, bold: !!isExpiring },
                                { label:"Cancel at End",      val: sub?.cancel_at_period_end ? "Yes — canceling" : sub ? "No" : "—", color: sub?.cancel_at_period_end ? "#F0A030" : "#3ECFB2", bold:true },
                                { label:"Subscribed Since",   val:fmt(sub?.created_at) },
                                { label:"This Month Installs",val: usage ? `${usage.count} used` : "0" },
                                { label:"Total Installs",     val: String(uLogs.filter(l => l.log_type==="install"||l.log_type==="confirmed-success").length) },
                                { label:"Confirmed Successes",val: String(confirmedInstalls.length), color:"#A855F7" },
                                { label:"Joined",             val:fmt(u.created_at) },
                                { label:"Log Sync",           val: u.privacy_consent ? "On" : "Off", color: u.privacy_consent ? "#3ECFB2" : "var(--atlas-text-mid)" },
                                { label:"Billing Cadence",    val: u.billing_interval === "annual" ? "Annual" : u.billing_interval === "monthly" ? "Monthly" : "—" },
                                { label:"Billing Anchor",     val: u.billing_anchor_day != null ? `Day ${u.billing_anchor_day} of month` : "—" },
                                { label:"Current Period Installs", val: (() => { const g = userGateCount(u.id); const lim = u.monthly_install_limit ?? 25; return g != null ? `${g.installs_this_month} / ${lim}` : `— / ${lim}` })(), color: (() => { const g = userGateCount(u.id); const lim = u.monthly_install_limit ?? 25; return g != null && g.installs_this_month >= lim - 5 ? "#F0A030" : "#3ECFB2" })(), bold: true },
                              ].map(f => (
                                <div key={f.label}>
                                  <span style={labelStyle}>{f.label}</span>
                                  <p style={{ fontSize:"12px", color: f.color ?? "#A0A8C8", fontWeight: f.bold ? 600 : 400, margin:0 }}>{f.val}</p>
                                </div>
                              ))}
                              <div style={{ gridColumn: "span 2" }}>
                                <span style={labelStyle}>Install Limit Override (per device, per period)</span>
                                <div style={{ display:"flex", gap:"8px", alignItems:"center", flexWrap:"wrap" }}>
                                  <input
                                    type="number"
                                    min={1}
                                    placeholder={u.monthly_install_limit != null ? String(u.monthly_install_limit) : "25 (standard)"}
                                    value={limitInput[u.id] ?? (u.monthly_install_limit != null ? String(u.monthly_install_limit) : "")}
                                    onChange={e => setLimitInput(m => ({ ...m, [u.id]: e.target.value }))}
                                    style={{ ...inputStyle, width: "110px" }}
                                  />
                                  <button
                                    onClick={() => saveInstallLimit(u.id)}
                                    disabled={limitSavingId === u.id}
                                    style={{ fontSize:"11px", fontWeight:600, color:"#08090E", background:"#3ECFB2", border:"none", borderRadius:"7px", padding:"6px 14px", cursor:"pointer" }}
                                  >
                                    {limitSavingId === u.id ? "Saving…" : "Save Limit"}
                                  </button>
                                  {u.monthly_install_limit != null && (
                                    <button
                                      onClick={() => { setLimitInput(m => ({ ...m, [u.id]: "" })); saveInstallLimit(u.id) }}
                                      disabled={limitSavingId === u.id}
                                      style={{ fontSize:"11px", color:"var(--atlas-text-label)", background:"none", border:"1px solid var(--atlas-border-color)", borderRadius:"7px", padding:"6px 14px", cursor:"pointer" }}
                                    >
                                      Revert to 25
                                    </button>
                                  )}
                                  <button
                                    onClick={() => resetInstallUsage(u.id)}
                                    disabled={resettingId === u.id}
                                    style={{ fontSize:"11px", fontWeight:600, color:"#F0A030", background:"rgba(240,160,48,0.08)", border:"1px solid rgba(240,160,48,0.3)", borderRadius:"7px", padding:"6px 14px", cursor:"pointer" }}
                                  >
                                    {resettingId === u.id ? "Resetting…" : "Reset Usage (Unlock Now)"}
                                  </button>
                                </div>
                                <p style={{ fontSize:"10px", color:"var(--atlas-text-label)", marginTop:"6px" }}>
                                  Leave blank for the standard 25/month. Takes effect on their next install attempt — no app update needed. "Reset Usage" zeroes their count for the current period only; it doesn't change their limit.
                                </p>
                              </div>
                              <div style={{ gridColumn: "span 2" }}>
                                <span style={labelStyle}>Force Update</span>
                                <div style={{ display:"flex", gap:"8px", alignItems:"center", flexWrap:"wrap" }}>
                                  <input
                                    type="text"
                                    placeholder={u.atlas_forced_update_version ? u.atlas_forced_update_version : "e.g. 1.6"}
                                    value={pushVersionInput[u.id] ?? (u.atlas_forced_update_version ?? "")}
                                    onChange={e => setPushVersionInput(m => ({ ...m, [u.id]: e.target.value }))}
                                    style={{ ...inputStyle, width: "110px" }}
                                  />
                                  <button
                                    onClick={() => pushUpdate(u.id)}
                                    disabled={pushingId === u.id}
                                    style={{ fontSize:"11px", fontWeight:600, color:"#fff", background:"#E05555", border:"none", borderRadius:"7px", padding:"6px 14px", cursor:"pointer" }}
                                  >
                                    {pushingId === u.id ? "Pushing…" : "Push & Force Update"}
                                  </button>
                                  {u.atlas_forced_update_version && (
                                    <button
                                      onClick={() => { setPushVersionInput(m => ({ ...m, [u.id]: "" })); pushUpdate(u.id) }}
                                      disabled={pushingId === u.id}
                                      style={{ fontSize:"11px", color:"var(--atlas-text-label)", background:"none", border:"1px solid var(--atlas-border-color)", borderRadius:"7px", padding:"6px 14px", cursor:"pointer" }}
                                    >
                                      Clear Force
                                    </button>
                                  )}
                                  {u.atlas_forced_update_version && (
                                    <span style={{ fontSize:"9px", fontWeight:700, color:"#E05555" }}>Currently forced to v{u.atlas_forced_update_version}</span>
                                  )}
                                </div>
                                <p style={{ fontSize:"10px", color:"var(--atlas-text-label)", marginTop:"6px" }}>
                                  Blocks ATLAS with an update-required screen until they're on this version. Takes effect within ~18s via the app's live sync — no manual check needed on their end.
                                </p>
                              </div>
                              <div style={{ gridColumn: "span 2" }}>
                                <span style={labelStyle}>Account Suspension (Indefinite — All Devices)</span>
                                <div style={{ display:"flex", gap:"8px", alignItems:"center", flexWrap:"wrap" }}>
                                  {u.atlas_suspended ? (
                                    <>
                                      <span style={{ fontSize:"10px", fontWeight:700, color:"#E05555", padding:"3px 8px", borderRadius:"5px", border:"1px solid rgba(224,85,85,0.4)", background:"rgba(224,85,85,0.1)" }}>SUSPENDED</span>
                                      <button
                                        onClick={() => setSuspended(u.id, false)}
                                        disabled={suspendingId === u.id}
                                        style={{ fontSize:"11px", fontWeight:600, color:"#3ECFB2", background:"rgba(62,207,178,0.08)", border:"1px solid rgba(62,207,178,0.3)", borderRadius:"7px", padding:"6px 14px", cursor:"pointer" }}
                                      >
                                        {suspendingId === u.id ? "Lifting…" : "Lift Suspension"}
                                      </button>
                                    </>
                                  ) : (
                                    <button
                                      onClick={() => setSuspended(u.id, true)}
                                      disabled={suspendingId === u.id}
                                      style={{ fontSize:"11px", fontWeight:600, color:"#fff", background:"#E05555", border:"none", borderRadius:"7px", padding:"6px 14px", cursor:"pointer" }}
                                    >
                                      {suspendingId === u.id ? "Suspending…" : "Suspend Account"}
                                    </button>
                                  )}
                                </div>
                                <p style={{ fontSize:"10px", color:"var(--atlas-text-label)", marginTop:"6px" }}>
                                  Unlike "Remove / Kick" (which only removes one device — they can still sign in from another under their device limit), suspension blocks this account on every device, indefinitely, until lifted. Signs out an active session within seconds. Does not touch billing or cancel their subscription.
                                </p>
                              </div>
                              {u.subscription_status !== "active" && (
                                <div style={{ gridColumn: "span 2" }}>
                                  <span style={labelStyle}>Admin-Granted Access (No Subscription Required)</span>
                                  <div style={{ display:"flex", gap:"8px", alignItems:"center", flexWrap:"wrap" }}>
                                    {sub?.admin_granted_access ? (
                                      <>
                                        <span style={{ fontSize:"10px", fontWeight:700, color:"#3ECFB2", padding:"3px 8px", borderRadius:"5px", border:"1px solid rgba(62,207,178,0.4)", background:"rgba(62,207,178,0.1)" }}>ADMIN GRANTED</span>
                                        <button
                                          onClick={() => setGrantedAccess(u.id, false)}
                                          disabled={grantingId === u.id}
                                          style={{ fontSize:"11px", fontWeight:600, color:"#E05555", background:"rgba(224,85,85,0.08)", border:"1px solid rgba(224,85,85,0.3)", borderRadius:"7px", padding:"6px 14px", cursor:"pointer" }}
                                        >
                                          {grantingId === u.id ? "Revoking…" : "Revoke Access"}
                                        </button>
                                      </>
                                    ) : (
                                      <button
                                        onClick={() => setGrantedAccess(u.id, true)}
                                        disabled={grantingId === u.id}
                                        style={{ fontSize:"11px", fontWeight:600, color:"#07080F", background:"linear-gradient(135deg, #3ECFB2, #2ABEAA)", border:"none", borderRadius:"7px", padding:"6px 14px", cursor:"pointer" }}
                                      >
                                        {grantingId === u.id ? "Granting…" : "Grant Free Access"}
                                      </button>
                                    )}
                                  </div>
                                  <p style={{ fontSize:"10px", color:"var(--atlas-text-label)", marginTop:"6px" }}>
                                    Lets this account sign in and use ATLAS normally despite having no active subscription — a pure local override, never touches Stripe or charges them, and doesn't affect their once-per-lifetime cancellation grace period.
                                  </p>
                                </div>
                              )}
                              {u.grace_period_used_at && (
                                <div style={{ gridColumn: "span 2" }}>
                                  <span style={labelStyle}>10-Day Cancellation Grace Period</span>
                                  <div style={{ display:"flex", gap:"8px", alignItems:"center", flexWrap:"wrap" }}>
                                    <span style={{ fontSize:"10px", fontWeight:700, color:"var(--atlas-text-label)", padding:"3px 8px", borderRadius:"5px", border:"1px solid var(--atlas-border-color)" }}>
                                      Already used {fmt(u.grace_period_used_at)}
                                    </span>
                                    <button
                                      onClick={() => resetGracePeriod(u.id)}
                                      disabled={resettingGraceId === u.id}
                                      style={{ fontSize:"11px", fontWeight:600, color:"#07080F", background:"linear-gradient(135deg, #3ECFB2, #2ABEAA)", border:"none", borderRadius:"7px", padding:"6px 14px", cursor:"pointer" }}
                                    >
                                      {resettingGraceId === u.id ? "Resetting…" : "Allow Another Grace Period"}
                                    </button>
                                  </div>
                                  <p style={{ fontSize:"10px", color:"var(--atlas-text-label)", marginTop:"6px" }}>
                                    This account has already used its one-time 10-day free-reactivation window and will get an immediate, final cancellation if they cancel again. This grants a one-off exception — their next cancellation gets the full grace flow again. Doesn't reactivate or charge anything now.
                                  </p>
                                </div>
                              )}
                              {userAuditLog(u.id).length > 0 && (
                                <div style={{ gridColumn: "span 2" }}>
                                  <span style={labelStyle}>Account History — {userAuditLog(u.id).length} event{userAuditLog(u.id).length === 1 ? "" : "s"}</span>
                                  <div style={{ display:"flex", flexDirection:"column", gap:"6px", marginTop:"4px" }}>
                                    {userAuditLog(u.id).map((a: any) => (
                                      <div key={a.id} style={{ padding:"8px 10px", borderRadius:"7px", border:"1px solid var(--atlas-border-color)", background:"var(--atlas-icon-bg)" }}>
                                        <div style={{ display:"flex", alignItems:"center", justifyContent:"space-between", gap:"8px" }}>
                                          <span style={{ fontSize:"11px", fontWeight:700, color:"var(--atlas-text-body)" }}>{a.event}</span>
                                          <span style={{ fontSize:"10px", color:"var(--atlas-text-label)" }}>{fmt(a.created_at)}</span>
                                        </div>
                                        {a.notes && <p style={{ fontSize:"11px", color:"var(--atlas-text-mid)", margin:"4px 0 0", lineHeight:1.4 }}>{a.notes}</p>}
                                        {a.metadata && Object.keys(a.metadata).length > 0 && (
                                          <p style={{ fontSize:"10px", color:"var(--atlas-text-label)", margin:"4px 0 0", fontFamily:"monospace", wordBreak:"break-word" }}>
                                            {Object.entries(a.metadata).filter(([, v]) => v !== null && v !== undefined).map(([k, v]) => `${k}: ${v}`).join("  ·  ")}
                                          </p>
                                        )}
                                      </div>
                                    ))}
                                  </div>
                                </div>
                              )}
                              {userDeviceUsage(u.id).length > 0 && (
                                <div style={{ gridColumn: "span 2" }}>
                                  <span style={labelStyle}>Installs This Period, Per Device</span>
                                  {userDeviceUsage(u.id).map((d, i) => {
                                    const lim = u.monthly_install_limit ?? 25
                                    return (
                                      <p key={i} style={{ fontSize: "12px", margin: "2px 0", color: d.installs_this_month >= lim ? "#E05555" : d.installs_this_month >= lim - 5 ? "#F0A030" : "#A0A8C8", fontWeight: d.installs_this_month >= lim - 5 ? 600 : 400 }}>
                                        {d.device_name}: {d.installs_this_month} / {lim}
                                      </p>
                                    )
                                  })}
                                </div>
                              )}
                              {sub?.stripe_customer_id && (
                                <div style={{ gridColumn:"span 2" }}>
                                  <span style={labelStyle}>Stripe Customer ID</span>
                                  <p style={{ fontSize:"10px", color:"var(--text-muted)", fontFamily:"monospace", margin:0 }}>{sub.stripe_customer_id}</p>
                                </div>
                              )}
                              {sub?.stripe_subscription_id && (
                                <div style={{ gridColumn:"span 2" }}>
                                  <span style={labelStyle}>Stripe Subscription ID</span>
                                  <p style={{ fontSize:"10px", color:"var(--text-muted)", fontFamily:"monospace", margin:0 }}>{sub.stripe_subscription_id}</p>
                                </div>
                              )}
                            </div>
                          </div>
                        )}

                        {/* ── LOGS tab ── */}
                        {activeProfileTab === "logs" && (
                          <div style={{ maxHeight:"420px", overflowY:"auto" }}>
                            {uLogs.length === 0
                              ? <p style={{ padding:"24px", textAlign:"center", color:"var(--atlas-text-label)", fontSize:"12px" }}>No logs yet.</p>
                              : uLogs.map(l => (
                                <div key={l.id} style={{ display:"flex", gap:"8px", alignItems:"center", padding:"9px 18px", borderBottom:"1px solid #0A0C18" }}>
                                  <span style={{ fontSize:"8px", fontWeight:800, letterSpacing:"1px", padding:"2px 7px", borderRadius:"3px", background:logTypeBg(l.log_type??"install"), color:logTypeColor(l.log_type??"install"), flexShrink:0, minWidth:"60px", textAlign:"center" }}>{(l.log_type??"install").toUpperCase()}</span>
                                  <div style={{ flex:1, minWidth:0 }}>
                                    <p style={{ fontSize:"12px", color:"#C0C8E8", margin:0, overflow:"hidden", textOverflow:"ellipsis", whiteSpace:"nowrap" }}>{l.app_name ?? l.filename ?? "—"}</p>
                                    {l.device_name && <p style={{ fontSize:"9px", color:"var(--atlas-text-label)", margin:"1px 0 0" }}>{l.device_name}</p>}
                                  </div>
                                  <span style={{ fontSize:"10px", color:"var(--atlas-text-label)", flexShrink:0 }}>{fmtDateTime(l.installed_at)}</span>
                                </div>
                              ))
                            }
                          </div>
                        )}

                        {/* ── DEVICES tab ── */}
                        {activeProfileTab === "devices" && (
                          <div style={{ padding:"12px 18px" }}>
                            {uDevs.length === 0
                              ? <p style={{ textAlign:"center", color:"var(--atlas-text-label)", fontSize:"12px", padding:"16px 0" }}>No devices registered.</p>
                              : uDevs.map((d, i) => (
                                <div key={d.id} style={{ padding:"10px 0", borderBottom: i < uDevs.length-1 ? "1px solid var(--atlas-divider-subtle)" : "none" }}>
                                  <div style={{ display:"flex", gap:"10px", alignItems:"flex-start" }}>
                                    <div style={{ width:"30px", height:"30px", borderRadius:"7px", background:"#0F1225", border:"1px solid var(--atlas-border-color)", display:"flex", alignItems:"center", justifyContent:"center", flexShrink:0, fontSize:"14px" }}>🖥</div>
                                    <div style={{ flex:1 }}>
                                      <p style={{ fontSize:"12px", color:"var(--atlas-text-body)", fontWeight:500, margin:0 }}>{d.device_name || "Unknown Device"}</p>
                                      <p style={{ fontSize:"9px", color:"#3ECFB2", fontFamily:"monospace", margin:"3px 0" }}>UUID: {d.hardware_uuid}</p>
                                      <div style={{ display:"flex", gap:"12px" }}>
                                        <p style={{ fontSize:"10px", color:"var(--atlas-text-label)", margin:0 }}>Last seen: {fmtDateTime(d.last_seen)}</p>
                                        <p style={{ fontSize:"10px", color:"var(--atlas-text-faint)", margin:0 }}>Added: {fmtShort(d.created_at)}</p>
                                      </div>
                                    </div>
                                    <button
                                      onClick={() => kickDevice(d.id, d.device_name)}
                                      disabled={kickingDeviceId === d.id}
                                      style={{ fontSize:"10px", fontWeight:600, color:"#E05555", background:"rgba(224,85,85,0.08)", border:"1px solid rgba(224,85,85,0.3)", borderRadius:"6px", padding:"5px 10px", cursor:"pointer", flexShrink:0 }}
                                    >
                                      {kickingDeviceId === d.id ? "Removing…" : "Remove / Kick"}
                                    </button>
                                  </div>
                                </div>
                              ))
                            }
                          </div>
                        )}

                        {/* ── SUPPORT tab ── */}
                        {activeProfileTab === "support" && (
                          <div style={{ maxHeight:"420px", overflowY:"auto" }}>
                            {uTickets.length === 0
                              ? <p style={{ padding:"24px", textAlign:"center", color:"var(--atlas-text-label)", fontSize:"12px" }}>No support tickets.</p>
                              : uTickets.map((t:any) => (
                                <div key={t.id} style={{ padding:"12px 18px", borderBottom:"1px solid #0A0C18" }}>
                                  <div style={{ display:"flex", gap:"8px", alignItems:"center", marginBottom:"6px", flexWrap:"wrap" }}>
                                    <span style={{ fontSize:"9px", fontWeight:700, padding:"2px 7px", borderRadius:"4px", border:`1px solid ${t.status==="open"?"rgba(224,85,85,0.3)":"rgba(62,207,178,0.3)"}`, color:t.status==="open"?"#E05555":"#3ECFB2", background:t.status==="open"?"rgba(224,85,85,0.08)":"rgba(62,207,178,0.08)" }}>{t.status.toUpperCase()}</span>
                                    <span style={{ fontSize:"11px", color:"#A0A8C8", fontWeight:500 }}>{t.issue_type}</span>
                                    {t.product_name && <span style={{ fontSize:"10px", color:"var(--text-muted)", padding:"1px 6px", background:"var(--atlas-icon-bg)", borderRadius:"4px", border:"1px solid var(--atlas-border-color)" }}>{t.product_name}</span>}
                                    <span style={{ marginLeft:"auto", fontSize:"10px", color:"var(--atlas-text-label)" }}>{fmt(t.created_at)}</span>
                                  </div>
                                  <p style={{ fontSize:"11px", color:"var(--text-muted)", margin:0, lineHeight:1.55 }}>{t.message}</p>
                                  {t.attached_log_content && (
                                    <details style={{ marginTop:"8px" }}>
                                      <summary style={{ fontSize:"10px", color:"#3ECFB2", cursor:"pointer" }}>View attached log</summary>
                                      <pre style={{ margin:"5px 0 0", padding:"8px", background:"var(--atlas-bg)", color:"var(--text-muted)", fontSize:"9px", lineHeight:1.6, borderRadius:"6px", border:"1px solid var(--atlas-border-color)", maxHeight:"160px", overflowY:"auto", whiteSpace:"pre-wrap", wordBreak:"break-word" }}>{t.attached_log_content}</pre>
                                    </details>
                                  )}
                                  {t.status === "open" && (
                                    <button onClick={() => resolveTicket(t.id)} style={{ marginTop:"8px", padding:"4px 10px", borderRadius:"6px", border:"1px solid rgba(62,207,178,0.3)", background:"rgba(62,207,178,0.08)", color:"#3ECFB2", fontSize:"10px", fontWeight:600, cursor:"pointer" }}>Mark Resolved</button>
                                  )}
                                </div>
                              ))
                            }
                          </div>
                        )}

                      </div>
                    )
                  })()}
                </div>
              )
            })}
          </div>
        )}

        {/* ── DEVICES ── */}
        {tab === "devices" && (
          <div style={card}>
            <div style={{ padding:"14px 18px", borderBottom:"1px solid var(--atlas-divider)" }}>
              <p style={{...labelStyle}}>All Registered Devices — {devices.length} total</p>
            </div>
            {devices.length === 0
              ? <div style={{padding:"40px",textAlign:"center",color:"var(--atlas-text-label)"}}>No devices.</div>
              : devices.map(d => (
                <div key={d.id} style={{ padding:"12px 18px", borderBottom:"1px solid var(--atlas-divider-subtle)", display:"flex", gap:"14px", alignItems:"flex-start" }}>
                  <div style={{ flex:1, minWidth:0 }}>
                    <p style={{fontSize:"13px",color:"var(--atlas-text-body)",fontWeight:500,margin:0}}>{d.device_name||"Unknown"}</p>
                    <p style={{fontSize:"9px",color:"#3ECFB2",fontFamily:"monospace",margin:"3px 0"}}>UUID: {d.hardware_uuid}</p>
                    <p style={{fontSize:"11px",color:"var(--text-muted)",margin:0}}>{emailOf(d.user_id)}</p>
                  </div>
                  <div style={{ textAlign:"right", flexShrink:0, display:"flex", flexDirection:"column", alignItems:"flex-end", gap:"6px" }}>
                    <p style={{fontSize:"10px",color:"#A0A8C8",margin:0}}>Last: {fmtDateTime(d.last_seen)}</p>
                    <p style={{fontSize:"10px",color:"var(--atlas-text-label)",margin:0}}>Added: {fmtShort(d.created_at)}</p>
                    <button
                      onClick={() => kickDevice(d.id, d.device_name)}
                      disabled={kickingDeviceId === d.id}
                      style={{ fontSize:"10px", fontWeight:600, color:"#E05555", background:"rgba(224,85,85,0.08)", border:"1px solid rgba(224,85,85,0.3)", borderRadius:"6px", padding:"5px 10px", cursor:"pointer" }}
                    >
                      {kickingDeviceId === d.id ? "Removing…" : "Remove / Kick"}
                    </button>
                  </div>
                </div>
              ))
            }
          </div>
        )}

        {/* ── SUSPENDED ACCOUNTS ── */}
        {tab === "suspended" && (() => {
          const suspendedUsers = users.filter(u => u.atlas_suspended)
          return (
            <div style={card}>
              <div style={{ padding:"14px 18px", borderBottom:"1px solid var(--atlas-divider)" }}>
                <p style={{...labelStyle}}>Suspended Accounts — {suspendedUsers.length} total</p>
                <p style={{ fontSize:"10px", color:"var(--atlas-text-label)", marginTop:"6px" }}>
                  Indefinite lockouts — either an admin ban or an auto-suspension after a cancelled subscriber's 10-day free-reactivation window expired. Logs, devices, history, and recovery kits remain fully intact and viewable below; only login/install access is blocked. Lifting a suspension here works regardless of the reason.
                </p>
              </div>
              {suspendedUsers.length === 0
                ? <div style={{padding:"40px",textAlign:"center",color:"var(--atlas-text-label)"}}>No suspended accounts.</div>
                : suspendedUsers.map(u => (
                  <div key={u.id} style={{ padding:"14px 18px", borderBottom:"1px solid var(--atlas-divider-subtle)", display:"flex", alignItems:"center", gap:"14px" }}>
                    <div style={{ flex:1, minWidth:0 }}>
                      <p style={{fontSize:"13px",color:"var(--atlas-text-body)",fontWeight:500,margin:0}}>{u.email}</p>
                      <div style={{ display:"flex", gap:"8px", alignItems:"center", marginTop:"3px" }}>
                        <span style={{ fontSize:"9px", fontWeight:700, padding:"2px 7px", borderRadius:"4px", border:"1px solid rgba(224,85,85,0.4)", color:"#E05555", background:"rgba(224,85,85,0.1)" }}>
                          {u.atlas_suspended_reason === 'grace_expired' ? 'GRACE PERIOD EXPIRED' : 'ADMIN SUSPENDED'}
                        </span>
                        <span style={{ fontSize:"10px", color:"var(--atlas-text-label)" }}>Joined {fmt(u.created_at)}</span>
                      </div>
                    </div>
                    <button
                      onClick={() => setSuspended(u.id, false)}
                      disabled={suspendingId === u.id}
                      style={{ fontSize:"11px", fontWeight:600, color:"#3ECFB2", background:"rgba(62,207,178,0.08)", border:"1px solid rgba(62,207,178,0.3)", borderRadius:"7px", padding:"6px 14px", cursor:"pointer", flexShrink:0 }}
                    >
                      {suspendingId === u.id ? "Lifting…" : "Lift Suspension"}
                    </button>
                  </div>
                ))
              }
            </div>
          )
        })()}

        {/* ── CANCELLATION FEEDBACK ── */}
        {tab === "feedback" && (
          <div style={card}>
            <div style={{ padding:"14px 18px", borderBottom:"1px solid var(--atlas-divider)" }}>
              <p style={{...labelStyle}}>Cancellation Feedback — {cancellationFeedback.length} total</p>
              <p style={{ fontSize:"10px", color:"var(--atlas-text-label)", marginTop:"6px" }}>
                Optional, skippable reason/feedback collected at the cancel-confirmation modal. Most recent first.
              </p>
            </div>
            {cancellationFeedback.length === 0
              ? <div style={{padding:"40px",textAlign:"center",color:"var(--atlas-text-label)"}}>No cancellation feedback yet.</div>
              : cancellationFeedback.map((f: any) => (
                <div key={f.id} style={{ padding:"14px 18px", borderBottom:"1px solid var(--atlas-divider-subtle)" }}>
                  <div style={{ display:"flex", alignItems:"center", justifyContent:"space-between", gap:"10px", marginBottom:"4px" }}>
                    <p style={{fontSize:"13px",color:"var(--atlas-text-body)",fontWeight:500,margin:0}}>{f.email}</p>
                    <span style={{ fontSize:"10px", color:"var(--atlas-text-label)" }}>{fmt(f.created_at)}</span>
                  </div>
                  {f.reason && (
                    <span style={{ display:"inline-block", fontSize:"9px", fontWeight:700, padding:"2px 7px", borderRadius:"4px", border:"1px solid rgba(240,160,48,0.4)", color:"#F0A030", background:"rgba(240,160,48,0.1)", marginBottom:"6px" }}>
                      {String(f.reason).toUpperCase()}
                    </span>
                  )}
                  {f.feedback && (
                    <p style={{ fontSize:"12px", color:"var(--atlas-text-mid)", lineHeight:1.5, margin:0 }}>{f.feedback}</p>
                  )}
                </div>
              ))
            }
          </div>
        )}

        {/* ── LOGS ── */}
        {tab === "logs" && (
          <div style={{ display:"flex", flexDirection:"column", gap:"12px" }}>
            <div style={{ display:"flex", gap:"6px", flexWrap:"wrap", alignItems:"center" }}>
              {["all","install","uninstall","failed","crashed","confirmed-success","install-demo"].map(t => (
                <button key={t} onClick={() => setLogFilter(t)} style={{ fontSize:"9px", fontWeight:700, letterSpacing:"1.5px", textTransform:"uppercase", padding:"4px 10px", borderRadius:"6px", border:"none", cursor:"pointer", background:logFilter===t?"var(--atlas-border-color)":"transparent", color:logFilter===t?"var(--atlas-fg)":"var(--atlas-text-label)" }}>{t}</button>
              ))}
              <span style={{ marginLeft:"auto", fontSize:"11px", color:"var(--atlas-text-faint)" }}>{filteredLogs.length} logs</span>
            </div>
            <div style={card}>
              {filteredLogs.length === 0
                ? <div style={{padding:"40px",textAlign:"center",color:"var(--atlas-text-label)"}}>No logs.</div>
                : filteredLogs.map(l => (
                  <div key={l.id} style={{ borderBottom:"1px solid var(--atlas-divider-subtle)" }}>
                    <button onClick={() => setExpandedLog(expandedLog===l.id?null:l.id)} style={{ width:"100%", background:"none", border:"none", cursor:"pointer", padding:"11px 18px", display:"flex", alignItems:"center", gap:"10px", textAlign:"left" }}>
                      <span style={{ fontSize:"8px", fontWeight:800, letterSpacing:"1px", padding:"2px 7px", borderRadius:"3px", background:logTypeBg(l.log_type??"install"), color:logTypeColor(l.log_type??"install"), flexShrink:0 }}>{(l.log_type??"install").toUpperCase()}</span>
                      <span style={{ fontSize:"12px", color:"#A8B4D0", flex:1, overflow:"hidden", textOverflow:"ellipsis", whiteSpace:"nowrap" }}>{l.app_name??l.filename}</span>
                      <span style={{ fontSize:"10px", color:"var(--atlas-text-mid)", flexShrink:0 }}>{emailOf(l.user_id)}</span>
                      <span style={{ fontSize:"10px", color:"var(--atlas-text-faint)", flexShrink:0 }}>{fmtShort(l.installed_at)}</span>
                    </button>
                    {expandedLog===l.id && l.content && (
                      <pre style={{ margin:0, padding:"12px 18px", background:"var(--atlas-bg)", color:"var(--text-muted)", fontSize:"10px", lineHeight:1.65, overflowX:"auto", whiteSpace:"pre-wrap", wordBreak:"break-word", maxHeight:"360px", overflowY:"auto" }}>{l.content}</pre>
                    )}
                  </div>
                ))
              }
            </div>
          </div>
        )}

        {/* ── SUPPORT ── */}
        {tab === "support" && (
          <div style={{ display:"flex", flexDirection:"column", gap:"10px" }}>
            {/* Filter row */}
            <div style={{ display:"flex", gap:"6px", alignItems:"center" }}>
              {["all","open","resolved"].map(s => {
                const count = s === "all" ? tickets.length : tickets.filter((t:any) => t.status === s).length
                return (
                  <button key={s} onClick={() => {}} style={{ fontSize:"9px", fontWeight:700, letterSpacing:"1px", textTransform:"uppercase", padding:"4px 10px", borderRadius:"6px", border:"none", cursor:"default", background:"transparent", color:"var(--atlas-text-label)" }}>
                    {s} ({count})
                  </button>
                )
              })}
              <span style={{ marginLeft:"auto", fontSize:"10px", color:"var(--atlas-text-faint)" }}>{openTickets.length} open</span>
            </div>

            {tickets.length === 0 && <div style={{...card,padding:"40px",textAlign:"center",color:"var(--atlas-text-label)"}}>No tickets yet.</div>}
            {tickets.map((t: any) => {
              const isExpanded = expandedTicket === t.id
              const isOpen = t.status === "open"
              return (
                <div key={t.id} style={{ ...card, border: isOpen ? "1px solid rgba(224,85,85,0.15)" : "1px solid var(--atlas-divider)" }}>
                  {/* Row — always visible */}
                  <button
                    onClick={() => setExpandedTicket(isExpanded ? null : t.id)}
                    style={{ width:"100%", background:"none", border:"none", cursor:"pointer", padding:"14px 18px", display:"flex", alignItems:"center", gap:"10px", textAlign:"left" }}
                  >
                    <div style={{ flex:1, minWidth:0 }}>
                      <div style={{ display:"flex", alignItems:"center", gap:"8px", flexWrap:"wrap" }}>
                        <span style={{ fontSize:"11px", fontWeight:700, color:"var(--atlas-text-body)" }}>{t.email}</span>
                        <span style={{ fontSize:"9px", fontWeight:700, letterSpacing:"1px", padding:"2px 7px", borderRadius:"4px",
                          border:`1px solid ${isOpen?"rgba(224,85,85,0.3)":"rgba(62,207,178,0.3)"}`,
                          color:isOpen?"#E05555":"#3ECFB2",
                          background:isOpen?"rgba(224,85,85,0.08)":"rgba(62,207,178,0.08)"
                        }}>{t.status.toUpperCase()}</span>
                        <span style={{ fontSize:"10px", color:"var(--text-muted)", padding:"2px 7px", borderRadius:"4px", background:"var(--atlas-icon-bg)", border:"1px solid var(--atlas-border-color)" }}>{t.issue_type}</span>
                        {t.product_name && <span style={{ fontSize:"10px", color:"#A0A8C8", padding:"2px 7px", borderRadius:"4px", background:"var(--atlas-icon-bg)", border:"1px solid var(--atlas-border-color)" }}>{t.product_name}</span>}
                      </div>
                      <p style={{ margin:"5px 0 0", fontSize:"12px", color:"#525270", overflow:"hidden", textOverflow:"ellipsis", whiteSpace:"nowrap" }}>{t.message}</p>
                    </div>
                    <div style={{ display:"flex", alignItems:"center", gap:"10px", flexShrink:0 }}>
                      <span style={{ fontSize:"10px", color:"var(--atlas-text-faint)" }}>{fmt(t.created_at)}</span>
                      <span style={{ fontSize:"10px", color:"var(--atlas-text-label)" }}>{isExpanded ? "▲" : "▼"}</span>
                    </div>
                  </button>

                  {/* Expanded detail */}
                  {isExpanded && (
                    <div style={{ borderTop:"1px solid var(--atlas-divider)", padding:"18px" }}>
                      {/* Meta row */}
                      <div style={{ display:"grid", gridTemplateColumns:"repeat(auto-fill,minmax(180px,1fr))", gap:"10px", marginBottom:"16px" }}>
                        {[
                          { label:"From", value: t.email },
                          { label:"Status", value: t.status },
                          { label:"Issue Type", value: t.issue_type },
                          { label:"Submitted", value: fmt(t.created_at) },
                          t.product_name && { label:"Product", value: t.product_name },
                          t.product_status && { label:"Product Status", value: t.product_status },
                          t.attached_log_id && { label:"Log ID", value: t.attached_log_id },
                        ].filter(Boolean).map((row: any) => (
                          <div key={row.label} style={{ padding:"10px 12px", background:"var(--atlas-bg)", borderRadius:"8px", border:"1px solid var(--atlas-divider)" }}>
                            <p style={{ margin:"0 0 3px", fontSize:"9px", fontWeight:700, letterSpacing:"1px", textTransform:"uppercase", color:"var(--atlas-text-label)" }}>{row.label}</p>
                            <p style={{ margin:0, fontSize:"12px", color:"#A0A8C8", wordBreak:"break-all" }}>{row.value}</p>
                          </div>
                        ))}
                      </div>

                      {/* Full message */}
                      <div style={{ marginBottom:"16px" }}>
                        <p style={{ margin:"0 0 8px", fontSize:"9px", fontWeight:700, letterSpacing:"1px", textTransform:"uppercase", color:"var(--atlas-text-label)" }}>Message</p>
                        <div style={{ padding:"14px", background:"var(--atlas-bg)", borderRadius:"8px", border:"1px solid var(--atlas-divider)" }}>
                          <p style={{ margin:0, fontSize:"13px", color:"#C0C8E8", lineHeight:1.7, whiteSpace:"pre-wrap" }}>{t.message}</p>
                        </div>
                      </div>

                      {/* Attached log */}
                      {t.attached_log_content && (
                        <div style={{ marginBottom:"16px" }}>
                          <p style={{ margin:"0 0 8px", fontSize:"9px", fontWeight:700, letterSpacing:"1px", textTransform:"uppercase", color:"var(--atlas-text-label)" }}>Attached Log</p>
                          <pre style={{ margin:0, padding:"12px", background:"var(--atlas-bg)", color:"var(--text-muted)", fontSize:"10px", lineHeight:1.6, borderRadius:"8px", border:"1px solid var(--atlas-border-color)", maxHeight:"240px", overflowY:"auto", whiteSpace:"pre-wrap", wordBreak:"break-word" }}>{t.attached_log_content}</pre>
                        </div>
                      )}

                      {/* Actions */}
                      <div style={{ display:"flex", gap:"8px" }}>
                        {isOpen && (
                          <button
                            onClick={() => resolveTicket(t.id)}
                            style={{ padding:"8px 18px", borderRadius:"8px", border:"1px solid rgba(62,207,178,0.35)", background:"rgba(62,207,178,0.08)", color:"#3ECFB2", fontSize:"12px", fontWeight:600, cursor:"pointer" }}
                          >
                            ✓ Mark Resolved
                          </button>
                        )}
                        <button
                          onClick={() => setExpandedTicket(null)}
                          style={{ padding:"8px 14px", borderRadius:"8px", border:"1px solid var(--atlas-border-color)", background:"transparent", color:"#525270", fontSize:"12px", cursor:"pointer" }}
                        >
                          Close
                        </button>
                      </div>
                    </div>
                  )}
                </div>
              )
            })}
          </div>
        )}

        {/* ── FAILURES ── */}
        {tab === "failures" && (
          <div style={{ display:"flex", flexDirection:"column", gap:"12px" }}>
            {Object.keys(failuresByProduct).length > 0 && (
              <div style={card}>
                <div style={{ padding:"12px 18px", borderBottom:"1px solid var(--atlas-divider)" }}>
                  <p style={{...labelStyle}}>Failures by Product</p>
                </div>
                <div style={{ padding:"12px 18px", display:"flex", flexWrap:"wrap", gap:"8px" }}>
                  {Object.entries(failuresByProduct).sort((a,b)=>b[1].length-a[1].length).map(([name, fs]) => (
                    <div key={name} onClick={() => setFailureFilter(name === failureFilter ? "all" : name)} style={{ padding:"6px 12px", borderRadius:"7px", background: failureFilter===name?"rgba(224,85,85,0.15)":"var(--atlas-icon-bg)", border: failureFilter===name?"1px solid rgba(224,85,85,0.4)":"1px solid var(--atlas-border-color)", cursor:"pointer" }}>
                      <span style={{ fontSize:"11px", color:"#C0C8E8" }}>{name}</span>
                      <span style={{ marginLeft:"8px", fontSize:"11px", fontWeight:700, color: fs.length >= 3?"#E05555":fs.length>=2?"#F0A030":"var(--text-muted)" }}>{fs.length}x</span>
                    </div>
                  ))}
                </div>
              </div>
            )}
            <div style={{ display:"flex", gap:"6px", flexWrap:"wrap", alignItems:"center" }}>
              {["all","open","investigating","fixed","wont_fix"].map(s => (
                <button key={s} onClick={() => setFailureFilter(s)} style={{ fontSize:"9px", fontWeight:700, letterSpacing:"1px", textTransform:"uppercase", padding:"4px 10px", borderRadius:"6px", border:"none", cursor:"pointer", background:failureFilter===s?"var(--atlas-border-color)":"transparent", color:failureFilter===s?"var(--atlas-fg)":"var(--atlas-text-label)" }}>{s.replace("_"," ")}</button>
              ))}
              <span style={{ marginLeft:"auto", fontSize:"11px", color:"var(--atlas-text-faint)" }}>{filteredFails.length} failures</span>
            </div>
            <div style={card}>
              {filteredFails.length === 0
                ? <div style={{padding:"40px",textAlign:"center",color:"var(--atlas-text-label)"}}>No failures matching filter.</div>
                : filteredFails.map((f: any) => (
                  <div key={f.id} style={{ borderBottom:"1px solid var(--atlas-divider-subtle)" }}>
                    <button onClick={() => setExpandedFailure(expandedFailure===f.id?null:f.id)} style={{ width:"100%", background:"none", border:"none", cursor:"pointer", padding:"12px 18px", display:"flex", alignItems:"center", gap:"10px", textAlign:"left" }}>
                      <span style={{ fontSize:"8px", fontWeight:800, padding:"2px 7px", borderRadius:"3px", background:`${failTypeColor(f.failure_type??"")}18`, color:failTypeColor(f.failure_type??""), flexShrink:0 }}>{(f.failure_type??"unknown").toUpperCase()}</span>
                      <span style={{ fontSize:"12px", color:"#C0C8E8", fontWeight:500, flex:1, overflow:"hidden", textOverflow:"ellipsis", whiteSpace:"nowrap" }}>{f.product_name}</span>
                      <span style={{ fontSize:"10px", color:"var(--text-muted)", flexShrink:0 }}>{f.device_name}</span>
                      <span style={{ fontSize:"9px", fontWeight:700, padding:"2px 7px", borderRadius:"4px", border:`1px solid ${fixStatusColor(f.admin_fix_status)}44`, color:fixStatusColor(f.admin_fix_status), background:`${fixStatusColor(f.admin_fix_status)}11`, flexShrink:0 }}>{(f.admin_fix_status??"open").toUpperCase()}</span>
                      <span style={{ fontSize:"10px", color:"var(--atlas-text-faint)", flexShrink:0 }}>{fmtShort(f.created_at)}</span>
                    </button>
                    {expandedFailure===f.id && (
                      <div style={{ borderTop:"1px solid var(--atlas-divider)", padding:"16px 18px", display:"flex", flexDirection:"column", gap:"14px" }}>
                        <div style={{ display:"grid", gridTemplateColumns:"1fr 1fr", gap:"10px" }}>
                          {[["File", f.source_filename],["Step", f.failure_step],["macOS", f.macos_version],["UUID", f.hardware_uuid]].map(([k,v]) => v ? (
                            <div key={k}><p style={{...labelStyle}}>{k}</p><p style={{ fontSize:"11px", color:"#A0A8C8", margin:0, fontFamily: k==="UUID"?"monospace":"inherit" }}>{v}</p></div>
                          ) : null)}
                        </div>
                        <div>
                          <p style={{...labelStyle}}>Failure Reason</p>
                          <p style={{ fontSize:"11px", color:"#E05555", margin:0, lineHeight:1.5 }}>{f.failure_reason}</p>
                        </div>
                        {f.steps_attempted?.length > 0 && (
                          <div>
                            <p style={{...labelStyle}}>Steps Attempted</p>
                            <div style={{ display:"flex", flexDirection:"column", gap:"3px" }}>
                              {f.steps_attempted.map((s: string, i: number) => (
                                <p key={i} style={{ fontSize:"10px", color:"var(--text-muted)", margin:0, fontFamily:"monospace" }}>{s}</p>
                              ))}
                            </div>
                          </div>
                        )}
                        {f.install_log && (
                          <details>
                            <summary style={{ fontSize:"10px", color:"#3ECFB2", cursor:"pointer" }}>Full install log</summary>
                            <pre style={{ margin:"6px 0 0", padding:"10px", background:"var(--atlas-bg)", color:"var(--text-muted)", fontSize:"9px", lineHeight:1.6, borderRadius:"6px", border:"1px solid var(--atlas-border-color)", maxHeight:"300px", overflowY:"auto", whiteSpace:"pre-wrap", wordBreak:"break-word" }}>{f.install_log}</pre>
                          </details>
                        )}
                        {f.admin_note && fixingId !== f.id && (
                          <div style={{ background:"rgba(62,207,178,0.06)", border:"1px solid rgba(62,207,178,0.2)", borderRadius:"8px", padding:"10px 14px" }}>
                            <p style={{...labelStyle,color:"#3ECFB2"}}>Admin Note</p>
                            <p style={{ fontSize:"11px", color:"#A0A8C8", margin:0, lineHeight:1.5 }}>{f.admin_note}</p>
                          </div>
                        )}
                        {fixingId === f.id ? (
                          <div style={{ background:"var(--atlas-icon-bg)", border:"1px solid var(--atlas-border-color)", borderRadius:"10px", padding:"14px" }}>
                            <p style={{...labelStyle,marginBottom:"10px"}}>Write Fix Note</p>
                            <textarea value={fixNote} onChange={e => setFixNote(e.target.value)} placeholder="Describe the fix…" style={{ ...inputStyle, height:"80px", resize:"vertical", fontFamily:"inherit", lineHeight:1.5 }} />
                            <div style={{ display:"flex", gap:"8px", marginTop:"10px", flexWrap:"wrap" }}>
                              {["investigating","fixed","wont_fix"].map(s => (
                                <button key={s} onClick={() => setFixStatus(s)} style={{ fontSize:"9px", fontWeight:700, padding:"4px 10px", borderRadius:"6px", border:`1px solid ${fixStatus===s?fixStatusColor(s)+"66":"var(--atlas-border-color)"}`, background:fixStatus===s?`${fixStatusColor(s)}15`:"transparent", color:fixStatus===s?fixStatusColor(s):"var(--atlas-text-label)", cursor:"pointer" }}>{s.replace("_"," ").toUpperCase()}</button>
                              ))}
                              <div style={{ marginLeft:"auto", display:"flex", gap:"6px" }}>
                                <button onClick={() => setFixingId(null)} style={{ fontSize:"11px", color:"var(--text-muted)", background:"none", border:"1px solid var(--atlas-border-color)", borderRadius:"7px", padding:"5px 12px", cursor:"pointer" }}>Cancel</button>
                                <button onClick={saveFailureFix} disabled={fixSaving} style={{ fontSize:"11px", fontWeight:600, color:"#08090E", background:"#3ECFB2", border:"none", borderRadius:"7px", padding:"5px 14px", cursor:"pointer" }}>{fixSaving?"Saving…":"Save Fix"}</button>
                              </div>
                            </div>
                          </div>
                        ) : (
                          <div style={{ display:"flex", gap:"8px" }}>
                            <button onClick={() => { setFixingId(f.id); setFixNote(f.admin_note??""); setFixStatus(f.admin_fix_status??"investigating") }} style={{ fontSize:"11px", fontWeight:600, color:"#3ECFB2", background:"rgba(62,207,178,0.08)", border:"1px solid rgba(62,207,178,0.25)", borderRadius:"7px", padding:"6px 14px", cursor:"pointer" }}>
                              {f.admin_note ? "Edit Fix Note" : "Write Fix"}
                            </button>
                            <button onClick={() => { setTab("patterns"); setNewPattern(true); setPatternDraft({ product_name: f.product_name, match_patterns_text: f.product_name.toLowerCase(), pkg_receipt_ids_text:"", installed_paths_text: (f.steps_attempted??[]).join("\n"), hosts_entries_text:"" }) }} style={{ fontSize:"11px", color:"#A855F7", background:"rgba(168,85,247,0.08)", border:"1px solid rgba(168,85,247,0.25)", borderRadius:"7px", padding:"6px 14px", cursor:"pointer" }}>
                              Create Pattern Fix →
                            </button>
                          </div>
                        )}
                      </div>
                    )}
                  </div>
                ))
              }
            </div>
          </div>
        )}

        {/* ── PATTERNS ── */}
        {tab === "patterns" && (
          <div style={{ display:"flex", flexDirection:"column", gap:"12px" }}>
            <div style={{ display:"flex", justifyContent:"space-between", alignItems:"center" }}>
              <p style={{...labelStyle,margin:0}}>{patterns.length} known install patterns (cloud TITAN MEMORY™)</p>
              <button onClick={() => { setNewPattern(true); setEditingPattern(null); setPatternDraft({ product_name:"", match_patterns_text:"", pkg_receipt_ids_text:"", installed_paths_text:"", hosts_entries_text:"" }) }} style={{ fontSize:"11px", fontWeight:600, color:"#08090E", background:"#3ECFB2", border:"none", borderRadius:"8px", padding:"6px 16px", cursor:"pointer" }}>+ New Pattern</button>
            </div>
            {(newPattern || editingPattern) && (
              <div style={{ ...card, padding:"20px" }}>
                <p style={{ fontSize:"13px", fontWeight:600, color:"var(--atlas-fg)", marginBottom:"16px" }}>{newPattern?"New Pattern":"Edit Pattern: "}{editingPattern?.product_name}</p>
                <div style={{ display:"flex", flexDirection:"column", gap:"12px" }}>
                  <div><span style={labelStyle}>Product Name</span><input style={inputStyle} value={patternDraft.product_name??""} onChange={e => setPatternDraft((d: any)=>({...d,product_name:e.target.value}))} placeholder="e.g. Baby Audio Smooth Operator Pro" /></div>
                  <div><span style={labelStyle}>Match Patterns (one per line)</span><textarea style={{...inputStyle,height:"70px",resize:"vertical",fontFamily:"monospace"}} value={patternDraft.match_patterns_text??""} onChange={e => setPatternDraft((d: any)=>({...d,match_patterns_text:e.target.value}))} placeholder={"baby audio smooth operator\nsmooth operator pro"} /></div>
                  <div><span style={labelStyle}>PKG Receipt IDs (one per line)</span><textarea style={{...inputStyle,height:"60px",resize:"vertical",fontFamily:"monospace"}} value={patternDraft.pkg_receipt_ids_text??""} onChange={e => setPatternDraft((d: any)=>({...d,pkg_receipt_ids_text:e.target.value}))} placeholder="com.babyaudio.smoothoperator" /></div>
                  <div><span style={labelStyle}>Installed Paths (one per line)</span><textarea style={{...inputStyle,height:"70px",resize:"vertical",fontFamily:"monospace"}} value={patternDraft.installed_paths_text??""} onChange={e => setPatternDraft((d: any)=>({...d,installed_paths_text:e.target.value}))} placeholder="/Library/Audio/Plug-Ins/Components/SmoothOperator.component" /></div>
                  <div><span style={labelStyle}>Hosts Entries to Block (one per line)</span><textarea style={{...inputStyle,height:"60px",resize:"vertical",fontFamily:"monospace"}} value={patternDraft.hosts_entries_text??""} onChange={e => setPatternDraft((d: any)=>({...d,hosts_entries_text:e.target.value}))} placeholder="activation.babyaud.io" /></div>
                  <div style={{ display:"flex", gap:"8px", justifyContent:"flex-end" }}>
                    <button onClick={() => { setNewPattern(false); setEditingPattern(null) }} style={{ fontSize:"11px", color:"var(--text-muted)", background:"none", border:"1px solid var(--atlas-border-color)", borderRadius:"7px", padding:"6px 14px", cursor:"pointer" }}>Cancel</button>
                    <button onClick={savePattern} disabled={patternSaving} style={{ fontSize:"11px", fontWeight:600, color:"#08090E", background:"#3ECFB2", border:"none", borderRadius:"7px", padding:"6px 16px", cursor:"pointer" }}>{patternSaving?"Saving…":"Save Pattern"}</button>
                  </div>
                </div>
              </div>
            )}
            <div style={card}>
              {patterns.length === 0
                ? <div style={{padding:"40px",textAlign:"center",color:"var(--atlas-text-label)"}}>No patterns yet. They appear here as users install products successfully.</div>
                : patterns.map((p: any) => (
                  <div key={p.id} style={{ borderBottom:"1px solid var(--atlas-divider-subtle)", padding:"12px 18px", display:"flex", alignItems:"flex-start", gap:"12px" }}>
                    <div style={{ flex:1, minWidth:0 }}>
                      <div style={{ display:"flex", alignItems:"center", gap:"8px", marginBottom:"4px" }}>
                        <p style={{ fontSize:"13px", color:"var(--atlas-text-body)", fontWeight:500, margin:0 }}>{p.product_name}</p>
                        {p.admin_verified && <span style={{ fontSize:"8px", fontWeight:800, letterSpacing:"1px", padding:"2px 6px", borderRadius:"3px", background:"rgba(62,207,178,0.1)", color:"#3ECFB2", border:"1px solid rgba(62,207,178,0.2)" }}>ADMIN VERIFIED</span>}
                        <span style={{ fontSize:"10px", color:"#3ECFB2", marginLeft:"auto" }}>{p.success_count} confirmed install{p.success_count!==1?"s":""}</span>
                      </div>
                      <div style={{ display:"flex", gap:"6px", flexWrap:"wrap" }}>
                        {(p.match_patterns??[]).slice(0,4).map((m: string) => (
                          <span key={m} style={{ fontSize:"9px", color:"var(--text-muted)", fontFamily:"monospace", padding:"2px 6px", background:"var(--atlas-icon-bg)", borderRadius:"4px", border:"1px solid var(--atlas-border-color)" }}>{m}</span>
                        ))}
                        {(p.match_patterns??[]).length > 4 && <span style={{fontSize:"9px",color:"var(--atlas-text-faint)"}}>+{p.match_patterns.length-4} more</span>}
                      </div>
                      {(p.hosts_entries??[]).length > 0 && <p style={{ fontSize:"9px", color:"#E05555", margin:"4px 0 0", fontFamily:"monospace" }}>blocks: {p.hosts_entries.join(", ")}</p>}
                    </div>
                    <div style={{ display:"flex", gap:"6px", flexShrink:0 }}>
                      <button onClick={() => { setEditingPattern(p); setNewPattern(false); setPatternDraft({ product_name:p.product_name, match_patterns_text:(p.match_patterns??[]).join("\n"), pkg_receipt_ids_text:(p.pkg_receipt_ids??[]).join("\n"), installed_paths_text:(p.installed_paths??[]).join("\n"), hosts_entries_text:(p.hosts_entries??[]).join("\n") }) }} style={{ fontSize:"10px", color:"#A0A8C8", background:"var(--atlas-icon-bg)", border:"1px solid var(--atlas-border-color)", borderRadius:"6px", padding:"4px 10px", cursor:"pointer" }}>Edit</button>
                      <button onClick={() => deletePattern(p.id)} style={{ fontSize:"10px", color:"#E05555", background:"rgba(224,85,85,0.08)", border:"1px solid rgba(224,85,85,0.2)", borderRadius:"6px", padding:"4px 10px", cursor:"pointer" }}>Delete</button>
                    </div>
                  </div>
                ))
              }
            </div>

            {/* ── TITAN MEMORY entries (admin-confirmed, not yet in install_patterns) ── */}
            <div style={{ display:"flex", justifyContent:"space-between", alignItems:"center", marginTop:"8px" }}>
              <p style={{...labelStyle,margin:0}}>TITAN MEMORY™ — Admin confirmed ({titanMemory.length} entries)</p>
            </div>
            <div style={card}>
              {titanMemory.length === 0
                ? <div style={{padding:"40px",textAlign:"center",color:"var(--atlas-text-label)"}}>No titan_memory entries yet.</div>
                : titanMemory.map((tm: any) => {
                  const steps: any[] = Array.isArray(tm.steps) ? tm.steps : []
                  const alreadyPromoted = patterns.some((p: any) => p.product_name.toLowerCase().trim() === tm.product_name.toLowerCase().trim())
                  return (
                    <div key={tm.id} style={{ borderBottom:"1px solid var(--atlas-divider-subtle)", padding:"12px 18px", display:"flex", alignItems:"flex-start", gap:"12px" }}>
                      <div style={{ flex:1, minWidth:0 }}>
                        <div style={{ display:"flex", alignItems:"center", gap:"8px", marginBottom:"4px" }}>
                          <p style={{ fontSize:"13px", color:"var(--atlas-text-body)", fontWeight:500, margin:0 }}>{tm.product_name}</p>
                          {alreadyPromoted && <span style={{ fontSize:"8px", fontWeight:800, letterSpacing:"1px", padding:"2px 6px", borderRadius:"3px", background:"rgba(62,207,178,0.1)", color:"#3ECFB2", border:"1px solid rgba(62,207,178,0.2)" }}>IN PATTERNS</span>}
                          <span style={{ fontSize:"10px", color:"var(--text-muted)", marginLeft:"auto" }}>{fmt(tm.confirmed_at)}</span>
                        </div>
                        <div style={{ display:"flex", gap:"6px", flexWrap:"wrap" }}>
                          {steps.slice(0,4).map((s: any, i: number) => (
                            <span key={i} style={{ fontSize:"9px", color:"var(--text-muted)", fontFamily:"monospace", padding:"2px 6px", background:"var(--atlas-icon-bg)", borderRadius:"4px", border:"1px solid var(--atlas-border-color)" }}>{s.file ?? s.note ?? s.type}</span>
                          ))}
                          {steps.length > 4 && <span style={{fontSize:"9px",color:"var(--atlas-text-faint)"}}>+{steps.length-4} more steps</span>}
                        </div>
                        {(tm.hosts_entries??[]).length > 0 && <p style={{ fontSize:"9px", color:"#E05555", margin:"4px 0 0", fontFamily:"monospace" }}>blocks: {tm.hosts_entries.join(", ")}</p>}
                        {tm.confirmed_by && <p style={{ fontSize:"9px", color:"var(--atlas-text-faint)", margin:"2px 0 0" }}>confirmed by: {tm.confirmed_by}</p>}
                      </div>
                      <button
                        onClick={() => promoteToPattern(tm)}
                        disabled={promotingId === tm.id || alreadyPromoted}
                        style={{ fontSize:"10px", fontWeight:600, color: alreadyPromoted?"var(--atlas-text-label)":"#08090E", background: alreadyPromoted?"var(--atlas-divider)":"#A855F7", border:"none", borderRadius:"6px", padding:"5px 12px", cursor: alreadyPromoted?"default":"pointer", flexShrink:0, opacity: promotingId===tm.id ? 0.6 : 1 }}
                      >
                        {promotingId === tm.id ? "Promoting…" : alreadyPromoted ? "Promoted" : "Promote to Learn"}
                      </button>
                    </div>
                  )
                })
              }
            </div>
          </div>
        )}

        {/* ── RECOVERY KITS ── */}
        {tab === "recovery-kits" && (
          <div style={{ display: "flex", flexDirection: "column", gap: "10px" }}>
            <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
              <p style={{ fontSize: "11px", color: "var(--atlas-text-label)", margin: 0 }}>Subscribers with cloud-synced Recovery Kits.</p>
              <button onClick={loadRkSubscribers} disabled={rkSubscribersLoading}
                style={{ fontSize: "10px", fontWeight: 600, color: "#3ECFB2", background: "none", border: "1px solid var(--atlas-kit-btn-border)", borderRadius: "6px", padding: "5px 12px", cursor: "pointer", opacity: rkSubscribersLoading ? 0.5 : 1 }}>
                {rkSubscribersLoading ? "Loading…" : "Refresh"}
              </button>
            </div>

            {rkSubscribers.length === 0 && !rkSubscribersLoading && (
              <div style={{ background: "var(--atlas-card)", border: "1px solid var(--atlas-border-color)", borderRadius: "12px", padding: "32px", textAlign: "center", color: "var(--atlas-text-label)", fontSize: "12px" }}>
                No subscribers with cloud Recovery Kits.{" "}
                <button onClick={loadRkSubscribers} style={{ color: "#3ECFB2", background: "none", border: "none", cursor: "pointer", fontSize: "12px" }}>Load</button>
              </div>
            )}

            {rkSubscribers.map(sub => {
              const isExpanded = expandedRkUser === sub.user_id
              const kits = rkUserKits[sub.user_id] ?? []
              return (
                <div key={sub.user_id} style={{ background: "var(--atlas-card)", border: "1px solid var(--atlas-border-color)", borderRadius: "12px", overflow: "hidden" }}>
                  <div
                    onClick={() => {
                      if (isExpanded) { setExpandedRkUser(null); return }
                      setExpandedRkUser(sub.user_id)
                      if (!rkUserKits[sub.user_id]) loadRkUserKits(sub.user_id)
                    }}
                    style={{ padding: "14px 18px", display: "flex", alignItems: "center", justifyContent: "space-between", cursor: "pointer" }}
                  >
                    <div>
                      <p style={{ fontSize: "12px", fontWeight: 600, color: "#C0C8E8", margin: 0 }}>{sub.email}</p>
                      <p style={{ fontSize: "10px", color: "var(--atlas-text-label)", margin: "2px 0 0" }}>{sub.kit_count} kit{sub.kit_count !== 1 ? "s" : ""} · Latest {fmt(sub.latest_kit_date)}</p>
                    </div>
                    <span style={{ fontSize: "12px", color: "var(--atlas-text-label)" }}>{isExpanded ? "▲" : "▼"}</span>
                  </div>

                  {isExpanded && (
                    <div style={{ borderTop: "1px solid var(--atlas-divider-faint)" }}>
                      {rkUserKitsLoading === sub.user_id ? (
                        <div style={{ padding: "16px 18px", color: "var(--atlas-text-label)", fontSize: "11px" }}>Loading kits…</div>
                      ) : kits.length === 0 ? (
                        <div style={{ padding: "16px 18px", color: "var(--atlas-text-label)", fontSize: "11px" }}>No kits found.</div>
                      ) : kits.map((kit, i) => (
                        <div key={kit.id} style={{ padding: "12px 18px", borderBottom: i < kits.length - 1 ? "1px solid var(--atlas-divider-faint)" : "none", display: "flex", alignItems: "center", justifyContent: "space-between", gap: "12px" }}>
                          <div>
                            <p style={{ fontSize: "11px", fontWeight: 600, color: "#C0C8E8", margin: 0 }}>{fmtDateTime(kit.generated_at)}</p>
                            <p style={{ fontSize: "10px", color: "var(--atlas-text-label)", margin: "2px 0 0" }}>
                              {kit.record_count} items{kit.device_name ? ` · ${kit.device_name}` : ""} · ATLAS {kit.atlas_version}
                            </p>
                          </div>
                          <div style={{ display: "flex", gap: "6px", flexShrink: 0 }}>
                            <button
                              onClick={() => adminDownloadKit(kit.id, "atlaskit")}
                              disabled={rkDownloading === `${kit.id}-atlaskit`}
                              style={{ fontSize: "10px", fontWeight: 600, color: "#3ECFB2", background: "none", border: "1px solid var(--atlas-kit-btn-border)", borderRadius: "6px", padding: "5px 10px", cursor: "pointer", opacity: rkDownloading === `${kit.id}-atlaskit` ? 0.5 : 1 }}
                            >
                              {rkDownloading === `${kit.id}-atlaskit` ? "…" : ".atlaskit"}
                            </button>
                            <button
                              onClick={() => adminDownloadKit(kit.id, "txt")}
                              disabled={rkDownloading === `${kit.id}-txt`}
                              style={{ fontSize: "10px", fontWeight: 600, color: "var(--text-muted)", background: "none", border: "1px solid var(--atlas-divider)", borderRadius: "6px", padding: "5px 10px", cursor: "pointer", opacity: rkDownloading === `${kit.id}-txt` ? 0.5 : 1 }}
                            >
                              {rkDownloading === `${kit.id}-txt` ? "…" : ".txt"}
                            </button>
                          </div>
                        </div>
                      ))}
                    </div>
                  )}
                </div>
              )
            })}
          </div>
        )}

      </main>
    </div>
  )
}
