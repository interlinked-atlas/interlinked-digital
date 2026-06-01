import { NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'

const supabaseAdmin = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
)

// POST /api/atlas/install-log
// Log an installation (for Basic plan rate limiting)
export async function POST(request: Request) {
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

    const { app_name, device_id } = await request.json()

    // Get subscription to check plan
    const { data: subscription } = await supabaseAdmin
      .from('subscriptions')
      .select('plan')
      .eq('user_id', user.id)
      .eq('status', 'active')
      .single()

    if (!subscription) {
      return NextResponse.json(
        { error: 'No active subscription' },
        { status: 403 }
      )
    }

    // For Basic plan, check daily limit
    if (subscription.plan === 'basic') {
      const today = new Date()
      today.setHours(0, 0, 0, 0)
      
      const { count } = await supabaseAdmin
        .from('install_logs')
        .select('*', { count: 'exact', head: true })
        .eq('user_id', user.id)
        .gte('installed_at', today.toISOString())

      if (count && count >= 3) {
        return NextResponse.json({
          allowed: false,
          reason: 'daily_limit_reached',
          limit: 3,
          used: count,
          resets_at: new Date(today.getTime() + 24 * 60 * 60 * 1000).toISOString(),
        }, { status: 429 })
      }
    }

    // Log the installation
    await supabaseAdmin
      .from('install_logs')
      .insert({
        user_id: user.id,
        device_id,
        app_name,
        installed_at: new Date().toISOString(),
      })

    return NextResponse.json({
      allowed: true,
      logged: true,
    })
  } catch {
    return NextResponse.json(
      { error: 'Internal server error' },
      { status: 500 }
    )
  }
}

// GET /api/atlas/install-log
// Get install count for rate limiting display
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
      .select('plan')
      .eq('user_id', user.id)
      .eq('status', 'active')
      .single()

    if (!subscription) {
      return NextResponse.json({ error: 'No active subscription' }, { status: 403 })
    }

    // Pro has unlimited
    if (subscription.plan === 'pro') {
      return NextResponse.json({
        plan: 'pro',
        unlimited: true,
      })
    }

    // For Basic, return today's count
    const today = new Date()
    today.setHours(0, 0, 0, 0)
    
    const { count } = await supabaseAdmin
      .from('install_logs')
      .select('*', { count: 'exact', head: true })
      .eq('user_id', user.id)
      .gte('installed_at', today.toISOString())

    return NextResponse.json({
      plan: 'basic',
      unlimited: false,
      daily_limit: 3,
      used_today: count || 0,
      remaining: Math.max(0, 3 - (count || 0)),
      resets_at: new Date(today.getTime() + 24 * 60 * 60 * 1000).toISOString(),
    })
  } catch {
    return NextResponse.json(
      { error: 'Internal server error' },
      { status: 500 }
    )
  }
}
