import { NextRequest, NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
)

const ADMIN_EMAIL = 'titantinstaller@gmail.com'

// install_counts is the authoritative usage-gate table behind reserve_install_slot /
// confirm_install_reservation / release_install_reservation (service-role-only RPCs —
// see supabase/migrations/20260925200532_restrict_install_limit_rpc_execution_to_service_role.sql).
// Its RLS policy is intentionally service-role-only with no admin-email bypass, unlike
// profiles/subscriptions/devices/install_logs/support_tickets/monthly_install_counts.
// This route restores the admin dashboard's read access the same way admin-data/route.ts
// does for install_logs, without weakening the table's RLS policy.
export async function GET(req: NextRequest) {
  const token = req.headers.get('authorization')?.replace('Bearer ', '').trim()
  if (!token) return NextResponse.json({ error: 'Missing authorization' }, { status: 401 })

  const { data: { user }, error: authError } = await supabase.auth.getUser(token)
  if (authError || !user) return NextResponse.json({ error: 'Invalid token' }, { status: 401 })
  if (user.email?.toLowerCase() !== ADMIN_EMAIL.toLowerCase()) {
    return NextResponse.json({ error: 'Forbidden' }, { status: 403 })
  }

  const { data, error } = await supabase
    .from('install_counts')
    .select('user_id, hardware_uuid, installs_this_month, period_start')
    .order('updated_at', { ascending: false })

  if (error) return NextResponse.json({ error: error.message }, { status: 500 })

  return NextResponse.json({ counts: data ?? [] })
}
