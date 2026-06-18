import { NextRequest, NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
)

const MONTHLY_LIMITS: Record<string, number> = {
  standard: 10,
  pro:      25,
  advanced: 50,
}

// POST /api/atlas/install-count
// Increment monthly install count and return updated state.
// Returns { allowed, used, limit, reset_date } or 429 if limit reached.
export async function POST(req: NextRequest) {
  const token = req.headers.get('authorization')?.replace('Bearer ', '').trim()
  if (!token) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

  const { data: { user }, error } = await supabase.auth.getUser(token)
  if (error || !user) return NextResponse.json({ error: 'Invalid token' }, { status: 401 })

  const { data: sub } = await supabase
    .from('subscriptions')
    .select('plan')
    .eq('user_id', user.id)
    .single()

  const plan  = sub?.plan ?? 'standard'
  const limit = MONTHLY_LIMITS[plan] ?? 10

  const now         = new Date()
  const periodStart = new Date(now.getFullYear(), now.getMonth(), 1).toISOString().split('T')[0]
  const periodEnd   = new Date(now.getFullYear(), now.getMonth() + 1, 0).toISOString().split('T')[0]
  const resetDate   = new Date(now.getFullYear(), now.getMonth() + 1, 1).toISOString()

  // Upsert + increment atomically via RPC or manual read-increment-write
  const { data: existing } = await supabase
    .from('monthly_install_counts')
    .select('id, count')
    .eq('user_id', user.id)
    .eq('period_start', periodStart)
    .single()

  if (existing) {
    if (existing.count >= limit) {
      return NextResponse.json({
        allowed:    false,
        used:       existing.count,
        limit,
        reset_date: resetDate,
      }, { status: 429 })
    }
    const newCount = existing.count + 1
    await supabase
      .from('monthly_install_counts')
      .update({ count: newCount, updated_at: new Date().toISOString() })
      .eq('id', existing.id)

    return NextResponse.json({ allowed: true, used: newCount, limit, reset_date: resetDate })
  } else {
    await supabase.from('monthly_install_counts').insert({
      user_id:      user.id,
      period_start: periodStart,
      period_end:   periodEnd,
      count:        1,
    })
    return NextResponse.json({ allowed: true, used: 1, limit, reset_date: resetDate })
  }
}
