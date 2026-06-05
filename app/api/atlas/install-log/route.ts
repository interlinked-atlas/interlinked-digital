import { NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'

const supabaseAdmin = createClient(process.env.NEXT_PUBLIC_SUPABASE_URL!, process.env.SUPABASE_SERVICE_ROLE_KEY!)

export async function POST(request: Request) {
  try {
    const authHeader = request.headers.get('authorization')
    if (!authHeader?.startsWith('Bearer ')) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
    const token = authHeader.substring(7)
    const { data: { user }, error: authError } = await supabaseAdmin.auth.getUser(token)
    if (authError || !user) return NextResponse.json({ error: 'Invalid token' }, { status: 401 })

    const { app_name, device_id } = await request.json()

    // Check plan from profiles (source of truth)
    const { data: profile } = await supabaseAdmin
      .from('profiles').select('plan, subscription_status').eq('id', user.id).single()

    const isActiveSubscription = profile?.subscription_status === 'active'
    const isPro = profile?.plan === 'pro' && isActiveSubscription

    if (!isActiveSubscription) {
      return NextResponse.json({ allowed: false, reason: 'no_active_subscription' }, { status: 403 })
    }

    // Standard plan: enforce 3 installs per 24 hours server-side
    if (!isPro) {
      const since = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString()
      const { count } = await supabaseAdmin
        .from('install_logs')
        .select('*', { count: 'exact', head: true })
        .eq('user_id', user.id)
        .eq('log_type', 'install')
        .gte('installed_at', since)

      if ((count ?? 0) >= 3) {
        const resetAt = new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString()
        return NextResponse.json({
          allowed: false, reason: 'daily_limit_reached',
          limit: 3, used: count, resets_at: resetAt,
        }, { status: 429 })
      }
    }

    // Log the install
    await supabaseAdmin.from('install_logs').insert({
      user_id: user.id, device_id: device_id ?? null,
      app_name, installed_at: new Date().toISOString(),
      log_type: 'install',
    })

    return NextResponse.json({ allowed: true, logged: true })
  } catch {
    return NextResponse.json({ error: 'Internal server error' }, { status: 500 })
  }
}

export async function GET(request: Request) {
  try {
    const authHeader = request.headers.get('authorization')
    if (!authHeader?.startsWith('Bearer ')) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
    const token = authHeader.substring(7)
    const { data: { user }, error: authError } = await supabaseAdmin.auth.getUser(token)
    if (authError || !user) return NextResponse.json({ error: 'Invalid token' }, { status: 401 })

    const { data: profile } = await supabaseAdmin
      .from('profiles').select('plan, subscription_status').eq('id', user.id).single()

    const isPro = profile?.plan === 'pro' && profile?.subscription_status === 'active'
    if (isPro) return NextResponse.json({ plan: 'pro', unlimited: true })

    const since = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString()
    const { count } = await supabaseAdmin
      .from('install_logs')
      .select('*', { count: 'exact', head: true })
      .eq('user_id', user.id).eq('log_type', 'install').gte('installed_at', since)

    return NextResponse.json({
      plan: 'standard', unlimited: false, daily_limit: 3,
      used_today: count ?? 0, remaining: Math.max(0, 3 - (count ?? 0)),
      resets_at: new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString(),
    })
  } catch {
    return NextResponse.json({ error: 'Internal server error' }, { status: 500 })
  }
}
