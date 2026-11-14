import { NextRequest, NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
)

const ADMIN_EMAIL = 'titantinstaller@gmail.com'

async function requireAdmin(req: NextRequest) {
  const token = req.headers.get('authorization')?.replace('Bearer ', '').trim()
  if (!token) return null
  const { data: { user }, error } = await supabase.auth.getUser(token)
  if (error || !user) return null
  if (user.email?.toLowerCase() !== ADMIN_EMAIL.toLowerCase()) return null
  return user
}

// PATCH /api/atlas/admin/browser-download-limit
//
// Sets profiles.monthly_browser_download_limit for one user. null clears
// the override back to the standard 25. Unlike the regular install limit,
// this is capped at 25 — admin can only dial a user's Browser allowance
// DOWN from the standard amount, never above it.
//
// report_browser_download/atlas_browser_usage (Postgres functions) already
// read this column directly via COALESCE(..., 25) — no app update needed,
// takes effect on the user's very next Browser download attempt.
export async function PATCH(req: NextRequest) {
  const admin = await requireAdmin(req)
  if (!admin) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })

  let body: { user_id?: string; monthly_browser_download_limit?: number | null } = {}
  try { body = await req.json() } catch { /* no body sent */ }

  const userID = body.user_id?.trim()
  if (!userID) return NextResponse.json({ error: 'missing_user_id' }, { status: 400 })

  const limit = body.monthly_browser_download_limit
  if (limit !== undefined && limit !== null &&
      (typeof limit !== 'number' || !Number.isInteger(limit) || limit < 1 || limit > 25)) {
    return NextResponse.json({ error: 'monthly_browser_download_limit must be an integer from 1 to 25, or null' }, { status: 400 })
  }

  const { error } = await supabase
    .from('profiles')
    .update({ monthly_browser_download_limit: limit ?? null })
    .eq('id', userID)

  if (error) return NextResponse.json({ error: error.message }, { status: 500 })
  return NextResponse.json({ ok: true, monthly_browser_download_limit: limit ?? null })
}
