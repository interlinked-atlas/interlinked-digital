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

  const { file_id } = await req.json()
  if (!file_id) return NextResponse.json({ error: 'file_id required' }, { status: 400 })

  // Get storage path first (verify ownership)
  const { data: file, error: fileErr } = await supabase
    .from('shared_files')
    .select('storage_path')
    .eq('id', file_id)
    .eq('user_id', user.id)
    .single()

  if (fileErr || !file) return NextResponse.json({ error: 'File not found' }, { status: 404 })

  // Delete from storage
  await supabase.storage.from('atlas-shared-files').remove([file.storage_path])

  // Delete from DB
  await supabase.from('shared_files').delete().eq('id', file_id).eq('user_id', user.id)

  return NextResponse.json({ success: true })
}
