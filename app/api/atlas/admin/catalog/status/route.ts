// Admin-only toggle for ATLAS Browser maintenance mode. When on, the app
// shows "ATLAS Browser is Currently being Upgraded. Please Try Again
// Later." instead of the catalog — see /api/atlas/catalog/status (public).
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

export async function GET(req: NextRequest) {
  const auth = await verifyAdmin(req)
  if (!auth.ok) return auth.error!

  const { data, error } = await supabase
    .from('atlas_settings')
    .select('value')
    .eq('key', 'browser_maintenance')
    .maybeSingle()

  if (error) return NextResponse.json({ error: error.message }, { status: 500 })
  return NextResponse.json({ maintenance: data?.value === 'true' })
}

export async function PATCH(req: NextRequest) {
  const auth = await verifyAdmin(req)
  if (!auth.ok) return auth.error!

  const { maintenance } = await req.json().catch(() => ({}))
  if (typeof maintenance !== 'boolean') return NextResponse.json({ error: 'Missing maintenance (boolean)' }, { status: 400 })

  const { error } = await supabase
    .from('atlas_settings')
    .upsert({ key: 'browser_maintenance', value: maintenance ? 'true' : 'false', updated_at: new Date().toISOString() })

  if (error) return NextResponse.json({ error: error.message }, { status: 500 })
  return NextResponse.json({ ok: true, maintenance })
}
