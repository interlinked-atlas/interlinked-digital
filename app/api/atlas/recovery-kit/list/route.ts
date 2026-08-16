import { NextRequest, NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
)

export async function GET(req: NextRequest) {
  const token = req.headers.get('authorization')?.replace('Bearer ', '')
  if (!token) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

  const { data: { user }, error: authErr } = await supabase.auth.getUser(token)
  if (authErr || !user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

  // Accessible to any authenticated user — so they can see their kits even after a plan change
  const { data, error } = await supabase
    .from('recovery_kits')
    .select('id, generated_at, atlas_version, kit_version, record_count, archived_count, device_name, atlaskit_size, txt_size, created_at')
    .eq('user_id', user.id)
    .eq('is_deleted', false)
    .order('generated_at', { ascending: false })

  if (error) return NextResponse.json({ error: error.message }, { status: 500 })

  return NextResponse.json({ kits: data ?? [] })
}
