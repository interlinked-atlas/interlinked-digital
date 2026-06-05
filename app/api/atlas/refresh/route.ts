import { NextResponse } from 'next/server'
import { createClient } from '@/lib/supabase/server'

// POST /api/atlas/refresh
// macOS app sends refresh_token, receives new JWT session
export async function POST(request: Request) {
  try {
    const { refresh_token } = await request.json()

    if (!refresh_token) {
      return NextResponse.json(
        { error: 'Refresh token is required' },
        { status: 400 }
      )
    }

    const supabase = await createClient()
    
    const { data, error } = await supabase.auth.refreshSession({
      refresh_token,
    })

    if (error) {
      return NextResponse.json(
        { error: error.message },
        { status: 401 }
      )
    }

    if (!data.session) {
      return NextResponse.json(
        { error: 'Failed to refresh session' },
        { status: 500 }
      )
    }

    return NextResponse.json({
      access_token: data.session.access_token,
      refresh_token: data.session.refresh_token,
      expires_at: data.session.expires_at,
    })
  } catch {
    return NextResponse.json(
      { error: 'Internal server error' },
      { status: 500 }
    )
  }
}
