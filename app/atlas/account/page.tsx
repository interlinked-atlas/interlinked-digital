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
const ATLAS_MONTHLY_LIMIT = 25

export default async function AccountPage() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect("/auth/login")

  const isAdmin = user.email?.toLowerCase() === ADMIN_EMAIL.toLowerCase()

  const [subResult, profileResult, devicesResult, logsResult] = await Promise.all([
    supabase
      .from("subscriptions")
      .select("id, plan, status, current_period_end, cancel_at_period_end, cancelled_at, stripe_customer_id, stripe_subscription_id")
      .eq("user_id", user.id)
      .order("updated_at", { ascending: false })
      .limit(1)
      .maybeSingle(),
    supabase
      .from("profiles")
      .select("plan, subscription_status, billing_interval, billing_anchor_day, monthly_install_limit, atlas_suspended, atlas_suspended_reason")
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

  // Admin can override the standard 25/month cap per account (see
  // /api/atlas/admin/install-limit) — reserve_install_slot/confirm_install_
  // reservation already read this via COALESCE(monthly_install_limit, 25),
  // so this page must match that, not the hardcoded constant, or a
  // support-granted override would show the wrong number here.
  const effectiveMonthlyLimit = profile?.monthly_install_limit ?? ATLAS_MONTHLY_LIMIT

  // Monthly install usage — same billing-anchor-aware period calculation and
  // per-device enforcement (install_counts.hardware_uuid) as reserve_install_slot
  // and /api/atlas/entitlement use; shown per device, not blended into one
  // account-wide number, since the install cap is enforced per device.
  const { data: periodStart } = await supabaseAdmin.rpc('atlas_period_start', {
    p_billing_interval: profile?.billing_interval ?? null,
    p_billing_anchor_day: profile?.billing_anchor_day ?? null,
  })
  const { data: nextPeriodStart } = await supabaseAdmin.rpc('atlas_next_period_start', {
    p_billing_interval: profile?.billing_interval ?? null,
    p_billing_anchor_day: profile?.billing_anchor_day ?? null,
  })
  const { data: countRows } = await supabaseAdmin
    .from('install_counts')
    .select('hardware_uuid, installs_this_month')
    .eq('user_id', user.id)
    .eq('period_start', periodStart)

  const usageByDevice = new Map<string, number>()
  for (const r of countRows ?? []) {
    usageByDevice.set(r.hardware_uuid, (usageByDevice.get(r.hardware_uuid) ?? 0) + (r.installs_this_month ?? 0))
  }
  const monthlyResetDate = nextPeriodStart ? new Date(nextPeriodStart as string).toISOString() : null
  const devicesWithUsage = devices.map(d => {
    const used = usageByDevice.get(d.hardware_uuid) ?? 0
    return {
      ...d,
      monthly_installs_used: used,
      monthly_installs_remaining: Math.max(0, effectiveMonthlyLimit - used),
    }
  })

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
      devices={devicesWithUsage}
      logs={logs}
      isAdmin={isAdmin}
      monthlyLimit={effectiveMonthlyLimit}
      monthlyResetDate={monthlyResetDate}
    />
  )
}
