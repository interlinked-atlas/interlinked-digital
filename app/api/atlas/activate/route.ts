import { NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'
import { SignJWT } from 'jose'

// Service role client for server-side operations
const supabaseAdmin = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
)

// Secret for signing entitlement tokens (should be in env vars)
const ENTITLEMENT_SECRET = new TextEncoder().encode(
  process.env.ENTITLEMENT_SECRET || 'atlas-entitlement-secret-key-change-me'
)

// POST /api/atlas/activate
// Activate a device for the user's subscription
export async function POST(request: Request) {
  try {
    const authHeader = request.headers.get('authorization')
    if (!authHeader?.startsWith('Bearer ')) {
      return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
    }

    const token = authHeader.substring(7)
    
    // Verify the JWT and get user
    const { data: { user }, error: authError } = await supabaseAdmin.auth.getUser(token)
    
    if (authError || !user) {
      return NextResponse.json({ error: 'Invalid token' }, { status: 401 })
    }

    const { machine_uuid, device_name, hardware_hash } = await request.json()

    if (!machine_uuid) {
      return NextResponse.json(
        { error: 'machine_uuid is required' },
        { status: 400 }
      )
    }

    // Get user's subscription
    const { data: subscription, error: subError } = await supabaseAdmin
      .from('subscriptions')
      .select('*')
      .eq('user_id', user.id)
      .eq('status', 'active')
      .single()

    if (subError || !subscription) {
      return NextResponse.json(
        { error: 'No active subscription found' },
        { status: 403 }
      )
    }

    // Check activation limits
    const maxActivations = subscription.plan === 'pro' ? 3 : 1
    
    const { data: existingActivations, error: activationsError } = await supabaseAdmin
      .from('device_activations')
      .select('*')
      .eq('user_id', user.id)
      .eq('is_active', true)

    if (activationsError) {
      return NextResponse.json(
        { error: 'Failed to check activations' },
        { status: 500 }
      )
    }

    // Check if this device is already activated
    const existingDevice = existingActivations?.find(a => a.machine_uuid === machine_uuid)
    
    if (existingDevice) {
      // Update last seen and return success
      await supabaseAdmin
        .from('device_activations')
        .update({ last_seen_at: new Date().toISOString() })
        .eq('id', existingDevice.id)

      // Generate entitlement token
      const entitlementToken = await generateEntitlementToken(user.id, subscription.plan, machine_uuid)

      return NextResponse.json({
        success: true,
        message: 'Device already activated',
        activation_id: existingDevice.id,
        entitlement_token: entitlementToken,
        plan: subscription.plan,
        features: getPlanFeatures(subscription.plan),
      })
    }

    // Check if at limit
    if (existingActivations && existingActivations.length >= maxActivations) {
      return NextResponse.json(
        { 
          error: 'Activation limit reached',
          current_activations: existingActivations.length,
          max_activations: maxActivations,
        },
        { status: 403 }
      )
    }

    // Create new activation
    const { data: newActivation, error: insertError } = await supabaseAdmin
      .from('device_activations')
      .insert({
        user_id: user.id,
        machine_uuid,
        device_name: device_name || 'Unknown Device',
        hardware_hash,
        activated_at: new Date().toISOString(),
        last_seen_at: new Date().toISOString(),
        is_active: true,
      })
      .select()
      .single()

    if (insertError) {
      return NextResponse.json(
        { error: 'Failed to activate device' },
        { status: 500 }
      )
    }

    // Generate entitlement token
    const entitlementToken = await generateEntitlementToken(user.id, subscription.plan, machine_uuid)

    return NextResponse.json({
      success: true,
      message: 'Device activated successfully',
      activation_id: newActivation.id,
      entitlement_token: entitlementToken,
      plan: subscription.plan,
      features: getPlanFeatures(subscription.plan),
      activations_remaining: maxActivations - (existingActivations?.length || 0) - 1,
    })
  } catch {
    return NextResponse.json(
      { error: 'Internal server error' },
      { status: 500 }
    )
  }
}

// DELETE /api/atlas/activate
// Deactivate a device
export async function DELETE(request: Request) {
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

    const { machine_uuid } = await request.json()

    if (!machine_uuid) {
      return NextResponse.json(
        { error: 'machine_uuid is required' },
        { status: 400 }
      )
    }

    const { error } = await supabaseAdmin
      .from('device_activations')
      .update({ is_active: false })
      .eq('user_id', user.id)
      .eq('machine_uuid', machine_uuid)

    if (error) {
      return NextResponse.json(
        { error: 'Failed to deactivate device' },
        { status: 500 }
      )
    }

    return NextResponse.json({
      success: true,
      message: 'Device deactivated successfully',
    })
  } catch {
    return NextResponse.json(
      { error: 'Internal server error' },
      { status: 500 }
    )
  }
}

async function generateEntitlementToken(userId: string, plan: string, machineUuid: string) {
  // Short-lived token (15 minutes) for offline verification
  const token = await new SignJWT({
    sub: userId,
    plan,
    machine: machineUuid,
  })
    .setProtectedHeader({ alg: 'HS256' })
    .setIssuedAt()
    .setExpirationTime('15m')
    .sign(ENTITLEMENT_SECRET)

  return token
}

function getPlanFeatures(plan: string) {
  const features = {
    basic: {
      unlimited_installs: false,
      daily_install_limit: 3,
      bulk_queue: false,
      uninstall_manager: false,
      recovery_system: false,
      max_devices: 1,
    },
    pro: {
      unlimited_installs: true,
      daily_install_limit: null,
      bulk_queue: true,
      uninstall_manager: true,
      recovery_system: true,
      max_devices: 3,
    },
  }
  
  return features[plan as keyof typeof features] || features.basic
}
