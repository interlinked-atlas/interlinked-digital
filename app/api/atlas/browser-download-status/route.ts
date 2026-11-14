// Read-only status check for ATLAS Browser's own 25/month download cap —
// same reasoning as install-status/route.ts: lets the Mac app refresh its
// locked-screen state (e.g. after the period rolls over) without needing
// to attempt an actual download first. Calls atlas_browser_usage (no row
// mutation), never report_browser_download.
import { NextRequest, NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
)

export async function GET(req: NextRequest) {
  const token = req.headers.get('authorization')?.replace('Bearer ', '').trim()
  if (!token) return NextResponse.json({ error: 'unauthorized' }, { status: 401 })

  const { data: { user }, error: authErr } = await supabase.auth.getUser(token)
  if (authErr || !user) return NextResponse.json({ error: 'unauthorized' }, { status: 401 })

  const { data, error } = await supabase.rpc('atlas_browser_usage', { p_user_id: user.id })

  if (error) {
    console.error('[browser-download-status] RPC error:', error)
    return NextResponse.json({ error: 'server_error' }, { status: 503 })
  }

  return NextResponse.json(data)
}
