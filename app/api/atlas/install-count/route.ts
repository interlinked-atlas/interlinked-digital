import { NextRequest, NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
)

const ATLAS_MONTHLY_LIMIT = 25

// POST /api/atlas/install-count
// Increment monthly install count and return updated state.
// Returns { allowed, used, limit, reset_date } or 429 if limit reached.
//
// Period start is calculated using profiles.billing_anchor_day so the server-side
// window matches the billing-anniversary reset logic in MonthlyLimitManager.swift.
export async function POST(req: NextRequest) {
  const token = req.headers.get('authorization')?.replace('Bearer ', '').trim()
  if (!token) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

  const { data: { user }, error } = await supabase.auth.getUser(token)
  if (error || !user) return NextResponse.json({ error: 'Invalid token' }, { status: 401 })

  const { data: profile } = await supabase
    .from('profiles')
    .select('plan, billing_anchor_day')
    .eq('id', user.id)
    .single()

  const anchorDay = profile?.billing_anchor_day ?? 1

  // Calculate current billing period using billing_anchor_day
  const now = new Date()
  const currentDay = now.getDate()

  let periodStartYear  = now.getFullYear()
  let periodStartMonth = now.getMonth()

  if (currentDay < anchorDay) {
    periodStartMonth -= 1
    if (periodStartMonth < 0) {
      periodStartMonth = 11
      periodStartYear -= 1
    }
  }

  const daysInPeriodMonth = new Date(periodStartYear, periodStartMonth + 1, 0).getDate()
  const clampedAnchor     = Math.min(anchorDay, daysInPeriodMonth)
  const periodStartDate   = new Date(periodStartYear, periodStartMonth, clampedAnchor)

  let resetYear  = periodStartYear
  let resetMonth = periodStartMonth + 1
  if (resetMonth > 11) { resetMonth = 0; resetYear += 1 }
  const daysInResetMonth = new Date(resetYear, resetMonth + 1, 0).getDate()
  const resetDay  = Math.min(anchorDay, daysInResetMonth)
  const resetDate = new Date(resetYear, resetMonth, resetDay)

  const periodStart = periodStartDate.toISOString().split('T')[0]
  const periodEnd   = new Date(resetDate.getTime() - 1).toISOString().split('T')[0]

  const { data: existing } = await supabase
    .from('monthly_install_counts')
    .select('id, count')
    .eq('user_id', user.id)
    .eq('period_start', periodStart)
    .single()

  if (existing) {
    if (existing.count >= ATLAS_MONTHLY_LIMIT) {
      return NextResponse.json({
        allowed:    false,
        used:       existing.count,
        limit:      ATLAS_MONTHLY_LIMIT,
        reset_date: resetDate.toISOString(),
      }, { status: 429 })
    }
    const newCount = existing.count + 1
    await supabase
      .from('monthly_install_counts')
      .update({ count: newCount, updated_at: new Date().toISOString() })
      .eq('id', existing.id)

    return NextResponse.json({ allowed: true, used: newCount, limit: ATLAS_MONTHLY_LIMIT, reset_date: resetDate.toISOString() })
  } else {
    await supabase.from('monthly_install_counts').insert({
      user_id:      user.id,
      period_start: periodStart,
      period_end:   periodEnd,
      count:        1,
    })
    return NextResponse.json({ allowed: true, used: 1, limit: ATLAS_MONTHLY_LIMIT, reset_date: resetDate.toISOString() })
  }
}
