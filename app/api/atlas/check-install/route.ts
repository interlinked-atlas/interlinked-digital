import { NextRequest, NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
)

export async function POST(req: NextRequest) {
  // Verify Bearer token
  const token = req.headers.get('authorization')?.replace('Bearer ', '').trim()
  if (!token) return NextResponse.json({ allowed: false, reason: 'unauthorized' }, { status: 401 })

  const { data: { user }, error: authErr } = await supabase.auth.getUser(token)
  if (authErr || !user) return NextResponse.json({ allowed: false, reason: 'unauthorized' }, { status: 401 })

  // Get plan from profile
  const { data: profile } = await supabase
    .from('profiles')
    .select('plan')
    .eq('id', user.id)
    .single()

  const plan = profile?.plan ?? 'standard'

  // Atomically check + increment via RPC
  const { data, error } = await supabase.rpc('check_and_increment_install', {
    p_user_id: user.id,
    p_plan: plan,
  })

  if (error) {
    console.error('[check-install] RPC error:', error)
    // Fail open — don't block the user if DB is down
    return NextResponse.json({ allowed: true, reason: null, error: error.message })
  }

  return NextResponse.json(data)
}
