import { NextRequest, NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'
import { Resend } from 'resend'

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
)
const resend = new Resend(process.env.RESEND_API_KEY)
const FROM = 'ATLAS by InterLinked <atlas@interlinked.digital>'

export async function POST(req: NextRequest) {
  const { email } = await req.json()
  if (!email || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
    return NextResponse.json({ error: 'Valid email required' }, { status: 400 })
  }

  const { error } = await supabase.from('atlas_waitlist').insert({ email })
  if (error) {
    if (error.code === '23505') {
      // Already on the list — still return success so we don't leak info
      return NextResponse.json({ success: true })
    }
    return NextResponse.json({ error: 'Could not save email' }, { status: 500 })
  }

  // Get current waitlist count
  const { count } = await supabase.from('atlas_waitlist').select('*', { count: 'exact', head: true })

  // Send confirmation email to subscriber
  await resend.emails.send({
    from: FROM,
    to: email,
    subject: "You're on the ATLAS waitlist",
    html: waitlistEmail(),
    text: `You're on the ATLAS waitlist.\n\nWe'll send you one email the moment ATLAS launches — no spam, ever.\n\nTo make sure you get it, add atlas@interlinked.digital to your contacts.\n\nIf you didn't sign up, you can ignore this email.\n\n— InterLinked\ninterlinked.digital/atlas`,
    headers: {
      'List-Unsubscribe': '<mailto:atlas@interlinked.digital?subject=unsubscribe>',
      'X-Entity-Ref-ID': `atlas-waitlist-${Date.now()}`,
    },
  })

  // Notify admin
  await resend.emails.send({
    from: FROM,
    to: 'interlinked.digital@gmail.com',
    subject: `ATLAS — New waitlist subscriber`,
    html: adminNotifyEmail(email, count ?? 0),
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
const LOGO_URL = 'data:image/png;base64,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'

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
<style>@font-face{font-family:"SF-Intellivised";src:url("https://www.interlinked.digital/fonts/SF-Intellivised.ttf") format("truetype");}</style>
<table width="100%" cellpadding="0" cellspacing="0" border="0" style="background:${BG};">
  <tr><td align="center" style="padding:52px 20px 48px;">
    <table width="100%" cellpadding="0" cellspacing="0" border="0" style="max-width:520px;">

      <!-- Logo -->
      <tr><td align="center" style="padding-bottom:40px;">
        <table cellpadding="0" cellspacing="0" border="0">
          <tr>
            <td align="center" valign="middle" style="padding-right:12px;">
              <img src="${LOGO_URL}" width="36" height="36" alt="ATLAS" style="display:block;border:0;width:36px;height:36px;object-fit:contain;">
            </td>
            <td align="left" valign="middle">
              <span style="font-family:'SF-Intellivised',-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:22px;font-weight:normal;letter-spacing:10px;color:${WHITE};text-transform:uppercase;display:inline-block;padding-left:2px;">ATLAS</span>
            </td>
          </tr>
        </table>
      </td></tr>

      <!-- Card -->
      <tr><td style="background:${CARD};border-radius:16px;border:1px solid ${BORDER};overflow:hidden;box-shadow:0 40px 80px rgba(0,0,0,0.6);">

        <!-- Top gradient bar -->
        <div style="height:2px;background:linear-gradient(90deg,${TEAL} 0%,${INDIGO} 100%);"></div>

        <div style="padding:36px 36px 40px;">

          <!-- Eyebrow -->
          <p style="margin:0 0 14px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:10px;font-weight:600;letter-spacing:3px;text-transform:uppercase;color:${MUTED};">Waitlist Confirmed</p>

          <!-- Heading -->
          <h1 style="margin:0 0 12px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:24px;font-weight:700;letter-spacing:-0.03em;line-height:1.2;color:${WHITE};">You're in.</h1>

          <!-- Body -->
          <p style="margin:0 0 28px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:14px;color:${MUTED};line-height:1.7;letter-spacing:-0.005em;">
            We'll send you a notification the moment ATLAS is available. No spam — one email, when it's ready.
          </p>

          <!-- Platform badges -->
          <table cellpadding="0" cellspacing="0" border="0" style="margin-bottom:28px;">
            <tr>
              <td style="padding-right:8px;">
                <table cellpadding="0" cellspacing="0" border="0">
                  <tr><td style="background:#0C0C0E;border:1px solid rgba(255,255,255,0.08);border-radius:8px;padding:9px 16px;">
                    <table cellpadding="0" cellspacing="0" border="0"><tr>
                      <td style="padding-right:8px;vertical-align:middle;"><img src="data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='14' height='14' viewBox='0 0 24 24' fill='%238A8A96'%3E%3Cpath d='M18.71 19.5c-.83 1.24-1.71 2.45-3.05 2.47-1.34.03-1.77-.79-3.29-.79-1.53 0-2 .77-3.27.82-1.31.05-2.3-1.32-3.14-2.53C4.25 17 2.94 12.45 4.7 9.39c.87-1.52 2.43-2.48 4.12-2.51 1.28-.02 2.5.87 3.29.87.78 0 2.26-1.07 3.8-.91.65.03 2.47.26 3.64 1.98-.09.06-2.17 1.28-2.15 3.81.03 3.02 2.65 4.03 2.68 4.04-.03.07-.42 1.44-1.37 2.83M13 3.5c.73-.83 1.94-1.46 2.94-1.5.13 1.17-.34 2.35-1.04 3.19-.69.85-1.83 1.51-2.95 1.42-.15-1.15.41-2.35 1.05-3.11z'%2F%3E%3C%2Fsvg%3E" width="14" height="14" alt="" style="display:block;border:0;"></td>
                      <td style="font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:12px;font-weight:600;color:${SUBTLE};">macOS</td>
                    </tr></table>
                  </td></tr>
                </table>
              </td>
              <td>
                <table cellpadding="0" cellspacing="0" border="0">
                  <tr><td style="background:#0C0C0E;border:1px solid rgba(255,255,255,0.08);border-radius:8px;padding:9px 16px;">
                    <table cellpadding="0" cellspacing="0" border="0"><tr>
                      <td style="padding-right:8px;vertical-align:middle;"><img src="data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='14' height='14' viewBox='0 0 22 22'%3E%3Crect x='0' y='0' width='10' height='10' rx='1' fill='%238A8A96'%2F%3E%3Crect x='12' y='0' width='10' height='10' rx='1' fill='%238A8A96'%2F%3E%3Crect x='0' y='12' width='10' height='10' rx='1' fill='%238A8A96'%2F%3E%3Crect x='12' y='12' width='10' height='10' rx='1' fill='%238A8A96'%2F%3E%3C%2Fsvg%3E" width="14" height="14" alt="" style="display:block;border:0;"></td>
                      <td style="font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:12px;font-weight:600;color:${SUBTLE};">Windows</td>
                    </tr></table>
                  </td></tr>
                </table>
              </td>
            </tr>
          </table>

          <!-- Divider -->
          <table cellpadding="0" cellspacing="0" border="0" width="100%" style="margin:0 0 24px;">
            <tr><td style="height:1px;background:${BORDER};font-size:0;">&nbsp;</td></tr>
          </table>

          <!-- Demo section -->
          <p style="margin:0 0 6px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:10px;font-weight:600;letter-spacing:3px;text-transform:uppercase;color:${TEAL};">Demo Now Live</p>
          <p style="margin:0 0 16px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:16px;font-weight:700;color:${WHITE};letter-spacing:-0.02em;">Watch ATLAS in action.</p>

          <a href="https://www.interlinked.digital/atlas" target="_blank" style="display:block;text-decoration:none;margin-bottom:16px;">
            <img src="https://img.youtube.com/vi/OHbz5y4kHeg/maxresdefault.jpg" width="100%" alt="Watch ATLAS Demo" style="display:block;border:0;width:100%;border-radius:10px;border:1px solid rgba(255,255,255,0.08);">
          </a>

          <table cellpadding="0" cellspacing="0" border="0" width="100%" style="margin-bottom:28px;">
            <tr><td align="center">
              <a href="https://www.interlinked.digital/atlas" target="_blank" style="display:inline-block;background:${TEAL};color:#080809;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:14px;font-weight:700;letter-spacing:-0.01em;text-decoration:none;padding:14px 32px;border-radius:10px;">Watch ATLAS in Action →</a>
            </td></tr>
          </table>

          <!-- Divider -->
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

function adminNotifyEmail(subscriberEmail: string, totalCount: number) {
  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>New ATLAS Subscriber</title>
  <style>@font-face{font-family:"SF-Intellivised";src:url("https://www.interlinked.digital/fonts/SF-Intellivised.ttf") format("truetype");}</style>
</head>
<body style="margin:0;padding:0;background:${BG};-webkit-font-smoothing:antialiased;">
<style>@font-face{font-family:"SF-Intellivised";src:url("https://www.interlinked.digital/fonts/SF-Intellivised.ttf") format("truetype");}</style>
<table width="100%" cellpadding="0" cellspacing="0" border="0" style="background:${BG};">
  <tr><td align="center" style="padding:52px 20px 48px;">
    <table width="100%" cellpadding="0" cellspacing="0" border="0" style="max-width:520px;">

      <!-- Logo -->
      <tr><td align="center" style="padding-bottom:40px;">
        <table cellpadding="0" cellspacing="0" border="0"><tr>
          <td align="center" valign="middle" style="padding-right:12px;">
            <img src="${LOGO_URL}" width="36" height="36" alt="ATLAS" style="display:block;border:0;">
          </td>
          <td align="left" valign="middle">
            <span style="font-family:'SF-Intellivised',-apple-system,sans-serif;font-size:22px;letter-spacing:10px;color:#ffffff;text-transform:uppercase;">ATLAS</span>
          </td>
        </tr></table>
      </td></tr>

      <!-- Card -->
      <tr><td style="background:${CARD};border-radius:16px;border:1px solid ${BORDER};overflow:hidden;box-shadow:0 40px 80px rgba(0,0,0,0.6);">
        <div style="height:2px;background:linear-gradient(90deg,${TEAL} 0%,${INDIGO} 100%);"></div>
        <div style="padding:36px 36px 40px;">

          <p style="margin:0 0 14px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;font-size:10px;font-weight:600;letter-spacing:3px;text-transform:uppercase;color:${MUTED};">Waitlist</p>
          <h1 style="margin:0 0 20px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;font-size:22px;font-weight:700;letter-spacing:-0.03em;color:#ffffff;">New subscriber</h1>

          <!-- Subscriber info box -->
          <table cellpadding="0" cellspacing="0" border="0" width="100%" style="background:#0C0C0E;border-radius:10px;border:1px solid ${BORDER};margin-bottom:24px;">
            <tr><td style="padding:20px 22px;">
              <table cellpadding="0" cellspacing="0" border="0" width="100%">
                <tr>
                  <td style="font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;font-size:11px;font-weight:600;letter-spacing:2px;text-transform:uppercase;color:${MUTED};padding-bottom:6px;">Email</td>
                </tr>
                <tr>
                  <td style="font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;font-size:15px;font-weight:600;color:#ffffff;letter-spacing:-0.01em;">${subscriberEmail}</td>
                </tr>
                <tr><td style="height:16px;"></td></tr>
                <tr>
                  <td style="font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;font-size:11px;font-weight:600;letter-spacing:2px;text-transform:uppercase;color:${MUTED};padding-bottom:6px;">Total subscribers</td>
                </tr>
                <tr>
                  <td style="font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;font-size:24px;font-weight:700;color:${TEAL};letter-spacing:-0.03em;">${totalCount}</td>
                </tr>
              </table>
            </td></tr>
          </table>

          <p style="margin:0;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;font-size:12px;color:${MUTED};line-height:1.6;">
            View all subscribers in <a href="https://supabase.com/dashboard/project/bmbmzytnpsntgzmutikp/editor" style="color:${SUBTLE};text-decoration:none;">Supabase → atlas_waitlist</a>
          </p>

        </div>
      </td></tr>

      <!-- Footer -->
      <tr><td align="center" style="padding-top:28px;">
        <p style="margin:0;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;font-size:10px;letter-spacing:2.5px;text-transform:uppercase;color:#252530;">INTERLINKED DIGITAL</p>
      </td></tr>

    </table>
  </td></tr>
</table>
</body>
</html>`
}
