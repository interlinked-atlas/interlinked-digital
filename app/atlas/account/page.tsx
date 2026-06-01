import { redirect } from "next/navigation"
import { createClient } from "@/lib/supabase/server"
import { createClient as createAdminClient } from "@supabase/supabase-js"
import AccountDashboard from "./account-dashboard"

const supabaseAdmin = createAdminClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
)

export default async function AccountPage() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect("/auth/login")

  // Subscription details (populated by Stripe webhook)
  const { data: subscription } = await supabaseAdmin
    .from("subscriptions")
    .select("*")
    .eq("user_id", user.id)
    .order("updated_at", { ascending: false })
    .limit(1)
    .single()

  // Profile (plan + status, used by ATLAS app)
  const { data: profile } = await supabaseAdmin
    .from("profiles")
    .select("plan, subscription_status")
    .eq("id", user.id)
    .single()

  // Devices registered by ATLAS app
  const { data: devices } = await supabaseAdmin
    .from("devices")
    .select("id, device_name, hardware_uuid, last_seen, created_at")
    .eq("user_id", user.id)
    .order("last_seen", { ascending: false })

  return (
    <AccountDashboard
      user={user}
      subscription={subscription ?? null}
      profile={profile ?? null}
      devices={devices ?? []}
    />
  )
}
