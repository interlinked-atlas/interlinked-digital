import { NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'

const supabaseAdmin = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
)

const ATLAS_MONTHLY_LIMIT = 25
const ATLAS_MAX_DEVICES   = 3

function isSubscribedPlan(plan: string) {
  return plan === 'atlas' || plan === 'pro' || plan === 'standard'
}

// GET /api/atlas/entitlement
export async function GET(request: Request) {
  try {
    const authHeader = request.headers.get('authorization')
    if (!authHeader?.startsWith('Bearer ')) {
      return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
    }

    const token = authHeader.substring(7)
    const { data: { user }, error: authError } = await supabaseAdmin.auth.getUser(token)

    if (authError || !user) {
      return NextResponse.json({ error: 'Invalid token' }, { status: 401 })
    }

    const { data: subscription } = await supabaseAdmin
      .from('subscriptions')
      .select('*')
      .eq('user_id', user.id)
      .single()

    if (!subscription) {
      return NextResponse.json({ valid: false, reason: 'no_subscription' })
    }

    const isActive  = subscription.status === 'active' || subscription.status === 'trialing'
    const isPastDue = subscription.status === 'past_due'
    const periodEnd = new Date(subscription.current_period_end)
    const graceEnd  = new Date(periodEnd.getTime() + 3 * 24 * 60 * 60 * 1000)
    const inGrace   = isPastDue && new Date() < graceEnd

    if (!isActive && !inGrace) {
      return NextResponse.json({
        valid: false,
        reason: subscription.status,
        expired_at: subscription.current_period_end,
      })
    }

    const plan = subscription.plan ?? 'atlas'
    if (!isSubscribedPlan(plan)) {
      return NextResponse.json({ valid: false, reason: 'no_subscription' })
    }

    // Get current monthly install count (calendar month)
    const now         = new Date()
    const periodStart = new Date(now.getFullYear(), now.getMonth(), 1).toISOString().split('T')[0]
    const { data: countRow } = await supabaseAdmin
      .from('monthly_install_counts')
      .select('count')
      .eq('user_id', user.id)
      .eq('period_start', periodStart)
      .single()

    const monthlyUsed = countRow?.count ?? 0
    const resetDate   = new Date(now.getFullYear(), now.getMonth() + 1, 1).toISOString()

    const { data: devices } = await supabaseAdmin
      .from('devices')
      .select('id, device_name, hardware_uuid, last_seen, created_at')
      .eq('user_id', user.id)

    return NextResponse.json({
      valid: true,
      plan: 'atlas',
      status: subscription.status,
      current_period_end: subscription.current_period_end,
      cancel_at_period_end: subscription.cancel_at_period_end,
      in_grace_period: inGrace,
      features: {
        bulk_queue:            true,
        uninstall_manager:     true,
        recovery_system:       true,
        max_devices:           ATLAS_MAX_DEVICES,
        monthly_install_limit: ATLAS_MONTHLY_LIMIT,
        monthly_installs_used: monthlyUsed,
        monthly_reset_date:    resetDate,
      },
      activations: {
        current: devices?.length ?? 0,
        max:     ATLAS_MAX_DEVICES,
        devices: devices?.map(d => ({
          id:           d.id,
          device_name:  d.device_name,
          activated_at: d.created_at,
          last_seen_at: d.last_seen,
        })),
      },
    })
  } catch {
    return NextResponse.json({ error: 'Internal server error' }, { status: 500 })
  }
}
