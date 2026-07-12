import { NextRequest, NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'
import { createHmac, timingSafeEqual } from 'crypto'
import { Resend } from 'resend'

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
)
const resend = new Resend(process.env.RESEND_API_KEY)
const FROM = 'ATLAS by InterLinked <atlas@interlinked.digital>'
const CODE_TTL_MS = 10 * 60 * 1000 // 10 minutes

function signToken(email: string, code: string, ts: number): string {
  const secret = process.env.SUPABASE_SERVICE_ROLE_KEY!
  return createHmac('sha256', secret).update(`${email}|${code}|${ts}`).digest('hex')
}

function safeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false
  return timingSafeEqual(Buffer.from(a), Buffer.from(b))
}

export async function POST(req: NextRequest) {
  const { email, code, token, ts } = await req.json()
  if (!email || !code || !token || !ts) {
    return NextResponse.json({ error: 'Missing fields' }, { status: 400 })
  }

  // Check expiry
  if (Date.now() - Number(ts) > CODE_TTL_MS) {
    return NextResponse.json({ error: 'Code expired. Request a new one.' }, { status: 400 })
  }

  // Verify HMAC
  const expected = signToken(email, code, Number(ts))
  if (!safeEqual(expected, token)) {
    return NextResponse.json({ error: 'Invalid code.' }, { status: 400 })
  }

  // Insert into waitlist (ignore duplicate)
  const { error } = await supabase.from('atlas_waitlist').insert({ email })
  if (error && error.code !== '23505') {
    return NextResponse.json({ error: 'Could not save email' }, { status: 500 })
  }

  // Get count for admin email
  const { count } = await supabase.from('atlas_waitlist').select('*', { count: 'exact', head: true })

  // Send welcome email (with demo link)
  await resend.emails.send({
    from: FROM,
    to: email,
    subject: "You're on the ATLAS waitlist",
    html: waitlistEmail(),
    text: `You're on the ATLAS waitlist.\n\nWatch the ATLAS demo: https://www.interlinked.digital/atlas?demo=1\n\nWe'll send you one email the moment ATLAS launches — no spam, ever.\n\n— InterLinked`,
    headers: {
      'List-Unsubscribe': '<mailto:atlas@interlinked.digital?subject=unsubscribe>',
      'X-Entity-Ref-ID': `atlas-waitlist-${Date.now()}`,
    },
  })

  // Admin notify
  await resend.emails.send({
    from: FROM,
    to: 'interlinked.digital@gmail.com',
    subject: `ATLAS — New waitlist subscriber`,
    html: adminEmail(email, count ?? 0),
  })

  return NextResponse.json({ success: true })
}

// ─── Emails ───────────────────────────────────────────────────────────────────

const BG     = '#080809'
const CARD   = '#111113'
const BORDER = 'rgba(255,255,255,0.08)'
const TEAL   = '#3ECFB2'
const INDIGO = '#5E6AD2'
const WHITE  = '#FFFFFF'
const MUTED  = '#525260'
const SUBTLE = '#8A8A96'
const LOGO_URL = 'https://www.interlinked.digital/atlas-logo.png'

function waitlistEmail() {
  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>You're on the ATLAS waitlist</title>
  <style>@font-face{font-family:"SF-Intellivised";src:url("https://www.interlinked.digital/fonts/SF-Intellivised.ttf") format("truetype");}</style>
</head>
<body style="margin:0;padding:0;background:${BG};-webkit-font-smoothing:antialiased;">
<table width="100%" cellpadding="0" cellspacing="0" border="0" style="background:${BG};">
  <tr><td align="center" style="padding:52px 20px 48px;">
    <table width="100%" cellpadding="0" cellspacing="0" border="0" style="max-width:520px;">

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

      <tr><td style="background:${CARD};border-radius:16px;border:1px solid ${BORDER};overflow:hidden;box-shadow:0 40px 80px rgba(0,0,0,0.6);">
        <div style="height:2px;background:linear-gradient(90deg,${TEAL} 0%,${INDIGO} 100%);"></div>
        <div style="padding:36px 36px 40px;">

          <p style="margin:0 0 14px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:10px;font-weight:600;letter-spacing:3px;text-transform:uppercase;color:${MUTED};">Waitlist Confirmed</p>
          <h1 style="margin:0 0 12px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:24px;font-weight:700;letter-spacing:-0.03em;line-height:1.2;color:${WHITE};">You're in.</h1>
          <p style="margin:0 0 28px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:14px;color:${MUTED};line-height:1.7;letter-spacing:-0.005em;">
            We'll send you a notification the moment ATLAS is available. No spam — one email, when it's ready.
          </p>

          <table cellpadding="0" cellspacing="0" border="0" style="margin-bottom:28px;">
            <tr>
              <td style="padding-right:8px;">
                <table cellpadding="0" cellspacing="0" border="0"><tr><td style="background:#0C0C0E;border:1px solid rgba(255,255,255,0.08);border-radius:8px;padding:9px 16px;">
                  <table cellpadding="0" cellspacing="0" border="0"><tr>
                    <td style="padding-right:8px;vertical-align:middle;"><img src="data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='14' height='14' viewBox='0 0 24 24' fill='%238A8A96'%3E%3Cpath d='M18.71 19.5c-.83 1.24-1.71 2.45-3.05 2.47-1.34.03-1.77-.79-3.29-.79-1.53 0-2 .77-3.27.82-1.31.05-2.3-1.32-3.14-2.53C4.25 17 2.94 12.45 4.7 9.39c.87-1.52 2.43-2.48 4.12-2.51 1.28-.02 2.5.87 3.29.87.78 0 2.26-1.07 3.8-.91.65.03 2.47.26 3.64 1.98-.09.06-2.17 1.28-2.15 3.81.03 3.02 2.65 4.03 2.68 4.04-.03.07-.42 1.44-1.37 2.83M13 3.5c.73-.83 1.94-1.46 2.94-1.5.13 1.17-.34 2.35-1.04 3.19-.69.85-1.83 1.51-2.95 1.42-.15-1.15.41-2.35 1.05-3.11z'%2F%3E%3C%2Fsvg%3E" width="14" height="14" alt="" style="display:block;border:0;"></td>
                    <td style="font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:12px;font-weight:600;color:${SUBTLE};">macOS</td>
                  </tr></table>
                </td></tr></table>
              </td>
              <td>
                <table cellpadding="0" cellspacing="0" border="0"><tr><td style="background:#0C0C0E;border:1px solid rgba(255,255,255,0.08);border-radius:8px;padding:9px 16px;">
                  <table cellpadding="0" cellspacing="0" border="0"><tr>
                    <td style="padding-right:8px;vertical-align:middle;"><img src="data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='14' height='14' viewBox='0 0 22 22'%3E%3Crect x='0' y='0' width='10' height='10' rx='1' fill='%238A8A96'%2F%3E%3Crect x='12' y='0' width='10' height='10' rx='1' fill='%238A8A96'%2F%3E%3Crect x='0' y='12' width='10' height='10' rx='1' fill='%238A8A96'%2F%3E%3Crect x='12' y='12' width='10' height='10' rx='1' fill='%238A8A96'%2F%3E%3C%2Fsvg%3E" width="14" height="14" alt="" style="display:block;border:0;"></td>
                    <td style="font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:12px;font-weight:600;color:${SUBTLE};">Windows</td>
                  </tr></table>
                </td></tr></table>
              </td>
            </tr>
          </table>

          <table cellpadding="0" cellspacing="0" border="0" width="100%" style="margin:0 0 24px;">
            <tr><td style="height:1px;background:${BORDER};font-size:0;">&nbsp;</td></tr>
          </table>

          <p style="margin:0 0 6px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:10px;font-weight:600;letter-spacing:3px;text-transform:uppercase;color:${TEAL};">Demo Now Live</p>
          <p style="margin:0 0 16px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:16px;font-weight:700;color:${WHITE};letter-spacing:-0.02em;">Watch ATLAS in action.</p>

          <a href="https://www.interlinked.digital/atlas?demo=1" target="_blank" style="display:block;text-decoration:none;margin-bottom:16px;">
            <img src="https://img.youtube.com/vi/OHbz5y4kHeg/maxresdefault.jpg" width="100%" alt="Watch ATLAS Demo" style="display:block;border:0;width:100%;border-radius:10px;border:1px solid rgba(255,255,255,0.08);">
          </a>

          <table cellpadding="0" cellspacing="0" border="0" width="100%" style="margin-bottom:28px;">
            <tr><td align="center">
              <a href="https://www.interlinked.digital/atlas?demo=1" target="_blank" style="display:inline-block;background:${TEAL};color:#080809;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:14px;font-weight:700;letter-spacing:-0.01em;text-decoration:none;padding:14px 32px;border-radius:10px;">Watch the Demo →</a>
            </td></tr>
          </table>

          <table cellpadding="0" cellspacing="0" border="0" width="100%" style="margin:0 0 20px;">
            <tr><td style="height:1px;background:${BORDER};font-size:0;">&nbsp;</td></tr>
          </table>

          <p style="margin:0 0 16px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:13px;font-weight:600;color:${SUBTLE};line-height:1.6;">
            Stay Tuned for Subscription Plans &amp; Pricing.
          </p>
          <p style="margin:0 0 10px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:12px;color:${MUTED};line-height:1.6;">
            To make sure you get our emails, add <span style="color:${SUBTLE};">atlas@interlinked.digital</span> to your contacts.
          </p>
          <p style="margin:0;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:12px;color:${MUTED};line-height:1.6;">
            Questions? <a href="mailto:interlinked.digital@gmail.com" style="color:${SUBTLE};text-decoration:none;">interlinked.digital@gmail.com</a>
          </p>

        </div>
      </td></tr>

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

function adminEmail(subscriberEmail: string, totalCount: number) {
  return `<!DOCTYPE html>
<html lang="en">
<head><meta charset="UTF-8"><title>New ATLAS Subscriber</title></head>
<body style="margin:0;padding:0;background:${BG};">
<table width="100%" cellpadding="0" cellspacing="0" border="0" style="background:${BG};">
  <tr><td align="center" style="padding:52px 20px 48px;">
    <table width="100%" cellpadding="0" cellspacing="0" border="0" style="max-width:520px;">
      <tr><td style="background:${CARD};border-radius:16px;border:1px solid ${BORDER};overflow:hidden;">
        <div style="height:2px;background:linear-gradient(90deg,${TEAL} 0%,${INDIGO} 100%);"></div>
        <div style="padding:36px 36px 40px;">
          <p style="margin:0 0 14px;font-family:-apple-system,sans-serif;font-size:10px;font-weight:600;letter-spacing:3px;text-transform:uppercase;color:${MUTED};">Waitlist</p>
          <h1 style="margin:0 0 20px;font-family:-apple-system,sans-serif;font-size:22px;font-weight:700;color:#fff;">New subscriber</h1>
          <table cellpadding="0" cellspacing="0" border="0" width="100%" style="background:#0C0C0E;border-radius:10px;border:1px solid ${BORDER};margin-bottom:24px;">
            <tr><td style="padding:20px 22px;">
              <p style="margin:0 0 4px;font-family:-apple-system,sans-serif;font-size:11px;font-weight:600;letter-spacing:2px;text-transform:uppercase;color:${MUTED};">Email</p>
              <p style="margin:0 0 16px;font-family:-apple-system,sans-serif;font-size:15px;font-weight:600;color:#fff;">${subscriberEmail}</p>
              <p style="margin:0 0 4px;font-family:-apple-system,sans-serif;font-size:11px;font-weight:600;letter-spacing:2px;text-transform:uppercase;color:${MUTED};">Total subscribers</p>
              <p style="margin:0;font-family:-apple-system,sans-serif;font-size:24px;font-weight:700;color:${TEAL};">${totalCount}</p>
            </td></tr>
          </table>
          <p style="margin:0;font-family:-apple-system,sans-serif;font-size:12px;color:${MUTED};">
            <a href="https://supabase.com/dashboard/project/bmbmzytnpsntgzmutikp/editor" style="color:${SUBTLE};text-decoration:none;">View in Supabase →</a>
          </p>
        </div>
      </td></tr>
    </table>
  </td></tr>
</table>
</body>
</html>`
}
