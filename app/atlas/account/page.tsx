import { redirect } from "next/navigation"
import { createClient } from "@/lib/supabase/server"
import { createClient as createAdminClient } from "@supabase/supabase-js"
import AccountDashboard from "./account-dashboard"

const supabaseAdmin = createAdminClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
)

const ADMIN_EMAIL = "titantinstaller@gmail.com"

export default async function AccountPage() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect("/auth/login")

  const isAdmin = user.email?.toLowerCase() === ADMIN_EMAIL.toLowerCase()

  const [
    { data: subscription },
    { data: profile },
    { data: rawDevices },
    { data: rawLogs },
  ] = await Promise.all([
    supabaseAdmin
      .from("subscriptions")
      .select("*")
      .eq("user_id", user.id)
      .order("updated_at", { ascending: false })
      .limit(1)
      .single(),
    supabaseAdmin
      .from("profiles")
      .select("plan, subscription_status")
      .eq("id", user.id)
      .single(),
    // device_activations is where the ATLAS app actually writes
    supabaseAdmin
      .from("device_activations")
      .select("id, device_name, machine_uuid, last_seen_at, activated_at, is_active")
      .eq("user_id", user.id)
      .eq("is_active", true)
      .order("last_seen_at", { ascending: false }),
    // install_logs for install history
    supabaseAdmin
      .from("install_logs")
      .select("id, app_name, installed_at, device_id")
      .eq("user_id", user.id)
      .order("installed_at", { ascending: false })
      .limit(50),
  ])

  // Normalize device_activations → devices shape expected by dashboard
  const devices = (rawDevices ?? []).map(d => ({
    id: d.id,
    device_name: d.device_name,
    hardware_uuid: d.machine_uuid,
    last_seen: d.last_seen_at,
    created_at: d.activated_at,
  }))

  // Normalize install_logs → log shape expected by dashboard
  const logs = (rawLogs ?? []).map(l => ({
    id: l.id,
    log_type: "install",
    app_name: l.app_name,
    filename: l.app_name ?? "install",
    content: null,
    device_name: null,
    hardware_uuid: null,
    created_at: l.installed_at,
  }))

  return (
    <AccountDashboard
      user={user}
      subscription={subscription ?? null}
      profile={profile ?? null}
      devices={devices}
      logs={logs}
      isAdmin={isAdmin}
    />
  )
}
