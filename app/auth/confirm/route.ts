import { createClient } from '@/lib/supabase/server'
import { type EmailOtpType } from '@supabase/supabase-js'
import { NextRequest, NextResponse } from 'next/server'

// GET /auth/confirm?token_hash=...&type=recovery&next=...
// Receives the link built by app/api/atlas/auth-email/route.ts for password
// recovery (and any other Supabase email-OTP action using the same shape).
// Verifies the token server-side, which establishes the session via the
// cookie-based Supabase client (lib/supabase/server.ts) — the standard
// @supabase/ssr pattern already used by app/auth/callback/route.ts — then
// redirects to the caller-supplied `next` destination.
//
// `next` is restricted to a same-site relative path to prevent this route
// being turned into an open redirect: only a string starting with a single
// "/" (not "//", which browsers treat as protocol-relative to another host)
// is accepted; anything else falls back to the existing default destination.
function safeNext(next: string | null, origin: string): string {
  const fallback = '/auth/reset-password'
  if (!next) return fallback
  if (!next.startsWith('/') || next.startsWith('//')) return fallback
  try {
    // Resolve against our own origin and re-check it didn't escape it
    // (guards against exotic inputs like "/\evil.com" some browsers normalize).
    const resolved = new URL(next, origin)
    return resolved.origin === origin ? `${resolved.pathname}${resolved.search}` : fallback
  } catch {
    return fallback
  }
}

export async function GET(request: NextRequest) {
  const { searchParams, origin } = request.nextUrl
  const tokenHash = searchParams.get('token_hash')
  const type = searchParams.get('type') as EmailOtpType | null
  const next = safeNext(searchParams.get('next'), origin)

  if (!tokenHash || !type) {
    return NextResponse.redirect(`${origin}/auth/error`)
  }

  const supabase = await createClient()
  const { error } = await supabase.auth.verifyOtp({ type, token_hash: tokenHash })

  if (error) {
    // Missing, invalid, expired, or already-used token — fail closed to the
    // existing error page rather than throwing an unhandled server error.
    return NextResponse.redirect(`${origin}/auth/error`)
  }

  return NextResponse.redirect(`${origin}${next}`)
}
