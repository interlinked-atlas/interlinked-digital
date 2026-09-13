import { NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'

const supabaseAdmin = createClient(process.env.NEXT_PUBLIC_SUPABASE_URL!, process.env.SUPABASE_SERVICE_ROLE_KEY!)

function isActiveSubscription(plan: string, status: string) {
  return status === 'active' && (plan === 'atlas' || plan === 'pro' || plan === 'standard')
}

export async function POST(request: Request) {
  try {
    const authHeader = request.headers.get('authorization')
    if (!authHeader?.startsWith('Bearer ')) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
    const token = authHeader.substring(7)
    const { data: { user }, error: authError } = await supabaseAdmin.auth.getUser(token)
    if (authError || !user) return NextResponse.json({ error: 'Invalid token' }, { status: 401 })

    const { app_name, device_id } = await request.json()

    const { data: profile } = await supabaseAdmin
      .from('profiles').select('plan, subscription_status').eq('id', user.id).single()

    if (!isActiveSubscription(profile?.plan ?? '', profile?.subscription_status ?? '')) {
      return NextResponse.json({ allowed: false, reason: 'no_active_subscription' }, { status: 403 })
    }

    // No daily limit for ATLAS — log the install directly
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

    return NextResponse.json({ plan: 'atlas', unlimited: false, monthly_limit: 25 })
  } catch {
    return NextResponse.json({ error: 'Internal server error' }, { status: 500 })
  }
}
