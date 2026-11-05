import { NextRequest, NextResponse } from 'next/server'
import { checkRateLimit, getClientIp } from '@/lib/rateLimit'

// POST /api/atlas/login-check
//
// Rate-limit gate only — the website's own login page (app/auth/login/page.tsx)
// calls supabase.auth.signInWithPassword() directly from the browser so that
// @supabase/ssr can set the session cookies correctly, which bypasses
// /api/atlas/login (that route is for the Mac app, which has no cookie jar
// and needs a JWT returned directly). This route closes that gap: the login
// page calls it first, purely to apply the same per-IP limit the rest of the
// auth routes already have, before letting the real sign-in proceed.
export async function POST(req: NextRequest) {
  const ip = getClientIp(req)
  if (!(await checkRateLimit(`ip:${ip}`, 'login', 10, 600))) {
    return NextResponse.json({ error: 'Too many requests, please try again later.' }, { status: 429 })
  }
  return NextResponse.json({ ok: true })
}
