import { NextRequest, NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
)

const ADMIN_EMAIL = 'titantinstaller@gmail.com'

export async function GET(req: NextRequest) {
  const token = req.headers.get('authorization')?.replace('Bearer ', '')
  if (!token) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

  const { data: { user }, error: authErr } = await supabase.auth.getUser(token)
  if (authErr || !user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (user.email?.toLowerCase() !== ADMIN_EMAIL.toLowerCase()) {
    return NextResponse.json({ error: 'Forbidden' }, { status: 403 })
  }

  // Aggregate: one row per subscriber who has at least one active kit
  const { data, error } = await supabase
    .from('recovery_kits')
    .select('user_id, id, generated_at')
    .eq('is_deleted', false)
    .order('generated_at', { ascending: false })

  if (error) return NextResponse.json({ error: error.message }, { status: 500 })

  // Group by user_id
  const byUser: Record<string, { kit_count: number; latest_kit_date: string }> = {}
  for (const row of data ?? []) {
    if (!byUser[row.user_id]) {
      byUser[row.user_id] = { kit_count: 0, latest_kit_date: row.generated_at }
    }
    byUser[row.user_id].kit_count++
  }

  // Fetch emails from profiles table
  const userIds = Object.keys(byUser)
  const { data: profiles } = await supabase
    .from('profiles')
    .select('id, email')
    .in('id', userIds)

  const emailMap: Record<string, string> = {}
  for (const p of profiles ?? []) {
    emailMap[p.id] = p.email ?? p.id
  }

  const subscribers = userIds.map(uid => ({
    user_id:         uid,
    email:           emailMap[uid] ?? uid,
    kit_count:       byUser[uid].kit_count,
    latest_kit_date: byUser[uid].latest_kit_date,
  })).sort((a, b) => b.latest_kit_date.localeCompare(a.latest_kit_date))

  return NextResponse.json({ subscribers })
}
