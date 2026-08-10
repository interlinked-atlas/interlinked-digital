import { NextRequest, NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
)

const MAX_BYTES = 50 * 1024 * 1024 // 50 MB — Supabase free tier limit; raise to 2 GB after upgrading to Supabase Pro

export async function POST(req: NextRequest) {
  const token = req.headers.get('authorization')?.replace('Bearer ', '')
  if (!token) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

  const { data: { user }, error: authErr } = await supabase.auth.getUser(token)
  if (authErr || !user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

  // Pro only
  const { data: profile } = await supabase.from('profiles').select('plan').eq('id', user.id).single()
  const plan = profile?.plan ?? 'standard'
  if (plan !== 'pro') {
    return NextResponse.json({ error: 'File Sharing is a Pro feature' }, { status: 403 })
  }

  const { file_name, file_size } = await req.json()
  if (!file_name || typeof file_size !== 'number') {
    return NextResponse.json({ error: 'file_name and file_size required' }, { status: 400 })
  }

  if (file_size > MAX_BYTES) {
    const mb = (file_size / 1024 / 1024).toFixed(1)
    return NextResponse.json({
      error: `File too large (${mb} MB). FileShare currently supports files up to 50 MB.`,
      code: 'FILE_TOO_LARGE',
    }, { status: 413 })
  }

  // Generate a unique storage path
  const fileId      = crypto.randomUUID()
  const storagePath = `${user.id}/${fileId}/${file_name}`

  const { data: signedData, error: signErr } = await supabase.storage
    .from('atlas-shared-files')
    .createSignedUploadUrl(storagePath)

  if (signErr || !signedData) {
    return NextResponse.json({ error: 'Could not create upload URL' }, { status: 500 })
  }

  return NextResponse.json({
    upload_url:   signedData.signedUrl,
    file_id:      fileId,
    storage_path: storagePath,
  })
}
