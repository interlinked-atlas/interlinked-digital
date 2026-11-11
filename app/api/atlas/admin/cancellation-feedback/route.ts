// Admin-only: view the optional, skippable cancellation-reason survey
// collected at /atlas/account's cancel-confirmation modal (see
// app/api/atlas/cancel/route.ts), stored as billing_audit_log rows.
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
    .from('billing_audit_log')
    .select('id, email, metadata, created_at')
    .eq('event', 'subscription.cancellation_feedback')
    .order('created_at', { ascending: false })
    .limit(500)

  if (error) return NextResponse.json({ error: error.message }, { status: 500 })

  return NextResponse.json((data ?? []).map(row => ({
    id: row.id,
    email: row.email,
    reason: (row.metadata as Record<string, unknown> | null)?.reason ?? null,
    feedback: (row.metadata as Record<string, unknown> | null)?.feedback ?? null,
    created_at: row.created_at,
  })))
}
