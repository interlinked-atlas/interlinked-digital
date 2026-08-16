import { NextRequest, NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
)

export async function DELETE(req: NextRequest) {
  const token = req.headers.get('authorization')?.replace('Bearer ', '')
  if (!token) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

  const { data: { user }, error: authErr } = await supabase.auth.getUser(token)
  if (authErr || !user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

  const body = await req.json().catch(() => ({}))
  const { kit_id } = body
  if (!kit_id) return NextResponse.json({ error: 'kit_id required' }, { status: 400 })

  // Ownership enforced: row must belong to this user
  const { data: kitRow } = await supabase
    .from('recovery_kits')
    .select('atlaskit_path, txt_path')
    .eq('id', kit_id)
    .eq('user_id', user.id)
    .single()

  if (!kitRow) return NextResponse.json({ error: 'Recovery Kit not found' }, { status: 404 })

  // Delete both storage objects
  await supabase.storage.from('atlas-recovery-kits').remove([kitRow.atlaskit_path, kitRow.txt_path])

  // Soft-delete the row
  await supabase
    .from('recovery_kits')
    .update({ is_deleted: true, updated_at: new Date().toISOString() })
    .eq('id', kit_id)
    .eq('user_id', user.id)

  return NextResponse.json({ ok: true })
}
