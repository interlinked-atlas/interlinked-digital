import { NextRequest, NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
)

export async function GET(req: NextRequest) {
  const token = req.headers.get('authorization')?.replace('Bearer ', '').trim()
  if (!token) return NextResponse.json({ error: 'Missing authorization' }, { status: 401 })

  const { data: { user }, error: authError } = await supabase.auth.getUser(token)
  if (authError || !user) return NextResponse.json({ error: 'Invalid token' }, { status: 401 })

  // Return all patterns with at least 1 confirmed install, sorted by most confirmed first.
  // This is the cloud TITAN MEMORY™ — every ATLAS client gets the full list.
  const { data, error } = await supabase
    .from('install_patterns')
    .select('id, product_name, match_patterns, pkg_receipt_ids, installed_paths, hosts_entries, success_count, last_confirmed_at')
    .gte('success_count', 1)
    .order('success_count', { ascending: false })
    .limit(500)

  if (error) return NextResponse.json({ error: error.message }, { status: 500 })

  return NextResponse.json(data ?? [])
}
