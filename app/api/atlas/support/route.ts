import { NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'
import { Resend } from 'resend'

const supabaseAdmin = createClient(process.env.NEXT_PUBLIC_SUPABASE_URL!, process.env.SUPABASE_SERVICE_ROLE_KEY!)
const resend = new Resend(process.env.RESEND_API_KEY)

export async function POST(request: Request) {
  const authHeader = request.headers.get('authorization')
  if (!authHeader?.startsWith('Bearer ')) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  const token = authHeader.substring(7)
  const { data: { user }, error: authError } = await supabaseAdmin.auth.getUser(token)
  if (authError || !user) return NextResponse.json({ error: 'Invalid token' }, { status: 401 })

  const { issue_type, message, attached_log_id, attached_log_content, device_name } = await request.json()
  if (!message?.trim()) return NextResponse.json({ error: 'Message required' }, { status: 400 })

  const { data: profile } = await supabaseAdmin
    .from('profiles').select('plan, subscription_status').eq('id', user.id).single()

  const logBlock = attached_log_content
    ? `\n\n--- Attached Log ---\n${attached_log_content.slice(0, 4000)}`
    : ''

  const adminHtml = `
    <div style="font-family:monospace;background:#07080F;color:#E8ECFF;padding:24px;border-radius:8px;">
      <h2 style="color:#3ECFB2;margin:0 0 16px;">ATLAS Support Ticket</h2>
      <table style="width:100%;border-collapse:collapse;">
        <tr><td style="color:#6B7399;padding:4px 8px 4px 0;white-space:nowrap;">From</td><td style="color:#E8ECFF;">${user.email}</td></tr>
        <tr><td style="color:#6B7399;padding:4px 8px 4px 0;">Issue Type</td><td style="color:#E8ECFF;">${issue_type ?? 'Not specified'}</td></tr>
        <tr><td style="color:#6B7399;padding:4px 8px 4px 0;">Plan</td><td style="color:#E8ECFF;">${profile?.plan ?? 'unknown'} / ${profile?.subscription_status ?? 'unknown'}</td></tr>
        <tr><td style="color:#6B7399;padding:4px 8px 4px 0;">Device</td><td style="color:#E8ECFF;">${device_name ?? 'Not provided'}</td></tr>
      </table>
      <div style="margin:16px 0;padding:16px;background:#111113;border-radius:6px;border:1px solid rgba(255,255,255,0.08);">
        <pre style="margin:0;color:#D0D8F0;white-space:pre-wrap;">${message}</pre>
      </div>
      ${attached_log_content ? `<details><summary style="color:#3ECFB2;cursor:pointer;">View attached log</summary><pre style="background:#111113;padding:12px;border-radius:6px;color:#6B7399;font-size:11px;overflow:auto;max-height:400px;">${attached_log_content.slice(0, 8000)}</pre></details>` : ''}
    </div>`

  await resend.emails.send({
    from: 'ATLAS Support <atlas@interlinked.digital>',
    to: 'interlinked.digital@gmail.com',
    replyTo: user.email!,
    subject: `[ATLAS Support] ${issue_type ?? 'General'} — ${user.email}`,
    html: adminHtml,
  })

  // Confirmation to user
  await resend.emails.send({
    from: 'ATLAS by InterLinked <atlas@interlinked.digital>',
    to: user.email!,
    subject: 'We received your support request — ATLAS',
    html: `<div style="font-family:-apple-system,sans-serif;background:#080809;color:#E8ECFF;padding:32px;max-width:520px;margin:0 auto;border-radius:12px;">
      <p style="color:#3ECFB2;font-size:10px;letter-spacing:3px;text-transform:uppercase;">ATLAS Support</p>
      <h1 style="font-size:22px;font-weight:700;margin:0 0 12px;">We got your message.</h1>
      <p style="color:#8A8A96;line-height:1.7;">We'll review your request and respond to <strong style="color:#E8ECFF;">${user.email}</strong> as soon as possible — usually within 24 hours.</p>
      <div style="background:#111113;border:1px solid rgba(255,255,255,0.08);border-radius:8px;padding:16px;margin:20px 0;">
        <p style="font-size:11px;color:#525260;margin:0 0 4px;">YOUR MESSAGE</p>
        <p style="color:#A0A8C8;font-size:13px;line-height:1.6;margin:0;">${message.slice(0, 500)}${message.length > 500 ? '…' : ''}</p>
      </div>
      <p style="font-size:11px;color:#525260;">ATLAS by InterLinked · interlinked.digital</p>
    </div>`,
  })

  return NextResponse.json({ success: true })
}
