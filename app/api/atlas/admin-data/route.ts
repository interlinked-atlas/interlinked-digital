import { NextRequest, NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
)

const ADMIN_EMAILS = ['titantinstaller@gmail.com', 'interlinked.digital@gmail.com']

export async function GET(req: NextRequest) {
  const token = req.headers.get('authorization')?.replace('Bearer ', '').trim()
  if (!token) return NextResponse.json({ error: 'Missing authorization' }, { status: 401 })

  const { data: { user }, error: authError } = await supabase.auth.getUser(token)
  if (authError || !user) return NextResponse.json({ error: 'Invalid token' }, { status: 401 })
  if (!ADMIN_EMAILS.includes(user.email ?? '')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })

  const { data: logs, error } = await supabase
    .from('install_logs')
    .select('id, user_id, log_type, app_name, filename, content, device_name, installed_at')
    .order('installed_at', { ascending: false })
    .limit(500)

  if (error) return NextResponse.json({ error: error.message }, { status: 500 })

  return NextResponse.json({ logs: logs ?? [] })
}
