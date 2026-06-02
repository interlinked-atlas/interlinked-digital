import { redirect } from "next/navigation"
import { createClient } from "@/lib/supabase/server"
import { createClient as createAdminClient } from "@supabase/supabase-js"
import Link from "next/link"

export const dynamic = 'force-dynamic'

const supabaseAdmin = createAdminClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
)

const ADMIN_EMAIL = "titantinstaller@gmail.com"

export default async function AdminPage() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user || user.email?.toLowerCase() !== ADMIN_EMAIL.toLowerCase()) {
    redirect("/atlas/account")
  }

  // All logs — newest first, full content
  const { data: allLogs } = await supabaseAdmin
    .from("install_logs")
    .select("id, user_id, log_type, app_name, filename, content, device_name, hardware_uuid, installed_at")
    .order("installed_at", { ascending: false })
    .limit(1000)

  // All profiles
  const { data: profiles } = await supabaseAdmin
    .from("profiles")
    .select("id, email, plan, subscription_status, created_at, privacy_consent")

  // Group logs by user
  const byUser: Record<string, {
    email: string; plan: string; status: string; consent: boolean
    logs: NonNullable<typeof allLogs>
  }> = {}

  for (const log of (allLogs ?? [])) {
    if (!byUser[log.user_id]) {
      const p = profiles?.find(x => x.id === log.user_id)
      byUser[log.user_id] = {
        email: p?.email ?? log.user_id,
        plan: p?.plan ?? "unknown",
        status: p?.subscription_status ?? "unknown",
        consent: p?.privacy_consent ?? false,
        logs: [],
      }
    }
    byUser[log.user_id].logs.push(log)
  }

  // Include users with no logs too
  for (const p of (profiles ?? [])) {
    if (!byUser[p.id]) {
      byUser[p.id] = { email: p.email, plan: p.plan, status: p.subscription_status, consent: p.privacy_consent ?? false, logs: [] }
    }
  }

  const users = Object.entries(byUser).sort((a, b) => a[1].email.localeCompare(b[1].email))
  const totalLogs = allLogs?.length ?? 0
  const totalInstalls  = allLogs?.filter(l => (l.log_type ?? "install") === "install").length ?? 0
  const totalUninstalls = allLogs?.filter(l => l.log_type === "uninstall").length ?? 0
  const totalFailed    = allLogs?.filter(l => l.log_type === "failed").length ?? 0
  const totalCrashed   = allLogs?.filter(l => l.log_type === "crashed").length ?? 0

  return (
    <div style={{ minHeight: "100vh", background: "#07080F", color: "#E8ECFF" }}>
      <header style={{
        borderBottom: "1px solid #1E2240",
        position: "sticky", top: 0, zIndex: 50,
        background: "rgba(7,8,15,0.92)", backdropFilter: "blur(12px)",
        padding: "14px 24px",
        display: "flex", alignItems: "center", justifyContent: "space-between",
      }}>
        <div style={{ display: "flex", alignItems: "center", gap: "12px" }}>
          <Link href="/atlas/account" style={{
            fontSize: "10px", letterSpacing: "1px", color: "#6B7399",
            textDecoration: "none", padding: "5px 10px",
            border: "1px solid #1E2240", borderRadius: "6px",
          }}>← ACCOUNT</Link>
          <span style={{ fontFamily: "'SF-Intellivised', sans-serif", fontSize: "18px", letterSpacing: "6px", color: "#E8ECFF" }}>ATLAS</span>
          <span style={{ fontSize: "9px", color: "#F0A030", letterSpacing: "3px", padding: "2px 7px", border: "1px solid rgba(240,160,48,0.3)", borderRadius: "4px", background: "rgba(240,160,48,0.06)" }}>ADMIN</span>
        </div>
        <span style={{ fontSize: "11px", color: "#4A5280" }}>{user.email}</span>
      </header>

      <main style={{ maxWidth: "960px", margin: "0 auto", padding: "32px 24px" }}>
        <div style={{ marginBottom: "28px" }}>
          <h1 style={{ fontSize: "20px", fontWeight: 600, color: "#C0C8E8", marginBottom: "16px" }}>User Activity</h1>

          {/* Stats row */}
          <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(120px, 1fr))", gap: "12px", marginBottom: "24px" }}>
            {[
              { label: "USERS", val: users.length, color: "#E8ECFF" },
              { label: "TOTAL LOGS", val: totalLogs, color: "#E8ECFF" },
              { label: "INSTALLS", val: totalInstalls, color: "#3ECFB2" },
              { label: "UNINSTALLS", val: totalUninstalls, color: "#5B8DEF" },
              { label: "FAILED", val: totalFailed, color: "#E05555" },
              { label: "CRASHED", val: totalCrashed, color: "#F0A030" },
            ].map(s => (
              <div key={s.label} style={{ background: "#0C0E1C", borderRadius: "10px", border: "1px solid #1E2240", padding: "12px 16px" }}>
                <p style={{ fontSize: "8px", color: "#353860", letterSpacing: "2px", marginBottom: "4px" }}>{s.label}</p>
                <p style={{ fontSize: "20px", fontWeight: 700, color: s.color }}>{s.val}</p>
              </div>
            ))}
          </div>
        </div>

        {users.length === 0 && (
          <div style={{ textAlign: "center", padding: "60px", background: "#0C0E1C", borderRadius: "12px", border: "1px solid #1E2240", color: "#353860", fontSize: "13px" }}>
            No users yet.
          </div>
        )}

        <div style={{ display: "flex", flexDirection: "column", gap: "16px" }}>
          {users.map(([userId, data]) => (
            <details key={userId} style={{ background: "#0C0E1C", borderRadius: "12px", border: "1px solid #1E2240", overflow: "hidden" }}>
              <summary style={{
                padding: "16px 18px", cursor: "pointer",
                display: "flex", alignItems: "center", gap: "12px",
                listStyle: "none", userSelect: "none",
              }}>
                <div style={{
                  width: "8px", height: "8px", borderRadius: "50%",
                  background: data.status === "active" ? "#3ECFB2" : "#353860", flexShrink: 0,
                }} />
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div style={{ fontSize: "13px", color: "#D0D8F0", fontWeight: 500, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{data.email}</div>
                  <div style={{ fontSize: "10px", color: "#353860", marginTop: "2px", letterSpacing: "1px", display: "flex", gap: "8px" }}>
                    <span>{data.plan.toUpperCase()}</span>
                    <span>·</span>
                    <span>{data.status.toUpperCase()}</span>
                    {data.consent && <span style={{ color: "rgba(62,207,178,0.5)" }}>· LOG SYNC ON</span>}
                  </div>
                </div>
                <div style={{ display: "flex", gap: "6px", flexShrink: 0 }}>
                  {[
                    { type: "install",   color: "#3ECFB2" },
                    { type: "uninstall", color: "#5B8DEF" },
                    { type: "failed",    color: "#E05555" },
                    { type: "crashed",   color: "#F0A030" },
                  ].map(({ type, color }) => {
                    const count = data.logs.filter(l => (l.log_type ?? "install") === type).length
                    if (count === 0) return null
                    return (
                      <span key={type} style={{ fontSize: "9px", fontWeight: 700, padding: "2px 6px", borderRadius: "4px", border: `1px solid ${color}33`, color, background: `${color}11` }}>
                        {count} {type}
                      </span>
                    )
                  })}
                  {data.logs.length === 0 && <span style={{ fontSize: "10px", color: "#252845" }}>no logs</span>}
                </div>
              </summary>

              {data.logs.length > 0 && (
                <div style={{ borderTop: "1px solid #1A1D30" }}>
                  {data.logs.map((log: any) => {
                    const lt = log.log_type ?? "install"
                    const color = lt === "install" ? "#3ECFB2" : lt === "failed" ? "#E05555" : lt === "uninstall" ? "#5B8DEF" : "#F0A030"
                    const bg    = lt === "install" ? "rgba(62,207,178,0.08)" : lt === "failed" ? "rgba(224,85,85,0.08)" : lt === "uninstall" ? "rgba(91,141,239,0.08)" : "rgba(240,160,48,0.08)"
                    return (
                      <details key={log.id} style={{ borderBottom: "1px solid #13151F" }}>
                        <summary style={{
                          padding: "10px 18px", cursor: "pointer",
                          display: "flex", alignItems: "center", gap: "10px",
                          listStyle: "none",
                        }}>
                          <span style={{ fontSize: "8px", fontWeight: 800, letterSpacing: "1.5px", padding: "2px 6px", borderRadius: "3px", background: bg, color, flexShrink: 0 }}>
                            {lt.toUpperCase()}
                          </span>
                          <span style={{ fontSize: "12px", color: "#A8B4D0", flex: 1, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>
                            {log.app_name ?? log.filename ?? "Unknown"}
                          </span>
                          {log.device_name && (
                            <span style={{ fontSize: "10px", color: "#353860", flexShrink: 0 }}>{log.device_name}</span>
                          )}
                          <span style={{ fontSize: "10px", color: "#252845", flexShrink: 0 }}>
                            {new Date(log.installed_at).toLocaleString("en-US", { month: "short", day: "numeric", hour: "2-digit", minute: "2-digit" })}
                          </span>
                        </summary>
                        {log.content && (
                          <pre style={{
                            margin: 0, padding: "12px 18px",
                            background: "#07080F", color: "#6B7399",
                            fontSize: "10px", lineHeight: 1.65,
                            overflowX: "auto", whiteSpace: "pre-wrap",
                            wordBreak: "break-word", maxHeight: "320px", overflowY: "auto",
                            borderTop: "1px solid #13151F",
                          }}>
                            {log.content}
                          </pre>
                        )}
                      </details>
                    )
                  })}
                </div>
              )}
            </details>
          ))}
        </div>
      </main>
    </div>
  )
}
