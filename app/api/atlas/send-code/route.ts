import { NextRequest, NextResponse } from 'next/server'
import { createHmac } from 'crypto'
import { Resend } from 'resend'

const resend = new Resend(process.env.RESEND_API_KEY)
const FROM = 'ATLAS by InterLinked <atlas@interlinked.digital>'

function signToken(email: string, code: string, ts: number): string {
  const secret = process.env.SUPABASE_SERVICE_ROLE_KEY!
  return createHmac('sha256', secret).update(`${email}|${code}|${ts}`).digest('hex')
}

export async function POST(req: NextRequest) {
  const { email } = await req.json()
  if (!email || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
    return NextResponse.json({ error: 'Valid email required' }, { status: 400 })
  }

  // 5-digit code, zero-padded
  const code = String(Math.floor(10000 + Math.random() * 90000))
  const ts = Date.now()
  const token = signToken(email, code, ts)

  await resend.emails.send({
    from: FROM,
    to: email,
    subject: `${code} — your ATLAS verification code`,
    html: verifyEmail(code),
    text: `Your ATLAS verification code is: ${code}\n\nEnter this code on the page to unlock the ATLAS demo. This code expires in 10 minutes.\n\nIf you didn't request this, you can ignore this email.\n\n— InterLinked`,
    headers: {
      'X-Entity-Ref-ID': `atlas-verify-${ts}`,
    },
  })

  return NextResponse.json({ token, ts })
}

// ─── Email ────────────────────────────────────────────────────────────────────

const BG     = '#080809'
const CARD   = '#111113'
const BORDER = 'rgba(255,255,255,0.08)'
const TEAL   = '#3ECFB2'
const INDIGO = '#5E6AD2'
const WHITE  = '#FFFFFF'
const MUTED  = '#525260'
const LOGO_URL = 'https://www.interlinked.digital/atlas-logo.png'

function verifyEmail(code: string) {
  const digits = code.split('')
  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>Your ATLAS verification code</title>
  <style>@font-face{font-family:"SF-Intellivised";src:url("https://www.interlinked.digital/fonts/SF-Intellivised.ttf") format("truetype");}</style>
</head>
<body style="margin:0;padding:0;background:${BG};-webkit-font-smoothing:antialiased;">
<table width="100%" cellpadding="0" cellspacing="0" border="0" style="background:${BG};">
  <tr><td align="center" style="padding:52px 20px 48px;">
    <table width="100%" cellpadding="0" cellspacing="0" border="0" style="max-width:480px;">

      <!-- Logo -->
      <tr><td align="center" style="padding-bottom:40px;">
        <table cellpadding="0" cellspacing="0" border="0"><tr>
          <td align="center" valign="middle" style="padding-right:12px;">
            <img src="${LOGO_URL}" width="36" height="36" alt="ATLAS" style="display:block;border:0;width:36px;height:36px;object-fit:contain;">
          </td>
          <td align="left" valign="middle">
            <span style="font-family:'SF-Intellivised',-apple-system,sans-serif;font-size:22px;font-weight:normal;letter-spacing:10px;color:${WHITE};text-transform:uppercase;display:inline-block;padding-left:2px;">ATLAS</span>
          </td>
        </tr></table>
      </td></tr>

      <!-- Card -->
      <tr><td style="background:${CARD};border-radius:16px;border:1px solid ${BORDER};overflow:hidden;box-shadow:0 40px 80px rgba(0,0,0,0.6);">
        <div style="height:2px;background:linear-gradient(90deg,${TEAL} 0%,${INDIGO} 100%);"></div>
        <div style="padding:36px 36px 40px;">

          <p style="margin:0 0 14px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:10px;font-weight:600;letter-spacing:3px;text-transform:uppercase;color:${MUTED};">Verification</p>
          <h1 style="margin:0 0 10px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:24px;font-weight:700;letter-spacing:-0.03em;color:${WHITE};">Your verification code</h1>
          <p style="margin:0 0 32px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:14px;color:${MUTED};line-height:1.7;">Enter this code on the ATLAS page to unlock your demo. Expires in <strong style="color:#8A8A96;">10 minutes</strong>.</p>

          <!-- Code digits -->
          <table cellpadding="0" cellspacing="0" border="0" style="margin:0 auto 32px;">
            <tr>
              ${digits.map(d => `
              <td style="padding:0 5px;">
                <div style="width:52px;height:64px;background:#0C0C0E;border:1px solid rgba(62,207,178,0.25);border-radius:12px;display:flex;align-items:center;justify-content:center;text-align:center;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:30px;font-weight:700;color:${WHITE};letter-spacing:0;line-height:64px;">${d}</div>
              </td>`).join('')}
            </tr>
          </table>

          <!-- Divider -->
          <table cellpadding="0" cellspacing="0" border="0" width="100%" style="margin-bottom:20px;">
            <tr><td style="height:1px;background:${BORDER};font-size:0;">&nbsp;</td></tr>
          </table>

          <p style="margin:0;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:12px;color:${MUTED};line-height:1.6;">
            Didn't request this? You can safely ignore this email.
          </p>

        </div>
      </td></tr>

      <!-- Footer -->
      <tr><td align="center" style="padding-top:28px;">
        <p style="margin:0 0 6px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:10px;letter-spacing:2.5px;text-transform:uppercase;color:#252530;">INTERLINKED DIGITAL</p>
        <p style="margin:0;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:11px;color:#2A2A38;">
          <a href="https://www.interlinked.digital/atlas" style="color:#32323F;text-decoration:none;">interlinked.digital/atlas</a>
        </p>
      </td></tr>

    </table>
  </td></tr>
</table>
</body>
</html>`
}
