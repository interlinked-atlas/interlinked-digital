// Admin-only: upload a product thumbnail straight to the public
// atlas-catalog-images bucket and store its public URL on the row. Unlike
// every other upload route in this app (recovery-kit, fileshare, installers)
// this doesn't need a signed-upload-URL dance — the bucket is public and
// only the admin (service-role) ever writes to it, so the upload happens
// directly on this server route in one request.
import { NextRequest, NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'

const ADMIN_EMAIL = 'titantinstaller@gmail.com'

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
)

async function verifyAdmin(req: NextRequest): Promise<{ ok: boolean; error?: NextResponse }> {
  const token = req.headers.get('authorization')?.replace('Bearer ', '').trim()
  if (!token) return { ok: false, error: NextResponse.json({ error: 'Unauthorized' }, { status: 401 }) }
  const { data: { user }, error } = await supabase.auth.getUser(token)
  if (error || !user || user.email?.toLowerCase() !== ADMIN_EMAIL.toLowerCase())
    return { ok: false, error: NextResponse.json({ error: 'Forbidden' }, { status: 403 }) }
  return { ok: true }
}

export async function POST(req: NextRequest) {
  const auth = await verifyAdmin(req)
  if (!auth.ok) return auth.error!

  const form = await req.formData().catch(() => null)
  const file = form?.get('file')
  const id = form?.get('id')
  if (!(file instanceof File) || typeof id !== 'string' || !id) {
    return NextResponse.json({ error: 'Missing file or id' }, { status: 400 })
  }

  const ext = file.name.split('.').pop()?.toLowerCase() || 'png'
  const path = `${id}.${ext}`

  const { error: uploadError } = await supabase.storage
    .from('atlas-catalog-images')
    .upload(path, await file.arrayBuffer(), { contentType: file.type, upsert: true })

  if (uploadError) return NextResponse.json({ error: uploadError.message }, { status: 500 })

  const { data: { publicUrl } } = supabase.storage.from('atlas-catalog-images').getPublicUrl(path)

  const { error: updateError } = await supabase
    .from('atlas_catalog')
    .update({ image_url: publicUrl })
    .eq('id', id)

  if (updateError) return NextResponse.json({ error: updateError.message }, { status: 500 })

  return NextResponse.json({ ok: true, image_url: publicUrl })
}
