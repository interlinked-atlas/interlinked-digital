import { NextRequest, NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'

const ADMIN_EMAIL = 'titantinstaller@gmail.com'

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
)

export async function GET(req: NextRequest) {
  const token = req.headers.get('authorization')?.replace('Bearer ', '').trim()
  if (!token) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

  const { data: { user }, error } = await supabase.auth.getUser(token)
  if (error || !user || user.email?.toLowerCase() !== ADMIN_EMAIL.toLowerCase()) {
    return NextResponse.json({ error: 'Forbidden' }, { status: 403 })
  }

  const [profiles, devices, logs, tickets, subscriptions] = await Promise.all([
    supabase.from('profiles').select('id,email,plan,subscription_status,created_at,privacy_consent,privacy_consent_at').order('created_at', { ascending: false }),
    supabase.from('devices').select('id,user_id,device_name,hardware_uuid,last_seen,created_at').order('last_seen', { ascending: false }),
    supabase.from('install_logs').select('id,user_id,app_name,log_type,filename,content,device_name,hardware_uuid,installed_at').order('installed_at', { ascending: false }).limit(500),
    supabase.from('support_tickets').select('id,user_id,email,issue_type,message,status,created_at,attached_log_content').order('created_at', { ascending: false }),
    supabase.from('subscriptions').select('id,user_id,plan,status,current_period_end,cancel_at_period_end,stripe_subscription_id').order('created_at', { ascending: false }),
  ])

  return NextResponse.json({
    profiles:      profiles.data      ?? [],
    devices:       devices.data       ?? [],
    logs:          logs.data          ?? [],
    tickets:       tickets.data       ?? [],
    subscriptions: subscriptions.data ?? [],
  })
}

export async function PATCH(req: NextRequest) {
  const token = req.headers.get('authorization')?.replace('Bearer ', '').trim()
  if (!token) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

  const { data: { user }, error } = await supabase.auth.getUser(token)
  if (error || !user || user.email?.toLowerCase() !== ADMIN_EMAIL.toLowerCase()) {
    return NextResponse.json({ error: 'Forbidden' }, { status: 403 })
  }

  const { action, id } = await req.json()

  if (action === 'resolve_ticket') {
    const { error: e } = await supabase.from('support_tickets').update({ status: 'resolved' }).eq('id', id)
    if (e) return NextResponse.json({ error: e.message }, { status: 500 })
  }

  return NextResponse.json({ ok: true })
}
