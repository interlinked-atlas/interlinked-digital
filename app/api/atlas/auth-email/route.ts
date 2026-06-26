import { NextRequest, NextResponse } from 'next/server'
import { sendEmail } from '@/lib/email'

// Supabase Auth Hook — Custom Email
// Configure in Supabase: Authentication → Hooks → Send Email → HTTP
// Set this URL: https://www.interlinked.digital/api/atlas/auth-email
// Secret: SUPABASE_AUTH_EMAIL_HOOK_SECRET (env var)
//
// Supabase sends { user, email_data: { token, token_hash, redirect_to, email_action_type, site_url } }

export async function POST(req: NextRequest) {
  const secret = req.headers.get('x-supabase-hook-secret') ?? req.headers.get('authorization')?.replace('Bearer ', '')
  if (process.env.SUPABASE_AUTH_EMAIL_HOOK_SECRET && secret !== process.env.SUPABASE_AUTH_EMAIL_HOOK_SECRET) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  }

  const body = await req.json().catch(() => null)
  if (!body) return NextResponse.json({ error: 'Invalid body' }, { status: 400 })

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
