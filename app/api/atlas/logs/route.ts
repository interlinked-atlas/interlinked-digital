import { NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'

const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL!
const SUPABASE_ANON = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!
const SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY!

// POST /api/atlas/logs — called by ATLAS app after each install/uninstall/failure/crash
export async function POST(request: Request) {
  const authHeader = request.headers.get('authorization')
  if (!authHeader?.startsWith('Bearer ')) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  }
  const accessToken = authHeader.substring(7)

  // Validate user token
  const anonClient = createClient(SUPABASE_URL, SUPABASE_ANON)
  const { data: { user }, error: authError } = await anonClient.auth.getUser(accessToken)
  if (authError || !user) {
    return NextResponse.json({ error: 'Invalid token' }, { status: 401 })
  }

  let body: {
    log_type?: string; app_name?: string; filename?: string
    content?: string; device_name?: string; hardware_uuid?: string
  }
  try { body = await request.json() } catch {
    return NextResponse.json({ error: 'Invalid JSON' }, { status: 400 })
  }

  const { log_type, app_name, filename, content, device_name, hardware_uuid } = body
  if (!log_type || !filename) {
    return NextResponse.json({ error: 'Missing required fields' }, { status: 400 })
  }

  // Use service role to bypass RLS — user identity already verified above
  const adminClient = createClient(SUPABASE_URL, SERVICE_KEY)

  const { error: insertError } = await adminClient
    .from('install_logs')
    .insert({
      user_id: user.id,
      log_type,
      app_name: app_name ?? filename,
      filename,
      content: content ?? null,
      device_name: device_name ?? null,
      hardware_uuid: hardware_uuid ?? null,
      installed_at: new Date().toISOString(),
    })

  if (insertError) {
    console.error('[logs] insert error:', insertError.message)
    // Fallback: if new columns don't exist yet, store with minimal fields
    if (insertError.message.includes('column') || insertError.code === '42703') {
      await adminClient
        .from('install_logs')
        .insert({
          user_id: user.id,
          app_name: `[${log_type.toUpperCase()}] ${app_name ?? filename}`,
          installed_at: new Date().toISOString(),
        })
    }
  }

  return NextResponse.json({ success: true })
}
