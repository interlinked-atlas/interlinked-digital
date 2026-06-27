import { NextRequest, NextResponse } from 'next/server'
import { createHmac, timingSafeEqual } from 'crypto'
import { sendEmail } from '@/lib/email'

// Supabase Auth Hook — Custom Email
// URL: https://www.interlinked.digital/api/atlas/auth-email
// Supabase sends HMAC-SHA256 signature in Authorization header as Bearer whsec_...

function verifyHookSignature(rawBody: string, authHeader: string, secret: string): boolean {
  try {
    // Supabase secret format: v1,whsec_<base64>
    const whsecPart = secret.includes(',') ? secret.split(',')[1] : secret
    const keyBytes = Buffer.from(whsecPart.replace('whsec_', ''), 'base64')
    const sig = createHmac('sha256', keyBytes).update(rawBody).digest('hex')
    const expected = `v1,${sig}`
    const given = authHeader.replace('Bearer ', '')
    if (expected.length !== given.length) return false
    return timingSafeEqual(Buffer.from(expected), Buffer.from(given))
  } catch { return false }
}

export async function POST(req: NextRequest) {
  const rawBody = await req.text()
  const authHeader = req.headers.get('authorization') ?? ''
  const hookSecret = process.env.SUPABASE_AUTH_EMAIL_HOOK_SECRET ?? ''

  if (hookSecret && !verifyHookSignature(rawBody, authHeader, hookSecret)) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  }

  const body = JSON.parse(rawBody)

  const { user, email_data } = body
  const to = user?.email
  if (!to) return NextResponse.json({ ok: true })

  const actionType: string = email_data?.email_action_type ?? ''

  if (actionType === 'recovery') {
    // Password reset — build the magic link from token_hash
    const siteUrl = email_data?.site_url ?? 'https://www.interlinked.digital'
    const tokenHash = email_data?.token_hash ?? email_data?.token ?? ''
    const redirectTo = email_data?.redirect_to ?? `${siteUrl}/auth/reset-password`
    const resetUrl = tokenHash
      ? `${siteUrl}/auth/confirm?token_hash=${tokenHash}&type=recovery&next=${encodeURIComponent(redirectTo)}`
      : redirectTo

    await sendEmail({ to, template: 'password-reset', data: { resetUrl } })
  }

  // For signup confirmation — welcome email is already sent via auth-webhook on INSERT
  // so we don't duplicate it here. Return ok to suppress Supabase's default email.
  return NextResponse.json({ ok: true })
}
