import { redirect } from "next/navigation"
import { createClient } from "@/lib/supabase/server"
import { createClient as createAdminClient } from "@supabase/supabase-js"
import Link from "next/link"

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

  // Fetch all install logs with user info
  const { data: allLogs } = await supabaseAdmin
    .from("install_logs")
    .select("id, user_id, app_name, installed_at, device_id")
    .order("installed_at", { ascending: false })
    .limit(500)

  // Fetch all profiles
  const { data: profiles } = await supabaseAdmin
    .from("profiles")
    .select("id, email, plan, subscription_status")

  // Group logs by user_id
  const byUser: Record<string, { email: string; plan: string; status: string; logs: typeof allLogs }> = {}
  for (const log of (allLogs ?? [])) {
    if (!byUser[log.user_id]) {
      const profile = profiles?.find(p => p.id === log.user_id)
      byUser[log.user_id] = {
        email: profile?.email ?? log.user_id,
        plan: profile?.plan ?? "unknown",
        status: profile?.subscription_status ?? "unknown",
        logs: [],
      }
    }
    byUser[log.user_id].logs!.push(log)
  }

  const users = Object.entries(byUser).sort((a, b) => a[1].email.localeCompare(b[1].email))

  return (
    <div className="min-h-screen" style={{ background: "#07080F", color: "#E8ECFF" }}>
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
          <span style={{
            fontFamily: "'SF-Intellivised', sans-serif",
            fontSize: "18px", letterSpacing: "6px", color: "#E8ECFF",
          }}>ATLAS</span>
          <span style={{ fontSize: "9px", color: "#252845", letterSpacing: "3px" }}>ADMIN</span>
        </div>
        <span style={{ fontSize: "11px", color: "#3ECFB2" }}>
          {users.length} user{users.length !== 1 ? "s" : ""} · {allLogs?.length ?? 0} installs total
        </span>
      </header>

      <main style={{ maxWidth: "900px", margin: "0 auto", padding: "32px 24px" }}>
        <h1 style={{ fontSize: "18px", fontWeight: 600, marginBottom: "24px", color: "#C0C8E8" }}>
          User Activity
        </h1>

        {users.length === 0 && (
          <div style={{
            textAlign: "center", padding: "60px",
            background: "#0C0E1C", borderRadius: "12px", border: "1px solid #1E2240",
            color: "#353860", fontSize: "13px",
          }}>
            No installs logged yet. Logs appear here after users run installations in ATLAS.
          </div>
        )}

        <div style={{ display: "flex", flexDirection: "column", gap: "16px" }}>
          {users.map(([userId, data]) => (
            <details key={userId} style={{
              background: "#0C0E1C", borderRadius: "12px",
              border: "1px solid #1E2240", overflow: "hidden",
            }}>
              <summary style={{
                padding: "14px 18px", cursor: "pointer",
                display: "flex", alignItems: "center", justifyContent: "space-between",
                listStyle: "none", userSelect: "none",
              }}>
                <div style={{ display: "flex", alignItems: "center", gap: "12px" }}>
                  <div style={{
                    width: "8px", height: "8px", borderRadius: "50%",
                    background: data.status === "active" ? "#3ECFB2" : "#353860",
                    flexShrink: 0,
                  }} />
                  <div>
                    <div style={{ fontSize: "13px", color: "#D0D8F0", fontWeight: 500 }}>
                      {data.email}
                    </div>
                    <div style={{ fontSize: "10px", color: "#353860", marginTop: "2px", letterSpacing: "1px" }}>
                      {data.plan.toUpperCase()} · {data.status.toUpperCase()}
                    </div>
                  </div>
                </div>
                <span style={{
                  fontSize: "10px", color: "#4A5280", padding: "3px 8px",
                  borderRadius: "5px", border: "1px solid #1E2240", background: "#07080F",
                }}>
                  {data.logs?.length ?? 0} install{(data.logs?.length ?? 0) !== 1 ? "s" : ""}
                </span>
              </summary>

              <div style={{ borderTop: "1px solid #1A1D30" }}>
                {(data.logs ?? []).map((log: any) => (
                  <div key={log.id} style={{
                    padding: "10px 18px", borderBottom: "1px solid #13151F",
                    display: "flex", alignItems: "center", gap: "10px",
                  }}>
                    <span style={{
                      fontSize: "8px", fontWeight: 800, letterSpacing: "1.5px", padding: "2px 6px",
                      borderRadius: "3px",
                      background: "rgba(62,207,178,0.1)",
                      color: "#3ECFB2",
                    }}>INSTALL</span>
                    <span style={{ fontSize: "12px", color: "#A8B4D0", flex: 1 }}>
                      {log.app_name ?? "Unknown"}
                    </span>
                    <span style={{ fontSize: "10px", color: "#353860" }}>
                      {new Date(log.installed_at).toLocaleString("en-US", {
                        month: "short", day: "numeric",
                        hour: "2-digit", minute: "2-digit",
                      })}
                    </span>
                  </div>
                ))}
              </div>
            </details>
          ))}
        </div>
      </main>
    </div>
  )
}
