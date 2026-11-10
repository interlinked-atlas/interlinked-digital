import { NextRequest, NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
)

// POST /api/atlas/auth/password-changed
//
// Called by the website's reset-password page right after
// supabase.auth.updateUser({ password }) succeeds. A password change does
// NOT by itself invalidate other already-issued sessions (an access token
// already in memory on another device stays cryptographically valid until
// its own expiry, and GoTrue doesn't revoke other refresh tokens on a
// password change) — this route is what actually kicks every other session,
// using the same two mechanisms the rest of ATLAS already relies on:
//
//   1. Stamp profiles.password_changed_at — the ATLAS app's existing 5s
//      periodic poll compares this against the session's own issued-at
//      time and force-signs-out an already-running session within one
//      tick, same mechanism as atlas_suspended.
//   2. Revoke every other refresh token (scope: 'others') so a relaunch
//      with a stale cached refresh token fails to re-authenticate instead
//      of silently picking up a fresh session that would bypass check #1.
//
// The token passed in must be the access token of the session that JUST
// completed the password change — the user's own, newly-issued session,
// verified server-side via getUser(). This never lets anyone revoke
// sessions on an account they are not already authenticated as.
export async function POST(req: NextRequest) {
  let body: { access_token?: string } = {}
  try { body = await req.json() } catch { /* no body sent */ }

  const token = body.access_token?.trim()
  if (!token) return NextResponse.json({ error: 'missing_access_token' }, { status: 400 })

  const { data: { user }, error: userError } = await supabase.auth.getUser(token)
  if (userError || !user) return NextResponse.json({ error: 'invalid_token' }, { status: 401 })

  const { error: updateError } = await supabase
    .from('profiles')
    .update({ password_changed_at: new Date().toISOString() })
    .eq('id', user.id)
  if (updateError) return NextResponse.json({ error: updateError.message }, { status: 500 })

  // Defense in depth for the relaunch path — best-effort, doesn't block the
  // response if it fails, since mechanism #1 above already covers an
  // already-running session.
  try {
    await supabase.auth.admin.signOut(token, 'others')
  } catch { /* non-fatal */ }

  return NextResponse.json({ ok: true })
}
