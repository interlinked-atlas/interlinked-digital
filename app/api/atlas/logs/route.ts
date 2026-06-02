import { NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
)

// POST /api/atlas/logs
// Called by ATLAS app after each install/uninstall/failure.
export async function POST(request: Request) {
  const authHeader = request.headers.get('authorization')
  if (!authHeader?.startsWith('Bearer ')) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  }

  const accessToken = authHeader.substring(7)
  const { data: { user }, error: authError } = await supabase.auth.getUser(accessToken)
  if (authError || !user) {
    return NextResponse.json({ error: 'Invalid token' }, { status: 401 })
  }

  let body: {
    log_type?: string
    app_name?: string
    filename?: string
    content?: string
    device_name?: string
    hardware_uuid?: string
  }
  try { body = await request.json() } catch {
    return NextResponse.json({ error: 'Invalid JSON' }, { status: 400 })
  }

  const { log_type, app_name, filename, content, device_name, hardware_uuid } = body
  if (!log_type || !filename) {
    return NextResponse.json({ error: 'Missing required fields' }, { status: 400 })
  }

  // 1. Write install record to install_logs (always works — table exists)
  if (log_type === 'install' || log_type === 'failed') {
    await supabase
      .from('install_logs')
      .insert({
        user_id: user.id,
        app_name: app_name ?? filename,
        installed_at: new Date().toISOString(),
      })
      .then(({ error }) => {
        if (error) console.error('[logs] install_logs insert:', error.message)
      })
  }

  // 2. Store full log content in Supabase Storage (atlas-logs bucket)
  if (content) {
    const ts = Date.now()
    const safeName = filename.replace(/[^a-z0-9._-]/gi, '_').slice(0, 80)
    const filePath = `${user.id}/${ts}_${log_type}_${safeName}.txt`

    const logPayload = JSON.stringify({
      log_type,
      app_name: app_name ?? null,
      filename,
      content,
      device_name: device_name ?? null,
      hardware_uuid: hardware_uuid ?? null,
      created_at: new Date().toISOString(),
    })

    const { error: storageError } = await supabase.storage
      .from('atlas-logs')
      .upload(filePath, logPayload, {
        contentType: 'application/json',
        upsert: false,
      })

    if (storageError) {
      console.error('[logs] storage upload failed:', storageError.message)
      // Don't fail the request — install was logged above
    }
  }

  return NextResponse.json({ success: true })
}
