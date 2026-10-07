import { NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'

const supabaseAdmin = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
)

const ATLAS_MONTHLY_LIMIT = 25
const ATLAS_MAX_DEVICES   = 3

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

    // Entitlement is already fully determined above by subscriptions.status
    // (active / trialing / past_due-within-grace) — no plan-string check.

    // Get current install count from the authoritative, account-wide
    // install_counts table (one row per user_id — the 25-install allowance
    // is shared across every device on the account, not per device).
    //
    // Period boundary is computed by the same atlas_period_start/
    // atlas_next_period_start functions reserve_install_slot and
    // confirm_install_reservation use — one shared calculation, not a second
    // competing one. billing_interval/billing_anchor_day are cadence metadata
    // only; entitlement above remains solely subscriptions.status-based.
    const { data: billingProfile } = await supabaseAdmin
      .from('profiles')
      .select('billing_interval, billing_anchor_day')
      .eq('id', user.id)
      .single()

    const { data: periodStart } = await supabaseAdmin.rpc('atlas_period_start', {
      p_billing_interval: billingProfile?.billing_interval ?? null,
      p_billing_anchor_day: billingProfile?.billing_anchor_day ?? null,
    })
    const { data: nextPeriodStart } = await supabaseAdmin.rpc('atlas_next_period_start', {
      p_billing_interval: billingProfile?.billing_interval ?? null,
      p_billing_anchor_day: billingProfile?.billing_anchor_day ?? null,
    })

    const { data: countRows } = await supabaseAdmin
      .from('install_counts')
      .select('installs_this_month')
      .eq('user_id', user.id)
      .eq('period_start', periodStart)

    const monthlyUsed = (countRows ?? []).reduce((sum, r) => sum + (r.installs_this_month ?? 0), 0)
    const resetDate   = new Date(nextPeriodStart as string).toISOString()

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
