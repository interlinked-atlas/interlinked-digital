import { NextRequest, NextResponse } from 'next/server'
import { sendEmail } from '@/lib/email'

// Supabase Database Webhook: INSERT on auth.users table
// Configure in Supabase: Database -> Webhooks -> new webhook on auth.users INSERT
// Set secret header: x-webhook-secret = SUPABASE_WEBHOOK_SECRET (env var)
export async function POST(req: NextRequest) {
  const secret = req.headers.get('x-webhook-secret')
  if (secret !== process.env.SUPABASE_WEBHOOK_SECRET) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  }

  const body = await req.json()
  const record = body.record  // new auth user row
  if (!record?.email) return NextResponse.json({ ok: true })

  // Send welcome email
  await sendEmail({
    to: record.email,
    template: 'welcome',
    data: { name: record.raw_user_meta_data?.name ?? record.email.split('@')[0] },
  })

  return NextResponse.json({ ok: true })
}
