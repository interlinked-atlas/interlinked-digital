import { NextRequest, NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'
import { randomUUID } from 'crypto'

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
)

const MAX_BYTES = 10 * 1024 * 1024 // 10 MB per file

export async function POST(req: NextRequest) {
  const token = req.headers.get('authorization')?.replace('Bearer ', '')
  if (!token) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

  const { data: { user }, error: authErr } = await supabase.auth.getUser(token)
  if (authErr || !user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

  const { data: profile } = await supabase
    .from('profiles')
    .select('plan')
    .eq('id', user.id)
    .single()
  if (profile?.plan !== 'pro') {
    return NextResponse.json({ error: 'Cloud Recovery Kit requires ATLAS Pro' }, { status: 403 })
  }

  const body = await req.json().catch(() => ({}))
  const { generated_at, atlaskit_size, txt_size, atlas_version, kit_version, record_count, archived_count, device_name, hardware_uuid } = body

  if (!generated_at || typeof atlaskit_size !== 'number' || typeof txt_size !== 'number') {
    return NextResponse.json({ error: 'generated_at, atlaskit_size, and txt_size are required' }, { status: 400 })
  }
  if (atlaskit_size <= 0 || atlaskit_size > MAX_BYTES) {
    return NextResponse.json({ error: 'atlaskit_size out of range' }, { status: 413 })
  }
  if (txt_size <= 0 || txt_size > MAX_BYTES) {
    return NextResponse.json({ error: 'txt_size out of range' }, { status: 413 })
  }

  // Server-generated kit_id — client never controls this
  const kitId = randomUUID()
  const atlaskitPath = `${user.id}/${kitId}-atlaskit.enc`
  const txtPath = `${user.id}/${kitId}-txt.enc`

  const [atlaskitUrl, txtUrl] = await Promise.all([
    supabase.storage.from('atlas-recovery-kits').createSignedUploadUrl(atlaskitPath),
    supabase.storage.from('atlas-recovery-kits').createSignedUploadUrl(txtPath),
  ])

  if (atlaskitUrl.error || !atlaskitUrl.data) {
    return NextResponse.json({ error: 'Could not create atlaskit upload URL' }, { status: 500 })
  }
  if (txtUrl.error || !txtUrl.data) {
    return NextResponse.json({ error: 'Could not create txt upload URL' }, { status: 500 })
  }

  return NextResponse.json({
    kit_id:              kitId,
    atlaskit_upload_url: atlaskitUrl.data.signedUrl,
    atlaskit_path:       atlaskitPath,
    txt_upload_url:      txtUrl.data.signedUrl,
    txt_path:            txtPath,
  })
}
