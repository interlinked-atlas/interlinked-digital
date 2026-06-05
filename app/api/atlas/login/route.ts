import { NextResponse } from 'next/server'
import { createClient } from '@/lib/supabase/server'

// POST /api/atlas/login
// macOS app sends email + password, receives JWT session
export async function POST(request: Request) {
  try {
    const { email, password } = await request.json()

    if (!email || !password) {
      return NextResponse.json(
        { error: 'Email and password are required' },
        { status: 400 }
      )
    }

    const supabase = await createClient()
    
    const { data, error } = await supabase.auth.signInWithPassword({
      email,
      password,
    })

    if (error) {
      return NextResponse.json(
        { error: error.message },
        { status: 401 }
      )
    }

    if (!data.session) {
      return NextResponse.json(
        { error: 'Failed to create session' },
        { status: 500 }
      )
    }

    // Get subscription details
    const { data: subscription } = await supabase
      .from('subscriptions')
      .select('*')
      .eq('user_id', data.user.id)
      .eq('status', 'active')
      .single()

    return NextResponse.json({
      access_token: data.session.access_token,
      refresh_token: data.session.refresh_token,
      expires_at: data.session.expires_at,
      user: {
        id: data.user.id,
        email: data.user.email,
      },
      subscription: subscription ? {
        plan: subscription.plan,
        status: subscription.status,
        current_period_end: subscription.current_period_end,
      } : null,
    })
  } catch {
    return NextResponse.json(
      { error: 'Internal server error' },
      { status: 500 }
    )
  }
}
