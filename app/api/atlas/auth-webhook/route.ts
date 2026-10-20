import { NextRequest, NextResponse } from 'next/server'

// Supabase Database Webhook: INSERT on auth.users table
// Configure in Supabase: Database -> Webhooks -> new webhook on auth.users INSERT
// Set secret header: x-webhook-secret = SUPABASE_WEBHOOK_SECRET (env var)
//
// P1-1: the "welcome" email asserts the ATLAS account is active and invites
// immediate download — under the paid-only model that is only true after a
// successful Stripe checkout, not at account creation (an account created
// here has zero ATLAS entitlement). The Stripe webhook's own welcome-email
// send (checkout.session.completed) is now the sole ATLAS welcome email.
// This endpoint intentionally no longer sends anything — kept as a no-op
// (still validates the shared secret and returns 200) rather than removed,
// so the DB trigger that calls it keeps functioning and this can be revived
// with different content later without touching the trigger.
export async function POST(req: NextRequest) {
  const secret = req.headers.get('x-webhook-secret')
  if (secret !== process.env.SUPABASE_WEBHOOK_SECRET) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  }

  return NextResponse.json({ ok: true, sent: false })
}
