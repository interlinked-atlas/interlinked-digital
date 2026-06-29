import { NextRequest, NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'
import { sendEmail } from '@/lib/email'

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
)

const ADMIN_EMAIL = 'interlinked.digital@gmail.com'

export async function POST(req: NextRequest) {
  const token = req.headers.get('authorization')?.replace('Bearer ', '').trim()
  if (!token) return NextResponse.json({ error: 'Missing authorization' }, { status: 401 })

  const { data: { user }, error: authError } = await supabase.auth.getUser(token)
  if (authError || !user) return NextResponse.json({ error: 'Invalid token' }, { status: 401 })

  let body: Record<string, string>
  try { body = await req.json() } catch {
    return NextResponse.json({ error: 'Invalid body' }, { status: 400 })
  }

  const { issue_type, message, attached_log_id, attached_log_content } = body

  if (!message?.trim()) {
    return NextResponse.json({ error: 'Message is required' }, { status: 400 })
  }

  const { data: profile } = await supabase
    .from('profiles').select('email, plan').eq('id', user.id).single()

  const userEmail = profile?.email ?? user.email ?? 'unknown'
  const userPlan  = profile?.plan ?? 'unknown'
  const type      = issue_type ?? 'General'

  const { error: insertError } = await supabase.from('support_tickets').insert({
    user_id:              user.id,
    email:                userEmail,
    issue_type:           type,
    message:              message.trim(),
    attached_log_id:      attached_log_id    ?? null,
    attached_log_content: attached_log_content ?? null,
    status:               'open',
  })

  if (insertError) {
    console.error('[ATLAS] Support ticket insert failed:', insertError.message)
    return NextResponse.json({ error: 'Failed to submit ticket' }, { status: 500 })
  }

  // Notify admin
  await sendEmail({
    to: ADMIN_EMAIL,
    template: 'admin-notification',
    data: {
      subject: `📩 Support Request — ${type} (${userEmail})`,
      body: [
        `From: ${userEmail}`,
        `Plan: ${userPlan.toUpperCase()}`,
        `Type: ${type}`,
        ``,
        `Message:`,
        message.trim(),
        attached_log_id ? `\nAttached Log ID: ${attached_log_id}` : '',
        `\nTime: ${new Date().toUTCString()}`,
      ].join('\n'),
    },
  })

  return NextResponse.json({ ok: true })
}
