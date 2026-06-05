"use client"

import { useState, useEffect, useCallback } from "react"
import Link from "next/link"
import { useRouter } from "next/navigation"
import { createClient } from "@/lib/supabase/client"

const ADMIN_EMAIL = "titantinstaller@gmail.com"

type Tab = "subscribers" | "devices" | "logs" | "support"

const planColor   = (p: string) => p === "pro" ? "#F0A030" : "#5B8DEF"
const statusColor = (s: string) => s === "active" ? "#3ECFB2" : s === "cancelled" || s === "canceled" ? "#E05555" : "#F0A030"
const logTypeColor = (t: string) => t === "install" ? "#3ECFB2" : t === "failed" ? "#E05555" : t === "uninstall" ? "#5B8DEF" : "#F0A030"
const logTypeBg   = (t: string) => t === "install" ? "rgba(62,207,178,0.1)" : t === "failed" ? "rgba(224,85,85,0.1)" : t === "uninstall" ? "rgba(91,141,239,0.1)" : "rgba(240,160,48,0.1)"

export default function AdminPage() {
  const [tab, setTab]             = useState<Tab>("subscribers")
  const [authed, setAuthed]       = useState(false)
  const [loading, setLoading]     = useState(true)
  const [token, setToken]         = useState("")
  const [users, setUsers]         = useState<any[]>([])
  const [devices, setDevices]     = useState<any[]>([])
  const [logs, setLogs]           = useState<any[]>([])
  const [tickets, setTickets]     = useState<any[]>([])
  const [subscriptions, setSubs]  = useState<any[]>([])
  const [expandedUser, setExpandedUser] = useState<string | null>(null)
  const [expandedLog, setExpandedLog]   = useState<string | null>(null)
  const [logFilter, setLogFilter] = useState("all")
  const [userEmail, setUserEmail] = useState("")
  const [lastRefresh, setLastRefresh] = useState<Date | null>(null)
  const router = useRouter()
  const supabase = createClient()

  const loadAll = useCallback(async (tok: string) => {
    setLoading(true)
    try {
      const res = await fetch("/api/atlas/admin-data", {
        headers: { Authorization: `Bearer ${tok}` }
      })
      if (!res.ok) { router.replace("/atlas/account"); return }
      const data = await res.json()
      setUsers(data.profiles      ?? [])
      setDevices(data.devices     ?? [])
      setLogs(data.logs           ?? [])
      setTickets(data.tickets     ?? [])
      setSubs(data.subscriptions  ?? [])
      setLastRefresh(new Date())
    } finally {
      setLoading(false)
    }
  }, [router])

  useEffect(() => {
    supabase.auth.getSession().then(({ data: { session } }) => {
      if (!session || session.user.email?.toLowerCase() !== ADMIN_EMAIL.toLowerCase()) {
        router.replace("/atlas/account")
        return
      }
      setUserEmail(session.user.email ?? "")
      setToken(session.access_token)
      setAuthed(true)
      loadAll(session.access_token)
    })
  }, [])

  async function resolveTicket(id: string) {
    await fetch("/api/atlas/admin-data", {
      method: "PATCH",
      headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
      body: JSON.stringify({ action: "resolve_ticket", id })
    })
    setTickets(t => t.map(x => x.id === id ? { ...x, status: "resolved" } : x))
  }

  if (!authed) return null

  const proUsers      = users.filter(u => u.plan === "pro")
  const standardUsers = users.filter(u => u.plan === "standard")
  const activeUsers   = users.filter(u => u.subscription_status === "active")
  const openTickets   = tickets.filter(t => t.status === "open")
  const filteredLogs  = logFilter === "all" ? logs : logs.filter(l => l.log_type === logFilter)

  function userDevices(uid: string) { return devices.filter(d => d.user_id === uid) }
  function userLogs(uid: string)    { return logs.filter(l => l.user_id === uid) }
  function userEmail2(uid: string)  { return users.find(u => u.id === uid)?.email ?? uid.slice(0, 8) + "…" }
  function userSub(uid: string)     { return subscriptions.find(s => s.user_id === uid) }

  const card: React.CSSProperties = { background: "#0C0E1C", borderRadius: "12px", border: "1px solid #1E2240", overflow: "hidden" }

  const chip = (label: string, val: number | string, color: string) => (
    <div key={label} style={{ background: "#0C0E1C", border: "1px solid #1E2240", borderRadius: "10px", padding: "12px 18px", minWidth: "90px" }}>
      <p style={{ fontSize: "8px", color: "#353860", letterSpacing: "2px", marginBottom: "4px", textTransform: "uppercase" }}>{label}</p>
      <p style={{ fontSize: "22px", fontWeight: 700, color }}>{val}</p>
    </div>
  )

  return (
    <div style={{ minHeight: "100vh", background: "#07080F", color: "#E8ECFF" }}>
      {/* Header */}
      <header style={{ borderBottom: "1px solid #1E2240", position: "sticky", top: 0, zIndex: 50, background: "rgba(7,8,15,0.95)", backdropFilter: "blur(12px)", padding: "14px 28px", display: "flex", alignItems: "center", justifyContent: "space-between" }}>
        <div style={{ display: "flex", alignItems: "center", gap: "12px" }}>
          <Link href="/atlas/account" style={{ fontSize: "10px", letterSpacing: "1px", color: "#6B7399", textDecoration: "none", padding: "5px 10px", border: "1px solid #1E2240", borderRadius: "6px" }}>← ACCOUNT</Link>
          <span style={{ fontSize: "18px", letterSpacing: "6px" }}>ATLAS</span>
          <span style={{ fontSize: "9px", color: "#F0A030", letterSpacing: "3px", padding: "2px 8px", border: "1px solid rgba(240,160,48,0.3)", borderRadius: "4px", background: "rgba(240,160,48,0.06)" }}>ADMIN</span>
        </div>
        <div style={{ display: "flex", gap: "12px", alignItems: "center" }}>
          {lastRefresh && <span style={{ fontSize: "10px", color: "#252845" }}>Updated {lastRefresh.toLocaleTimeString()}</span>}
          <button onClick={() => loadAll(token)} disabled={loading} style={{ fontSize: "10px", padding: "5px 12px", borderRadius: "6px", border: "1px solid #1E2240", background: "#0C0E1C", color: loading ? "#252845" : "#6B7399", cursor: loading ? "default" : "pointer" }}>
            {loading ? "Loading…" : "↻ Refresh"}
          </button>
          <span style={{ fontSize: "11px", color: "#4A5280" }}>{userEmail}</span>
        </div>
      </header>

      <main style={{ maxWidth: "1100px", margin: "0 auto", padding: "28px 24px" }}>

        {/* Stats */}
        <div style={{ display: "flex", flexWrap: "wrap", gap: "10px", marginBottom: "24px" }}>
          {chip("Total Users",   users.length,         "#E8ECFF")}
          {chip("Active Subs",   activeUsers.length,   "#3ECFB2")}
          {chip("Pro",           proUsers.length,      "#F0A030")}
          {chip("Standard",      standardUsers.length, "#5B8DEF")}
          {chip("Devices",       devices.length,       "#E8ECFF")}
          {chip("Install Logs",  logs.filter(l => l.log_type === "install").length, "#3ECFB2")}
          {chip("Total Logs",    logs.length,          "#6B7399")}
          {chip("Open Tickets",  openTickets.length,   openTickets.length > 0 ? "#E05555" : "#353860")}
        </div>

        {/* Tabs */}
        <div style={{ display: "flex", gap: "4px", marginBottom: "20px", background: "#0C0E1C", border: "1px solid #1E2240", borderRadius: "10px", padding: "4px" }}>
          {(["subscribers","devices","logs","support"] as Tab[]).map(t => (
            <button key={t} onClick={() => setTab(t)} style={{
              flex: 1, padding: "8px", borderRadius: "7px", border: "none", cursor: "pointer", fontSize: "11px", fontWeight: 600, letterSpacing: "0.5px", textTransform: "capitalize",
              background: tab === t ? "#1E2240" : "transparent",
              color: tab === t ? "#E8ECFF" : "#353860",
            }}>
              {t}{t === "support" && openTickets.length > 0 && <span style={{ marginLeft: "6px", background: "#E05555", color: "#fff", fontSize: "9px", fontWeight: 800, padding: "1px 5px", borderRadius: "8px" }}>{openTickets.length}</span>}
            </button>
          ))}
        </div>

        {loading && (
          <div style={{ textAlign: "center", padding: "60px", color: "#353860", fontSize: "13px" }}>Loading…</div>
        )}

        {/* ── SUBSCRIBERS ── */}
        {!loading && tab === "subscribers" && (
          <div style={{ display: "flex", flexDirection: "column", gap: "10px" }}>
            {users.length === 0 && <div style={{ ...card, padding: "40px", textAlign: "center", color: "#353860" }}>No users yet.</div>}
            {users.map(u => {
              const uDevs = userDevices(u.id)
              const uLogs = userLogs(u.id)
              const sub   = userSub(u.id)
              const open  = expandedUser === u.id
              return (
                <div key={u.id} style={card}>
                  <button onClick={() => setExpandedUser(open ? null : u.id)} style={{ width: "100%", background: "none", border: "none", cursor: "pointer", padding: "14px 18px", display: "flex", alignItems: "center", gap: "12px", textAlign: "left" }}>
                    <div style={{ width: "8px", height: "8px", borderRadius: "50%", background: statusColor(u.subscription_status), boxShadow: `0 0 6px ${statusColor(u.subscription_status)}88`, flexShrink: 0 }} />
                    <div style={{ flex: 1, minWidth: 0 }}>
                      <p style={{ fontSize: "13px", color: "#D0D8F0", fontWeight: 500, margin: 0, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{u.email}</p>
                      <p style={{ fontSize: "10px", color: "#353860", margin: "2px 0 0", letterSpacing: "0.5px" }}>
                        Joined {new Date(u.created_at).toLocaleDateString("en-US", { month: "short", day: "numeric", year: "numeric" })}
                        {u.privacy_consent && <span style={{ color: "rgba(62,207,178,0.5)", marginLeft: "8px" }}>· log sync on</span>}
                      </p>
                    </div>
                    <div style={{ display: "flex", gap: "6px", alignItems: "center", flexShrink: 0 }}>
                      <span style={{ fontSize: "9px", fontWeight: 800, padding: "3px 8px", borderRadius: "5px", border: `1px solid ${planColor(u.plan)}44`, color: planColor(u.plan), background: `${planColor(u.plan)}11` }}>{u.plan.toUpperCase()}</span>
                      <span style={{ fontSize: "9px", fontWeight: 700, padding: "3px 8px", borderRadius: "5px", border: `1px solid ${statusColor(u.subscription_status)}44`, color: statusColor(u.subscription_status), background: `${statusColor(u.subscription_status)}11` }}>{u.subscription_status.toUpperCase()}</span>
                      <span style={{ fontSize: "10px", color: "#252845" }}>{uDevs.length} device{uDevs.length !== 1 ? "s" : ""} · {uLogs.length} log{uLogs.length !== 1 ? "s" : ""}</span>
                      <span style={{ fontSize: "11px", color: open ? "#3ECFB2" : "#353860" }}>{open ? "▲" : "▼"}</span>
                    </div>
                  </button>

                  {open && (
                    <div style={{ borderTop: "1px solid #1A1D30" }}>
                      {/* Subscription detail */}
                      {sub && (
                        <div style={{ padding: "10px 18px", borderBottom: "1px solid #1A1D30", display: "flex", gap: "20px", flexWrap: "wrap" }}>
                          <div>
                            <p style={{ fontSize: "8px", color: "#353860", letterSpacing: "2px", textTransform: "uppercase", margin: "0 0 3px" }}>Stripe Plan</p>
                            <p style={{ fontSize: "12px", color: planColor(sub.plan), margin: 0, fontWeight: 600 }}>{sub.plan.toUpperCase()}</p>
                          </div>
                          <div>
                            <p style={{ fontSize: "8px", color: "#353860", letterSpacing: "2px", textTransform: "uppercase", margin: "0 0 3px" }}>Status</p>
                            <p style={{ fontSize: "12px", color: statusColor(sub.status), margin: 0, fontWeight: 600 }}>{sub.status.toUpperCase()}</p>
                          </div>
                          {sub.current_period_end && (
                            <div>
                              <p style={{ fontSize: "8px", color: "#353860", letterSpacing: "2px", textTransform: "uppercase", margin: "0 0 3px" }}>Renews</p>
                              <p style={{ fontSize: "12px", color: sub.cancel_at_period_end ? "#E05555" : "#A8B4D0", margin: 0 }}>
                                {new Date(sub.current_period_end).toLocaleDateString("en-US", { month: "short", day: "numeric", year: "numeric" })}
                                {sub.cancel_at_period_end && <span style={{ color: "#E05555", marginLeft: "6px" }}>· cancels</span>}
                              </p>
                            </div>
                          )}
                          {sub.stripe_subscription_id && (
                            <div>
                              <p style={{ fontSize: "8px", color: "#353860", letterSpacing: "2px", textTransform: "uppercase", margin: "0 0 3px" }}>Stripe ID</p>
                              <p style={{ fontSize: "10px", color: "#4A5280", fontFamily: "monospace", margin: 0 }}>{sub.stripe_subscription_id}</p>
                            </div>
                          )}
                        </div>
                      )}

                      {/* Devices */}
                      <div style={{ padding: "12px 18px", borderBottom: "1px solid #1A1D30" }}>
                        <p style={{ fontSize: "9px", fontWeight: 700, letterSpacing: "2px", color: "#353860", textTransform: "uppercase", marginBottom: "8px" }}>Registered Devices ({uDevs.length})</p>
                        {uDevs.length === 0
                          ? <p style={{ fontSize: "11px", color: "#252845" }}>No devices registered.</p>
                          : uDevs.map(d => (
                            <div key={d.id} style={{ display: "flex", gap: "12px", alignItems: "flex-start", padding: "8px 0", borderBottom: "1px solid #13151F" }}>
                              <div style={{ width: "28px", height: "28px", borderRadius: "6px", background: "#0A0D1C", border: "1px solid #1E2240", display: "flex", alignItems: "center", justifyContent: "center", flexShrink: 0, fontSize: "12px" }}>🖥</div>
                              <div style={{ flex: 1, minWidth: 0 }}>
                                <p style={{ fontSize: "12px", color: "#C0C8E8", fontWeight: 500, margin: 0 }}>{d.device_name || "Unknown Mac"}</p>
                                <p style={{ fontSize: "10px", color: "#353860", fontFamily: "monospace", margin: "2px 0" }}>UUID: {d.hardware_uuid}</p>
                                <p style={{ fontSize: "10px", color: "#252845", margin: 0 }}>
                                  Last active: {new Date(d.last_seen).toLocaleString("en-US", { month: "short", day: "numeric", year: "numeric", hour: "2-digit", minute: "2-digit" })}
                                  {" · "}Registered: {new Date(d.created_at).toLocaleDateString("en-US", { month: "short", day: "numeric", year: "numeric" })}
                                </p>
                              </div>
                            </div>
                          ))
                        }
                      </div>

                      {/* Logs */}
                      {uLogs.length > 0 && (
                        <div>
                          <p style={{ fontSize: "9px", fontWeight: 700, letterSpacing: "2px", color: "#353860", textTransform: "uppercase", padding: "10px 18px 6px" }}>Install Logs ({uLogs.length})</p>
                          {uLogs.map(l => (
                            <div key={l.id} style={{ borderBottom: "1px solid #0F1020" }}>
                              <button onClick={() => setExpandedLog(expandedLog === l.id ? null : l.id)} style={{ width: "100%", background: "none", border: "none", cursor: "pointer", padding: "9px 18px", display: "flex", alignItems: "center", gap: "8px", textAlign: "left" }}>
                                <span style={{ fontSize: "8px", fontWeight: 800, letterSpacing: "1px", padding: "2px 6px", borderRadius: "3px", background: logTypeBg(l.log_type ?? "install"), color: logTypeColor(l.log_type ?? "install"), flexShrink: 0 }}>{(l.log_type ?? "install").toUpperCase()}</span>
                                <span style={{ fontSize: "11px", color: "#A8B4D0", flex: 1, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{l.app_name ?? l.filename}</span>
                                {l.device_name && <span style={{ fontSize: "10px", color: "#252845", flexShrink: 0 }}>{l.device_name}</span>}
                                <span style={{ fontSize: "10px", color: "#252845", flexShrink: 0 }}>{new Date(l.installed_at).toLocaleDateString("en-US", { month: "short", day: "numeric" })}</span>
                              </button>
                              {expandedLog === l.id && l.content && (
                                <pre style={{ margin: 0, padding: "10px 18px", background: "#07080F", color: "#6B7399", fontSize: "10px", lineHeight: 1.6, overflowX: "auto", whiteSpace: "pre-wrap", wordBreak: "break-word", maxHeight: "300px", overflowY: "auto" }}>{l.content}</pre>
                              )}
                            </div>
                          ))}
                        </div>
                      )}
                    </div>
                  )}
                </div>
              )
            })}
          </div>
        )}

        {/* ── DEVICES ── */}
        {!loading && tab === "devices" && (
          <div style={card}>
            <div style={{ padding: "14px 18px", borderBottom: "1px solid #1A1D30" }}>
              <p style={{ fontSize: "10px", fontWeight: 700, letterSpacing: "2px", color: "#353860", textTransform: "uppercase" }}>All Registered Devices — {devices.length} total</p>
            </div>
            {devices.length === 0
              ? <div style={{ padding: "40px", textAlign: "center", color: "#353860", fontSize: "13px" }}>No devices registered yet.</div>
              : devices.map(d => (
                <div key={d.id} style={{ padding: "12px 18px", borderBottom: "1px solid #0F1020", display: "flex", gap: "14px", alignItems: "flex-start" }}>
                  <div style={{ width: "32px", height: "32px", borderRadius: "7px", background: "#0A0D1C", border: "1px solid #1E2240", display: "flex", alignItems: "center", justifyContent: "center", flexShrink: 0, fontSize: "14px" }}>🖥</div>
                  <div style={{ flex: 1, minWidth: 0 }}>
                    <p style={{ fontSize: "13px", color: "#D0D8F0", fontWeight: 500, margin: 0 }}>{d.device_name || "Unknown Mac"}</p>
                    <p style={{ fontSize: "10px", color: "#3ECFB2", fontFamily: "monospace", margin: "3px 0" }}>UUID: {d.hardware_uuid}</p>
                    <p style={{ fontSize: "11px", color: "#6B7399", margin: 0 }}>{userEmail2(d.user_id)}</p>
                  </div>
                  <div style={{ textAlign: "right", flexShrink: 0 }}>
                    <p style={{ fontSize: "11px", color: "#A8B4D0", margin: 0 }}>Last active</p>
                    <p style={{ fontSize: "10px", color: "#353860", margin: "2px 0 0" }}>{new Date(d.last_seen).toLocaleString("en-US", { month: "short", day: "numeric", year: "numeric", hour: "2-digit", minute: "2-digit" })}</p>
                    <p style={{ fontSize: "10px", color: "#252845", margin: "2px 0 0" }}>Registered {new Date(d.created_at).toLocaleDateString("en-US", { month: "short", day: "numeric", year: "numeric" })}</p>
                  </div>
                </div>
              ))
            }
          </div>
        )}

        {/* ── LOGS ── */}
        {!loading && tab === "logs" && (
          <div style={{ display: "flex", flexDirection: "column", gap: "12px" }}>
            <div style={{ display: "flex", gap: "6px", flexWrap: "wrap" }}>
              {["all","install","uninstall","failed","crashed"].map(t => (
                <button key={t} onClick={() => setLogFilter(t)} style={{ fontSize: "9px", fontWeight: 700, letterSpacing: "1.5px", textTransform: "uppercase", padding: "4px 10px", borderRadius: "6px", border: "none", cursor: "pointer", background: logFilter === t ? "#1E2240" : "transparent", color: logFilter === t ? "#E8ECFF" : "#353860", outline: logFilter === t ? "1px solid #3E4270" : "none" }}>{t}</button>
              ))}
              <span style={{ marginLeft: "auto", fontSize: "11px", color: "#252845", alignSelf: "center" }}>{filteredLogs.length} logs</span>
            </div>
            <div style={card}>
              {filteredLogs.length === 0
                ? <div style={{ padding: "40px", textAlign: "center", color: "#353860", fontSize: "13px" }}>No logs.</div>
                : filteredLogs.map(l => (
                  <div key={l.id} style={{ borderBottom: "1px solid #0F1020" }}>
                    <button onClick={() => setExpandedLog(expandedLog === l.id ? null : l.id)} style={{ width: "100%", background: "none", border: "none", cursor: "pointer", padding: "11px 18px", display: "flex", alignItems: "center", gap: "10px", textAlign: "left" }}>
                      <span style={{ fontSize: "8px", fontWeight: 800, letterSpacing: "1px", padding: "2px 7px", borderRadius: "3px", background: logTypeBg(l.log_type ?? "install"), color: logTypeColor(l.log_type ?? "install"), flexShrink: 0 }}>{(l.log_type ?? "install").toUpperCase()}</span>
                      <span style={{ fontSize: "12px", color: "#A8B4D0", flex: 1, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{l.app_name ?? l.filename}</span>
                      <span style={{ fontSize: "10px", color: "#4A5280", flexShrink: 0 }}>{userEmail2(l.user_id)}</span>
                      {l.device_name && <span style={{ fontSize: "10px", color: "#252845", flexShrink: 0 }}>{l.device_name}</span>}
                      <span style={{ fontSize: "10px", color: "#252845", flexShrink: 0 }}>{new Date(l.installed_at).toLocaleDateString("en-US", { month: "short", day: "numeric" })}</span>
                    </button>
                    {expandedLog === l.id && l.content && (
                      <pre style={{ margin: 0, padding: "12px 18px", background: "#07080F", color: "#6B7399", fontSize: "10px", lineHeight: 1.65, overflowX: "auto", whiteSpace: "pre-wrap", wordBreak: "break-word", maxHeight: "360px", overflowY: "auto" }}>{l.content}</pre>
                    )}
                  </div>
                ))
              }
            </div>
          </div>
        )}

        {/* ── SUPPORT ── */}
        {!loading && tab === "support" && (
          <div style={{ display: "flex", flexDirection: "column", gap: "10px" }}>
            {tickets.length === 0 && <div style={{ ...card, padding: "40px", textAlign: "center", color: "#353860", fontSize: "13px" }}>No support tickets yet.</div>}
            {tickets.map(t => (
              <div key={t.id} style={{ ...card }}>
                <div style={{ padding: "14px 18px", display: "flex", gap: "12px", alignItems: "flex-start" }}>
                  <div style={{ flex: 1, minWidth: 0 }}>
                    <div style={{ display: "flex", alignItems: "center", gap: "8px", marginBottom: "6px", flexWrap: "wrap" }}>
                      <span style={{ fontSize: "11px", fontWeight: 600, color: "#D0D8F0" }}>{t.email}</span>
                      <span style={{ fontSize: "9px", fontWeight: 700, letterSpacing: "1px", padding: "2px 7px", borderRadius: "4px", border: `1px solid ${t.status === "open" ? "rgba(224,85,85,0.3)" : "rgba(62,207,178,0.3)"}`, color: t.status === "open" ? "#E05555" : "#3ECFB2", background: t.status === "open" ? "rgba(224,85,85,0.08)" : "rgba(62,207,178,0.08)" }}>{t.status.toUpperCase()}</span>
                      <span style={{ fontSize: "10px", color: "#353860", padding: "2px 7px", borderRadius: "4px", background: "#0A0D1C", border: "1px solid #1E2240" }}>{t.issue_type}</span>
                      <span style={{ marginLeft: "auto", fontSize: "10px", color: "#252845" }}>{new Date(t.created_at).toLocaleDateString("en-US", { month: "short", day: "numeric", year: "numeric" })}</span>
                    </div>
                    <p style={{ fontSize: "12px", color: "#8890B0", lineHeight: 1.6, margin: 0 }}>{t.message}</p>
                    {t.attached_log_content && (
                      <details style={{ marginTop: "10px" }}>
                        <summary style={{ fontSize: "10px", color: "#3ECFB2", cursor: "pointer" }}>View attached log</summary>
                        <pre style={{ margin: "6px 0 0", padding: "10px", background: "#07080F", color: "#6B7399", fontSize: "9px", lineHeight: 1.6, borderRadius: "6px", border: "1px solid #1E2240", maxHeight: "200px", overflowY: "auto", whiteSpace: "pre-wrap", wordBreak: "break-word" }}>{t.attached_log_content}</pre>
                      </details>
                    )}
                  </div>
                  {t.status === "open" && (
                    <button onClick={() => resolveTicket(t.id)} style={{ padding: "6px 12px", borderRadius: "7px", border: "1px solid rgba(62,207,178,0.3)", background: "rgba(62,207,178,0.08)", color: "#3ECFB2", fontSize: "11px", fontWeight: 600, cursor: "pointer", flexShrink: 0 }}>
                      Mark Resolved
                    </button>
                  )}
                </div>
              </div>
            ))}
          </div>
        )}
      </main>
    </div>
  )
}
