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

  // Auto-clean expired files
  await supabase.from('shared_files')
    .delete()
    .eq('user_id', user.id)
    .lt('expires_at', new Date().toISOString())

  const { data, error } = await supabase
    .from('shared_files')
    .select('id, file_name, file_size, storage_path, uploaded_at, expires_at, platform')
    .eq('user_id', user.id)
    .order('uploaded_at', { ascending: false })

  if (error) return NextResponse.json({ error: error.message }, { status: 500 })

  return NextResponse.json({ files: data ?? [] })
}
