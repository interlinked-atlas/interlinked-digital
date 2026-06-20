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

  // The requesting device's hardware UUID — used to filter targeted shares
  const deviceId = req.nextUrl.searchParams.get('device_id')

  // Auto-clean expired files — remove from storage first, then DB
  const { data: expired } = await supabase
    .from('shared_files')
    .select('storage_path')
    .eq('user_id', user.id)
    .lt('expires_at', new Date().toISOString())

  if (expired && expired.length > 0) {
    const paths = expired.map((f: { storage_path: string }) => f.storage_path)
    await supabase.storage.from('atlas-shared-files').remove(paths)
    await supabase.from('shared_files')
      .delete()
      .eq('user_id', user.id)
      .lt('expires_at', new Date().toISOString())
  }

  // Return files targeted at this device OR files with no specific target (null = all devices)
  let query = supabase
    .from('shared_files')
    .select('id, file_name, file_size, storage_path, uploaded_at, expires_at, platform, target_device_id')
    .eq('user_id', user.id)
    .order('uploaded_at', { ascending: false })

  if (deviceId) {
    query = query.or(`target_device_id.eq.${deviceId},target_device_id.is.null`)
  }

  const { data, error } = await query
  if (error) return NextResponse.json({ error: error.message }, { status: 500 })

  return NextResponse.json({ files: data ?? [] })
}
