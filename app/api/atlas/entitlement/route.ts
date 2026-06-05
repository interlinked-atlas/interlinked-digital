import { NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'

const supabaseAdmin = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
)

// GET /api/atlas/entitlement
// Check subscription status and entitlements
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

    // Get subscription
    const { data: subscription } = await supabaseAdmin
      .from('subscriptions')
      .select('*')
      .eq('user_id', user.id)
      .single()

    if (!subscription) {
      return NextResponse.json({
        valid: false,
        reason: 'no_subscription',
      })
    }

    // Check if subscription is active
    const isActive = subscription.status === 'active' || subscription.status === 'trialing'
    const isPastDue = subscription.status === 'past_due'
    
    // Allow grace period for past_due
    const gracePeriodDays = 3
    const periodEnd = new Date(subscription.current_period_end)
    const graceEnd = new Date(periodEnd.getTime() + gracePeriodDays * 24 * 60 * 60 * 1000)
    const inGracePeriod = isPastDue && new Date() < graceEnd

    if (!isActive && !inGracePeriod) {
      return NextResponse.json({
        valid: false,
        reason: subscription.status,
        expired_at: subscription.current_period_end,
      })
    }

    // Get device activations
    const { data: activations } = await supabaseAdmin
      .from('device_activations')
      .select('*')
      .eq('user_id', user.id)
      .eq('is_active', true)

    const maxDevices = subscription.plan === 'pro' ? 3 : 1

    return NextResponse.json({
      valid: true,
      plan: subscription.plan,
      status: subscription.status,
      current_period_end: subscription.current_period_end,
      cancel_at_period_end: subscription.cancel_at_period_end,
      in_grace_period: inGracePeriod,
      features: {
        unlimited_installs: subscription.plan === 'pro',
        daily_install_limit: subscription.plan === 'pro' ? null : 3,
        bulk_queue: subscription.plan === 'pro',
        uninstall_manager: subscription.plan === 'pro',
        recovery_system: subscription.plan === 'pro',
        max_devices: maxDevices,
      },
      activations: {
        current: activations?.length || 0,
        max: maxDevices,
        devices: activations?.map(a => ({
          id: a.id,
          device_name: a.device_name,
          activated_at: a.activated_at,
          last_seen_at: a.last_seen_at,
        })),
      },
    })
  } catch {
    return NextResponse.json(
      { error: 'Internal server error' },
      { status: 500 }
    )
  }
}
