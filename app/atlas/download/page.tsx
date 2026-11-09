import { redirect } from "next/navigation"
import { createClient } from "@/lib/supabase/server"
import { createClient as createAdminClient } from "@supabase/supabase-js"
import { hasActiveAtlasSubscription } from "@/lib/entitlement"
import DownloadPage from "./download-client"

export const dynamic = 'force-dynamic'

const supabaseAdmin = createAdminClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
)

export default async function Download() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect("/auth/login")

  if (!(await hasActiveAtlasSubscription(supabaseAdmin, user.id))) {
    redirect("/atlas/plans")
  }

  return <DownloadPage />
}
