import { NextRequest, NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
)

const MONTHLY_LIMITS: Record<string, number> = {
  standard: 10,
  pro:      25,
}

// POST /api/atlas/install-count
// Increment monthly install count and return updated state.
// Returns { allowed, used, limit, reset_date } or 429 if limit reached.
//
// Plan is read from `profiles` (the authoritative source the ATLAS app reads).
// Period start is calculated using profiles.billing_anchor_day so the server-side
// window matches the billing-anniversary reset logic in MonthlyLimitManager.swift.
export async function POST(req: NextRequest) {
  const token = req.headers.get('authorization')?.replace('Bearer ', '').trim()
  if (!token) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

  const { data: { user }, error } = await supabase.auth.getUser(token)
  if (error || !user) return NextResponse.json({ error: 'Invalid token' }, { status: 401 })

  // Read plan and billing anchor from profiles — same source the ATLAS app uses.
  const { data: profile } = await supabase
    .from('profiles')
    .select('plan, billing_anchor_day')
    .eq('id', user.id)
    .single()

  const plan      = profile?.plan ?? 'standard'
  const limit     = MONTHLY_LIMITS[plan] ?? 10
  const anchorDay = profile?.billing_anchor_day ?? 1

  // Calculate current billing period using billing_anchor_day, matching
  // MonthlyLimitManager.currentPeriodStart() in the ATLAS Swift app.
  const now = new Date()
  const currentDay = now.getDate()

  let periodStartYear  = now.getFullYear()
  let periodStartMonth = now.getMonth() // 0-indexed

  if (currentDay < anchorDay) {
    // We haven't hit the anchor day yet this month — period started last month
    periodStartMonth -= 1
    if (periodStartMonth < 0) {
      periodStartMonth = 11
      periodStartYear -= 1
    }
  }

  // Clamp anchor day to the actual number of days in the period-start month
  const daysInPeriodMonth = new Date(periodStartYear, periodStartMonth + 1, 0).getDate()
  const clampedAnchor = Math.min(anchorDay, daysInPeriodMonth)

  const periodStartDate = new Date(periodStartYear, periodStartMonth, clampedAnchor)

  // Next reset: same anchor day in the following month
  let resetYear  = periodStartYear
  let resetMonth = periodStartMonth + 1
  if (resetMonth > 11) { resetMonth = 0; resetYear += 1 }
  const daysInResetMonth = new Date(resetYear, resetMonth + 1, 0).getDate()
  const resetDay = Math.min(anchorDay, daysInResetMonth)
  const resetDate = new Date(resetYear, resetMonth, resetDay)

  const periodStart = periodStartDate.toISOString().split('T')[0]
  const periodEnd   = new Date(resetDate.getTime() - 1).toISOString().split('T')[0]

  // Upsert + increment atomically via manual read-increment-write
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
        reset_date: resetDate.toISOString(),
      }, { status: 429 })
    }
    const newCount = existing.count + 1
    await supabase
      .from('monthly_install_counts')
      .update({ count: newCount, updated_at: new Date().toISOString() })
      .eq('id', existing.id)

    return NextResponse.json({ allowed: true, used: newCount, limit, reset_date: resetDate.toISOString() })
  } else {
    await supabase.from('monthly_install_counts').insert({
      user_id:      user.id,
      period_start: periodStart,
      period_end:   periodEnd,
      count:        1,
    })
    return NextResponse.json({ allowed: true, used: 1, limit, reset_date: resetDate.toISOString() })
  }
}
