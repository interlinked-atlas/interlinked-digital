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
    { data: devices },
    { data: logs },
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
    supabaseAdmin
      .from("devices")
      .select("id, device_name, hardware_uuid, last_seen, created_at")
      .eq("user_id", user.id)
      .order("last_seen", { ascending: false }),
    supabaseAdmin
      .from("atlas_logs")
      .select("id, log_type, app_name, filename, content, device_name, hardware_uuid, created_at")
      .eq("user_id", user.id)
      .order("created_at", { ascending: false })
      .limit(50),
  ])

  return (
    <AccountDashboard
      user={user}
      subscription={subscription ?? null}
      profile={profile ?? null}
      devices={devices ?? []}
      logs={logs ?? []}
      isAdmin={isAdmin}
    />
  )
}
