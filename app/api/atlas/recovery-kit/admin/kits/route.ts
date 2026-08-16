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

  const subscriberUserId = req.nextUrl.searchParams.get('user_id')
  if (!subscriberUserId) {
    return NextResponse.json({ error: 'user_id required' }, { status: 400 })
  }

  // Audit log: admin listing a subscriber's kits
  await supabase.from('recovery_kit_admin_audit').insert({
    admin_user_id:       user.id,
    admin_email:         user.email,
    subscriber_user_id:  subscriberUserId,
    kit_id:              '00000000-0000-0000-0000-000000000000', // no specific kit for list action
    action:              'list_kits',
  })

  const { data, error } = await supabase
    .from('recovery_kits')
    .select('id, generated_at, atlas_version, kit_version, record_count, archived_count, device_name, atlaskit_size, txt_size, created_at')
    .eq('user_id', subscriberUserId)
    .eq('is_deleted', false)
    .order('generated_at', { ascending: false })

  if (error) return NextResponse.json({ error: error.message }, { status: 500 })

  return NextResponse.json({ kits: data ?? [] })
}
