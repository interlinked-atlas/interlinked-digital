import { NextRequest, NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'
import { sendEmail } from '@/lib/email'

// Public contact form — no login required (unlike /api/atlas/support, which
// is for already-authenticated in-app/account-dashboard support requests).
// Used by the Support popup on public pages (signup, login) where a visitor
// may not have an account yet.

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
)

const ADMIN_EMAIL = 'interlinked.digital@gmail.com'
const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/

export async function POST(req: NextRequest) {
  let body: Record<string, string>
  try { body = await req.json() } catch {
    return NextResponse.json({ error: 'Invalid body' }, { status: 400 })
  }

  const email   = (body.email ?? '').trim()
  const message = (body.message ?? '').trim()

  if (!email || !EMAIL_RE.test(email)) {
    return NextResponse.json({ error: 'A valid email is required' }, { status: 400 })
  }
  if (!message) {
    return NextResponse.json({ error: 'Message is required' }, { status: 400 })
  }
  if (message.length > 4000) {
    return NextResponse.json({ error: 'Message is too long' }, { status: 400 })
  }

  const { error: insertError } = await supabase.from('support_tickets').insert({
    user_id:    null,
    email,
    issue_type: 'Public Contact',
    message,
    status:     'open',
  })

  if (insertError) {
    console.error('[ATLAS] Public contact insert failed:', insertError.message)
    return NextResponse.json({ error: 'Failed to submit message' }, { status: 500 })
  }

  await sendEmail({
    to: email,
    template: 'support-received',
    data: { issueType: 'General', message },
  })

  await sendEmail({
    to: ADMIN_EMAIL,
    template: 'admin-notification',
    data: {
      subject: `📩 Public Contact Form (${email})`,
      body: [
        `From: ${email}`,
        `Type: Public Contact (not logged in)`,
        ``,
        `Message:`,
        message,
        `\nTime: ${new Date().toUTCString()}`,
      ].join('\n'),
    },
  })

  return NextResponse.json({ ok: true })
}
