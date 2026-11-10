import { NextRequest, NextResponse } from 'next/server'
import { createHmac, timingSafeEqual } from 'crypto'
import { sendEmail } from '@/lib/email'

// Supabase Auth Hook — Custom Email
// URL: https://www.interlinked.digital/api/atlas/auth-email
//
// Supabase signs these using the Standard Webhooks spec (https://www.standardwebhooks.com),
// NOT a bearer token or a single x-supabase-signature header — confirmed directly
// from a real request's headers: webhook-id, webhook-timestamp, webhook-signature.
// Signed content is `${webhook-id}.${webhook-timestamp}.${rawBody}`, HMAC-SHA256
// with the base64-decoded secret (after stripping its "whsec_" prefix), output
// base64-encoded. webhook-signature can list multiple space-separated "v1,<sig>"
// candidates; any one matching is sufficient.
function verifyHookSignature(rawBody: string, id: string, timestamp: string, signatureHeader: string, secret: string): boolean {
  try {
    const whsecPart = secret.includes(',') ? secret.split(',')[1] : secret
    const keyBytes = Buffer.from(whsecPart.replace('whsec_', ''), 'base64')
    const signedContent = `${id}.${timestamp}.${rawBody}`
    const expectedSig = createHmac('sha256', keyBytes).update(signedContent).digest('base64')
    const candidates = signatureHeader.split(' ').map(s => s.trim()).filter(Boolean)
    return candidates.some(candidate => {
      const [, sig] = candidate.split(',')
      if (!sig || sig.length !== expectedSig.length) return false
      return timingSafeEqual(Buffer.from(sig), Buffer.from(expectedSig))
    })
  } catch { return false }
}

export async function POST(req: NextRequest) {
  const rawBody = await req.text()
  const hookSecret = process.env.SUPABASE_AUTH_EMAIL_HOOK_SECRET ?? ''

  const webhookId        = req.headers.get('webhook-id') ?? ''
  const webhookTimestamp = req.headers.get('webhook-timestamp') ?? ''
  const webhookSignature = req.headers.get('webhook-signature') ?? ''

  if (!hookSecret || !webhookId || !webhookTimestamp || !webhookSignature ||
      !verifyHookSignature(rawBody, webhookId, webhookTimestamp, webhookSignature, hookSecret)) {
    console.error('[auth-email] signature mismatch or missing secret/headers')
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  }

  const body = JSON.parse(rawBody)

  const { user, email_data } = body
  const to = user?.email
  if (!to) return NextResponse.json({ ok: true })

  const actionType: string = email_data?.email_action_type ?? ''

  if (actionType === 'recovery') {
    // Password reset — build the magic link from token_hash.
    // siteUrl is a hardcoded production constant, NOT email_data.site_url —
    // that field was found to resolve to Supabase's own GoTrue API base URL
    // (https://<ref>.supabase.co/auth/v1) rather than the actual website,
    // producing a malformed, unusable link. Destination is also pinned to
    // the ATLAS-branded reset page regardless of email_data.redirect_to (the
    // client's resetPasswordForEmail() call still passes the legacy
    // /auth/reset-password as its own redirectTo, which would otherwise take
    // priority here and silently defeat this change).
    const siteUrl = 'https://www.interlinked.digital'
    const tokenHash = email_data?.token_hash ?? email_data?.token ?? ''
    const redirectTo = `${siteUrl}/atlas/reset-password`
    const resetUrl = tokenHash
      ? `${siteUrl}/auth/confirm?token_hash=${tokenHash}&type=recovery&next=${encodeURIComponent(redirectTo)}`
      : redirectTo

    await sendEmail({ to, template: 'password-reset', data: { resetUrl } })
  }

  // For signup confirmation — welcome email is already sent via auth-webhook on INSERT
  // so we don't duplicate it here. Return ok to suppress Supabase's default email.
  return NextResponse.json({ ok: true })
}
