import { NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
)

// POST /api/atlas/logs
// Called by ATLAS app after each install/uninstall/failure.
// Syncs full log content to the user's account dashboard.
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
  if (!log_type || !filename || !content) {
    return NextResponse.json({ error: 'Missing required fields' }, { status: 400 })
  }

  const { error: insertError } = await supabase.from('atlas_logs').insert({
    user_id:      user.id,
    log_type,
    app_name:     app_name ?? null,
    filename,
    content,
    device_name:  device_name ?? null,
    hardware_uuid: hardware_uuid ?? null,
  })

  if (insertError) {
    console.error('[ATLAS] Log insert error:', insertError.message)
    return NextResponse.json({ error: insertError.message }, { status: 500 })
  }

  return NextResponse.json({ success: true })
}
