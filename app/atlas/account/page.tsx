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

  const [subResult, profileResult, devicesResult, logsResult] = await Promise.all([
    supabase
      .from("subscriptions")
      .select("id, plan, status, current_period_end, cancel_at_period_end, stripe_customer_id, stripe_subscription_id")
      .eq("user_id", user.id)
      .order("updated_at", { ascending: false })
      .limit(1)
      .maybeSingle(),
    supabase
      .from("profiles")
      .select("plan, subscription_status")
      .eq("id", user.id)
      .maybeSingle(),
    supabase
      .from("devices")
      .select("id, device_name, hardware_uuid, last_seen, created_at")
      .eq("user_id", user.id)
      .order("created_at", { ascending: false }),
    // Use admin client to read logs (bypasses RLS in case user policy is restrictive)
    supabaseAdmin
      .from("install_logs")
      .select("id, log_type, app_name, filename, content, device_name, hardware_uuid, installed_at")
      .eq("user_id", user.id)
      .order("installed_at", { ascending: false })
      .limit(100),
  ])

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const subscription = (subResult.data as any) ?? null
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const profile = (profileResult.data as any) ?? null
  const devices = (devicesResult.data ?? []) as any[]
  const rawLogs = (logsResult.data ?? []) as any[]

  const logs = rawLogs.map((l: any) => ({
    id: l.id,
    log_type: l.log_type ?? "install",
    app_name: l.app_name ?? null,
    filename: l.filename ?? l.app_name ?? "log",
    content: l.content ?? null,
    device_name: l.device_name ?? null,
    hardware_uuid: l.hardware_uuid ?? null,
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
