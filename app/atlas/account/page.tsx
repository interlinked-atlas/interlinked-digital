import { redirect } from "next/navigation"
import { createClient } from "@/lib/supabase/server"
import { createClient as createAdminClient } from "@supabase/supabase-js"
import AccountDashboard from "./account-dashboard"

export const dynamic = 'force-dynamic'

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

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const [subResult, profileResult, devicesResult, logsResult] = await Promise.all([
    supabaseAdmin
      .from("subscriptions")
      .select("id, plan, status, current_period_end, cancel_at_period_end, stripe_customer_id, stripe_subscription_id")
      .eq("user_id", user.id)
      .order("updated_at", { ascending: false })
      .limit(1)
      .maybeSingle(),
    supabaseAdmin
      .from("profiles")
      .select("plan, subscription_status")
      .eq("id", user.id)
      .maybeSingle(),
    supabaseAdmin
      .from("devices")
      .select("id, device_name, hardware_uuid, last_seen, created_at")
      .eq("user_id", user.id)
      .order("created_at", { ascending: false }),
    supabaseAdmin
      .from("install_logs")
      .select("id, app_name, installed_at, device_id")
      .eq("user_id", user.id)
      .order("installed_at", { ascending: false })
      .limit(50),
  ])

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const subscription = (subResult.data as any) ?? null
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const profile = (profileResult.data as any) ?? null
  const devices = (devicesResult.data ?? []) as any[]
  const rawLogs = (logsResult.data ?? []) as any[]

  const logs = rawLogs.map((l: any) => ({
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
      subscription={subscription}
      profile={profile}
      devices={devices}
      logs={logs}
      isAdmin={isAdmin}
    />
  )
}
