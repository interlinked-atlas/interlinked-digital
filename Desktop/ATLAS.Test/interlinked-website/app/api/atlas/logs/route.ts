import { NextRequest, NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
)

export async function POST(req: NextRequest) {
  // Verify the ATLAS app's access token
  const token = req.headers.get('authorization')?.replace('Bearer ', '').trim()
  if (!token) {
    return NextResponse.json({ error: 'Missing authorization' }, { status: 401 })
  }

  const { data: { user }, error: authError } = await supabase.auth.getUser(token)
  if (authError || !user) {
    return NextResponse.json({ error: 'Invalid token' }, { status: 401 })
  }

  let body: Record<string, string>
  try {
    body = await req.json()
  } catch {
    return NextResponse.json({ error: 'Invalid JSON body' }, { status: 400 })
  }

  const { log_type, app_name, filename, content, device_name, hardware_uuid } = body

  if (!log_type || !filename || !content) {
    return NextResponse.json({ error: 'Missing required fields' }, { status: 400 })
  }

  const { error: insertError } = await supabase.from('install_logs').insert({
    user_id:      user.id,
    app_name:     app_name     ?? filename,
    log_type:     log_type,
    filename:     filename,
    content:      content,
    device_name:  device_name  ?? 'Unknown device',
    hardware_uuid: hardware_uuid ?? '',
    installed_at: new Date().toISOString(),
  })

  if (insertError) {
    console.error('[ATLAS] install_logs insert failed:', insertError.message)
    return NextResponse.json({ error: 'Failed to save log' }, { status: 500 })
  }

  return NextResponse.json({ ok: true })
}
