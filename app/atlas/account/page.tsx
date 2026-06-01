import { redirect } from "next/navigation"
import { createClient } from "@/lib/supabase/server"
import AccountDashboard from "./account-dashboard"

export default async function AccountPage() {
  const supabase = await createClient()
  
  const { data: { user } } = await supabase.auth.getUser()
  
  if (!user) {
    redirect("/auth/login")
  }

  // Get subscription data
  const { data: subscription } = await supabase
    .from("subscriptions")
    .select("*")
    .eq("user_id", user.id)
    .single()

  // Get device activations
  const { data: activations } = await supabase
    .from("device_activations")
    .select("*")
    .eq("user_id", user.id)
    .eq("is_active", true)
    .order("activated_at", { ascending: false })

  return (
    <AccountDashboard 
      user={user} 
      subscription={subscription} 
      activations={activations || []} 
    />
  )
}
