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

  const fileId = req.nextUrl.searchParams.get('file_id')
  if (!fileId) return NextResponse.json({ error: 'file_id required' }, { status: 400 })

  // Verify ownership
  const { data: file, error: fileErr } = await supabase
    .from('shared_files')
    .select('storage_path, expires_at')
    .eq('id', fileId)
    .eq('user_id', user.id)
    .single()

  if (fileErr || !file) return NextResponse.json({ error: 'File not found' }, { status: 404 })

  if (new Date(file.expires_at) < new Date()) {
    return NextResponse.json({ error: 'File has expired' }, { status: 410 })
  }

  const { data: signed, error: signErr } = await supabase.storage
    .from('atlas-shared-files')
    .createSignedUrl(file.storage_path, 3600) // 1 hour to start download

  if (signErr || !signed) return NextResponse.json({ error: 'Could not create download URL' }, { status: 500 })

  return NextResponse.json({ download_url: signed.signedUrl })
}
