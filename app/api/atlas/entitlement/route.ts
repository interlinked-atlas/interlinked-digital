import { NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'

const supabaseAdmin = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
)

const MONTHLY_LIMITS: Record<string, number> = {
  standard: 10,
  pro:      25,
}

const MAX_DEVICES: Record<string, number> = {
  standard: 1,
  pro:      3,
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

    const isActive    = subscription.status === 'active' || subscription.status === 'trialing'
    const isPastDue   = subscription.status === 'past_due'
    const periodEnd   = new Date(subscription.current_period_end)
    const graceEnd    = new Date(periodEnd.getTime() + 3 * 24 * 60 * 60 * 1000)
    const inGrace     = isPastDue && new Date() < graceEnd

    if (!isActive && !inGrace) {
      return NextResponse.json({
        valid: false,
        reason: subscription.status,
        expired_at: subscription.current_period_end,
      })
    }

    const plan       = subscription.plan ?? 'standard'
    const monthlyLimit = MONTHLY_LIMITS[plan] ?? 10
    const maxDevices   = MAX_DEVICES[plan] ?? 1

    // Get current monthly install count
    const now         = new Date()
    const periodStart = new Date(now.getFullYear(), now.getMonth(), 1).toISOString().split('T')[0]
    const { data: countRow } = await supabaseAdmin
      .from('monthly_install_counts')
      .select('count')
      .eq('user_id', user.id)
      .eq('period_start', periodStart)
      .single()

    const monthlyUsed = countRow?.count ?? 0

    // Compute reset date (first of next month)
    const resetDate = new Date(now.getFullYear(), now.getMonth() + 1, 1).toISOString()

    const { data: activations } = await supabaseAdmin
      .from('device_activations')
      .select('*')
      .eq('user_id', user.id)
      .eq('is_active', true)

    return NextResponse.json({
      valid: true,
      plan,
      status: subscription.status,
      current_period_end: subscription.current_period_end,
      cancel_at_period_end: subscription.cancel_at_period_end,
      in_grace_period: inGrace,
      features: {
        bulk_queue:        plan !== 'standard',
        uninstall_manager: plan !== 'standard',
        recovery_system:   plan !== 'standard',
        max_devices:       maxDevices,
        monthly_install_limit: monthlyLimit,
        monthly_installs_used: monthlyUsed,
        monthly_reset_date:    resetDate,
      },
      activations: {
        current: activations?.length ?? 0,
        max:     maxDevices,
        devices: activations?.map(a => ({
          id:           a.id,
          device_name:  a.device_name,
          activated_at: a.activated_at,
          last_seen_at: a.last_seen_at,
        })),
      },
    })
  } catch {
    return NextResponse.json({ error: 'Internal server error' }, { status: 500 })
  }
}
