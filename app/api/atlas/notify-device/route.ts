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

  const { device_name, hardware_uuid } = await request.json()
  if (!user.email) return NextResponse.json({ success: true })

  const now = new Date().toLocaleString('en-US', { dateStyle: 'long', timeStyle: 'short' })

  await resend.emails.send({
    from: 'ATLAS by InterLinked <atlas@interlinked.digital>',
    to: user.email,
    subject: 'New device activated on your ATLAS account',
    html: `<div style="font-family:-apple-system,sans-serif;background:#080809;color:#E8ECFF;padding:32px;max-width:520px;margin:0 auto;border-radius:12px;">
      <p style="color:#3ECFB2;font-size:10px;letter-spacing:3px;text-transform:uppercase;margin:0 0 16px;">Security Notice</p>
      <h1 style="font-size:22px;font-weight:700;margin:0 0 12px;">New device activated.</h1>
      <p style="color:#8A8A96;line-height:1.7;margin:0 0 20px;">ATLAS was just signed into on a new device linked to your account.</p>
      <div style="background:#111113;border:1px solid rgba(255,255,255,0.08);border-radius:10px;padding:18px;margin-bottom:24px;">
        <table style="width:100%;border-collapse:collapse;">
          <tr><td style="color:#525260;font-size:11px;padding:4px 0;width:100px;">Device</td><td style="color:#E8ECFF;font-size:13px;">${device_name ?? 'Unknown Mac'}</td></tr>
          <tr><td style="color:#525260;font-size:11px;padding:4px 0;">Time</td><td style="color:#E8ECFF;font-size:13px;">${now}</td></tr>
        </table>
      </div>
      <p style="color:#8A8A96;font-size:13px;line-height:1.7;">If this was you, no action needed. If you don't recognize this activity, sign in to your account and remove the device.</p>
      <a href="https://www.interlinked.digital/atlas/account" style="display:inline-block;margin-top:16px;padding:12px 24px;background:#3ECFB2;color:#08090E;border-radius:8px;text-decoration:none;font-weight:700;font-size:13px;">Review Devices →</a>
      <p style="font-size:11px;color:#2A2A38;margin-top:24px;">ATLAS by InterLinked · interlinked.digital</p>
    </div>`,
  })

  return NextResponse.json({ success: true })
}
