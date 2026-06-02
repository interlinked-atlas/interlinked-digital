import { Resend } from 'resend'

const resend = new Resend(process.env.RESEND_API_KEY)
const FROM = 'ATLAS by InterLinked <atlas@interlinked.digital>'

export type EmailTemplate = 'welcome' | 'subscription-confirmed' | 'subscription-cancelled' | 'payment-failed'

interface SendOptions {
  to: string
  template: EmailTemplate
  data?: Record<string, string>
}

export async function sendEmail({ to, template, data = {} }: SendOptions) {
  const templates: Record<EmailTemplate, { subject: string; html: string }> = {
    'welcome': {
      subject: 'Welcome to ATLAS',
      html: welcomeEmail(data.name ?? to.split('@')[0]),
    },
    'subscription-confirmed': {
      subject: `ATLAS ${data.plan ?? 'Pro'} — Subscription Confirmed`,
      html: subscriptionConfirmedEmail(data.plan ?? 'Pro', data.renewDate ?? ''),
    },
    'subscription-cancelled': {
      subject: 'Your ATLAS subscription has been cancelled',
      html: subscriptionCancelledEmail(data.endDate ?? ''),
    },
    'payment-failed': {
      subject: 'ATLAS — Payment Failed',
      html: paymentFailedEmail(),
    },
  }

  const { subject, html } = templates[template]
  const { data: result, error } = await resend.emails.send({ from: FROM, to, subject, html })
  if (error) console.error('[email] send error:', error)
  return { result, error }
}

// ─────────────────────────────────────────────
// Shared components
// ─────────────────────────────────────────────

const STAR_SVG = `<svg width="48" height="48" viewBox="0 0 48 48" fill="none" xmlns="http://www.w3.org/2000/svg">
  <path d="M24 4L26.8 21.2L44 24L26.8 26.8L24 44L21.2 26.8L4 24L21.2 21.2L24 4Z" fill="url(#star_grad)" stroke="rgba(62,207,178,0.4)" stroke-width="0.5"/>
  <circle cx="24" cy="24" r="3.5" fill="rgba(62,207,178,0.9)"/>
  <defs>
    <linearGradient id="star_grad" x1="4" y1="4" x2="44" y2="44" gradientUnits="userSpaceOnUse">
      <stop offset="0%" stop-color="#5B8DEF" stop-opacity="0.9"/>
      <stop offset="100%" stop-color="#3ECFB2" stop-opacity="0.9"/>
    </linearGradient>
  </defs>
</svg>`

function base(title: string, accentColor: string, body: string) {
  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>${title}</title>
</head>
<body style="margin:0;padding:0;background:#07080F;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;">
<table width="100%" cellpadding="0" cellspacing="0" border="0" style="background:#07080F;min-height:100vh;">
  <tr><td align="center" style="padding:48px 20px 40px;">
    <table width="100%" cellpadding="0" cellspacing="0" border="0" style="max-width:540px;">

      <!-- Header -->
      <tr><td align="center" style="padding-bottom:36px;">
        <table cellpadding="0" cellspacing="0" border="0">
          <tr>
            <td align="center" style="padding-bottom:14px;">
              ${STAR_SVG}
            </td>
          </tr>
          <tr>
            <td align="center">
              <span style="font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:26px;font-weight:200;letter-spacing:14px;color:#FFFFFF;text-transform:uppercase;display:inline-block;padding-left:14px;">ATLAS</span>
            </td>
          </tr>
          <tr>
            <td align="center" style="padding-top:6px;">
              <span style="font-size:9px;letter-spacing:4px;color:#3A3A4A;text-transform:uppercase;font-weight:400;">by InterLinked©</span>
            </td>
          </tr>
        </table>
      </td></tr>

      <!-- Accent line -->
      <tr><td style="padding-bottom:0;">
        <div style="height:1px;background:linear-gradient(90deg,transparent 0%,${accentColor}55 30%,${accentColor}99 50%,${accentColor}55 70%,transparent 100%);"></div>
      </td></tr>

      <!-- Card -->
      <tr><td style="background:#0C0C0F;border-radius:0 0 16px 16px;border:1px solid rgba(255,255,255,0.06);border-top:none;overflow:hidden;">
        ${body}
      </td></tr>

      <!-- Footer -->
      <tr><td align="center" style="padding-top:32px;padding-bottom:8px;">
        <table cellpadding="0" cellspacing="0" border="0">
          <tr>
            <td align="center" style="padding-bottom:10px;">
              <span style="font-size:9px;letter-spacing:3px;color:#2A2A36;text-transform:uppercase;">INTERLINKED DIGITAL</span>
            </td>
          </tr>
          <tr>
            <td align="center">
              <span style="font-size:11px;color:#2E2E3A;">
                <a href="https://www.interlinked.digital/atlas/account" style="color:#3A3A50;text-decoration:none;">Manage account</a>
                &nbsp;&nbsp;·&nbsp;&nbsp;
                <a href="https://www.interlinked.digital/atlas" style="color:#3A3A50;text-decoration:none;">interlinked.digital</a>
              </span>
            </td>
          </tr>
          <tr>
            <td align="center" style="padding-top:8px;">
              <span style="font-size:10px;color:#1E1E28;">© InterLinked. All rights reserved.</span>
            </td>
          </tr>
        </table>
      </td></tr>

    </table>
  </td></tr>
</table>
</body>
</html>`
}

function tealBtn(text: string, url: string) {
  return `<table cellpadding="0" cellspacing="0" border="0" style="margin-top:24px;">
    <tr>
      <td style="background:linear-gradient(135deg,#3ECFB2 0%,#2ABEAA 100%);border-radius:10px;" align="center">
        <a href="${url}" style="display:inline-block;padding:13px 32px;font-size:13px;font-weight:700;color:#07080F;text-decoration:none;letter-spacing:0.01em;">${text}</a>
      </td>
    </tr>
  </table>`
}

function outlineBtn(text: string, url: string, color: string) {
  return `<table cellpadding="0" cellspacing="0" border="0" style="margin-top:16px;">
    <tr>
      <td style="border:1px solid ${color}55;border-radius:10px;background:${color}0D;" align="center">
        <a href="${url}" style="display:inline-block;padding:13px 32px;font-size:13px;font-weight:600;color:${color};text-decoration:none;letter-spacing:0.01em;">${text}</a>
      </td>
    </tr>
  </table>`
}

function badge(text: string, color: string) {
  return `<span style="display:inline-block;padding:4px 12px;background:${color}18;border:1px solid ${color}44;border-radius:6px;font-size:9px;font-weight:800;letter-spacing:2.5px;color:${color};text-transform:uppercase;">${text}</span>`
}

// ─────────────────────────────────────────────
// Templates
// ─────────────────────────────────────────────

function welcomeEmail(name: string) {
  return base('Welcome to ATLAS', '#3ECFB2', `
    <!-- Top accent bar -->
    <div style="height:3px;background:linear-gradient(90deg,#3ECFB2 0%,#5B8DEF 100%);"></div>

    <div style="padding:36px 40px 40px;">
      <div style="margin-bottom:20px;">${badge('New Account', '#3ECFB2')}</div>

      <h1 style="margin:0 0 10px;font-size:22px;font-weight:700;color:#FFFFFF;letter-spacing:-0.02em;">Welcome, ${name}.</h1>
      <p style="margin:0 0 24px;font-size:14px;color:#6A6A7A;line-height:1.7;">
        Your ATLAS account is active. Download ATLAS for macOS, sign in, and start automating your software installations in seconds.
      </p>

      <!-- Feature list -->
      <table cellpadding="0" cellspacing="0" border="0" width="100%" style="background:#0F0F14;border-radius:12px;border:1px solid rgba(255,255,255,0.05);margin-bottom:8px;">
        <tr><td style="padding:20px 24px;">
          <div style="font-size:9px;letter-spacing:3px;color:#3A3A4A;text-transform:uppercase;margin-bottom:14px;font-weight:600;">WHAT YOU HAVE ACCESS TO</div>
          <table cellpadding="0" cellspacing="0" border="0" width="100%">
            <tr>
              <td style="padding:5px 0;">
                <table cellpadding="0" cellspacing="0" border="0"><tr>
                  <td style="width:20px;font-size:11px;color:#3ECFB2;font-weight:700;">✓</td>
                  <td style="font-size:13px;color:#C0C0CC;letter-spacing:-0.01em;">One-click software installation</td>
                </tr></table>
              </td>
            </tr>
            <tr>
              <td style="padding:5px 0;">
                <table cellpadding="0" cellspacing="0" border="0"><tr>
                  <td style="width:20px;font-size:11px;color:#3ECFB2;font-weight:700;">✓</td>
                  <td style="font-size:13px;color:#C0C0CC;letter-spacing:-0.01em;">Installation history &amp; logs</td>
                </tr></table>
              </td>
            </tr>
            <tr>
              <td style="padding:5px 0;">
                <table cellpadding="0" cellspacing="0" border="0"><tr>
                  <td style="width:20px;font-size:11px;color:#3ECFB2;font-weight:700;">✓</td>
                  <td style="font-size:13px;color:#C0C0CC;letter-spacing:-0.01em;">Real-time sync across devices</td>
                </tr></table>
              </td>
            </tr>
            <tr>
              <td style="padding:5px 0;">
                <table cellpadding="0" cellspacing="0" border="0"><tr>
                  <td style="width:20px;font-size:11px;color:#3ECFB2;font-weight:700;">✓</td>
                  <td style="font-size:13px;color:#C0C0CC;letter-spacing:-0.01em;">Notifications &amp; smart alerts</td>
                </tr></table>
              </td>
            </tr>
          </table>
        </td></tr>
      </table>

      ${tealBtn('Open Account Dashboard', 'https://www.interlinked.digital/atlas/account')}

      <p style="margin:20px 0 0;font-size:11px;color:#3A3A4A;line-height:1.6;">
        Already downloaded ATLAS? Sign in with this email address to activate your account on this device.
      </p>
    </div>
  `)
}

function subscriptionConfirmedEmail(plan: string, renewDate: string) {
  const isPro = plan.toLowerCase() === 'pro'
  const accentColor = isPro ? '#3ECFB2' : '#5B8DEF'
  const barGradient = isPro
    ? 'linear-gradient(90deg,#3ECFB2 0%,#2ABEAA 100%)'
    : 'linear-gradient(90deg,#5B8DEF 0%,#4A7ADE 100%)'

  return base(`ATLAS ${plan} — Confirmed`, accentColor, `
    <!-- Top accent bar -->
    <div style="height:3px;background:${barGradient};"></div>

    <div style="padding:36px 40px 40px;">
      <div style="margin-bottom:20px;">${badge(`ATLAS ${plan}`, accentColor)}</div>

      <h1 style="margin:0 0 10px;font-size:22px;font-weight:700;color:#FFFFFF;letter-spacing:-0.02em;">Subscription confirmed.</h1>
      <p style="margin:0 0 24px;font-size:14px;color:#6A6A7A;line-height:1.7;">
        You're now on the <strong style="color:#FFFFFF;font-weight:600;">ATLAS ${plan}</strong> plan.
        ${renewDate ? `Your subscription renews on <strong style="color:#FFFFFF;font-weight:600;">${renewDate}</strong>.` : 'Thank you for subscribing.'}
      </p>

      <!-- Plan highlights -->
      <table cellpadding="0" cellspacing="0" border="0" width="100%" style="background:#0F0F14;border-radius:12px;border:1px solid ${accentColor}22;margin-bottom:8px;">
        <tr><td style="padding:20px 24px;">
          <div style="font-size:9px;letter-spacing:3px;color:#3A3A4A;text-transform:uppercase;margin-bottom:14px;font-weight:600;">YOUR PLAN INCLUDES</div>
          ${isPro ? `
          <table cellpadding="0" cellspacing="0" border="0" width="100%">
            <tr><td style="padding:5px 0;"><table cellpadding="0" cellspacing="0" border="0"><tr><td style="width:20px;font-size:11px;color:${accentColor};font-weight:700;">✓</td><td style="font-size:13px;color:#C0C0CC;">Up to 3 devices</td></tr></table></td></tr>
            <tr><td style="padding:5px 0;"><table cellpadding="0" cellspacing="0" border="0"><tr><td style="width:20px;font-size:11px;color:${accentColor};font-weight:700;">✓</td><td style="font-size:13px;color:#C0C0CC;">Unlimited installs</td></tr></table></td></tr>
            <tr><td style="padding:5px 0;"><table cellpadding="0" cellspacing="0" border="0"><tr><td style="width:20px;font-size:11px;color:${accentColor};font-weight:700;">✓</td><td style="font-size:13px;color:#C0C0CC;">Bulk installation</td></tr></table></td></tr>
            <tr><td style="padding:5px 0;"><table cellpadding="0" cellspacing="0" border="0"><tr><td style="width:20px;font-size:11px;color:${accentColor};font-weight:700;">✓</td><td style="font-size:13px;color:#C0C0CC;">TITAN CORE™ &amp; Smart Storage</td></tr></table></td></tr>
            <tr><td style="padding:5px 0;"><table cellpadding="0" cellspacing="0" border="0"><tr><td style="width:20px;font-size:11px;color:${accentColor};font-weight:700;">✓</td><td style="font-size:13px;color:#C0C0CC;">Uninstall &amp; Rollback</td></tr></table></td></tr>
          </table>` : `
          <table cellpadding="0" cellspacing="0" border="0" width="100%">
            <tr><td style="padding:5px 0;"><table cellpadding="0" cellspacing="0" border="0"><tr><td style="width:20px;font-size:11px;color:${accentColor};font-weight:700;">✓</td><td style="font-size:13px;color:#C0C0CC;">Single-device access</td></tr></table></td></tr>
            <tr><td style="padding:5px 0;"><table cellpadding="0" cellspacing="0" border="0"><tr><td style="width:20px;font-size:11px;color:${accentColor};font-weight:700;">✓</td><td style="font-size:13px;color:#C0C0CC;">3 installs per day</td></tr></table></td></tr>
            <tr><td style="padding:5px 0;"><table cellpadding="0" cellspacing="0" border="0"><tr><td style="width:20px;font-size:11px;color:${accentColor};font-weight:700;">✓</td><td style="font-size:13px;color:#C0C0CC;">Install history &amp; notifications</td></tr></table></td></tr>
          </table>`}
        </td></tr>
      </table>

      ${tealBtn('View Account Dashboard', 'https://www.interlinked.digital/atlas/account')}
    </div>
  `)
}

function subscriptionCancelledEmail(endDate: string) {
  return base('ATLAS — Subscription Cancelled', '#F0A030', `
    <!-- Top accent bar -->
    <div style="height:3px;background:linear-gradient(90deg,#F0A030 0%,#E09020 100%);"></div>

    <div style="padding:36px 40px 40px;">
      <div style="margin-bottom:20px;">${badge('Subscription Ended', '#F0A030')}</div>

      <h1 style="margin:0 0 10px;font-size:22px;font-weight:700;color:#FFFFFF;letter-spacing:-0.02em;">Your subscription has been cancelled.</h1>
      <p style="margin:0 0 24px;font-size:14px;color:#6A6A7A;line-height:1.7;">
        ${endDate
          ? `You'll continue to have full access until <strong style="color:#FFFFFF;font-weight:600;">${endDate}</strong>. After that date, your account will revert to limited access.`
          : `Your ATLAS subscription has ended. You can re-subscribe at any time to restore full access.`
        }
      </p>

      <!-- Info box -->
      <table cellpadding="0" cellspacing="0" border="0" width="100%" style="background:#0F0F14;border-radius:12px;border:1px solid rgba(240,160,48,0.15);margin-bottom:8px;">
        <tr><td style="padding:20px 24px;">
          <div style="font-size:13px;color:#8A8A96;line-height:1.7;">
            Changed your mind? You can reactivate your subscription from your account dashboard at any time. Your install history and device registrations are preserved.
          </div>
        </td></tr>
      </table>

      ${outlineBtn('Re-subscribe to ATLAS', 'https://www.interlinked.digital/atlas', '#3ECFB2')}

      <p style="margin:20px 0 0;font-size:11px;color:#3A3A4A;line-height:1.6;">
        If you cancelled by mistake or have questions, contact us at <a href="mailto:interlinked.digital@gmail.com" style="color:#4A4A5A;text-decoration:none;">interlinked.digital@gmail.com</a>.
      </p>
    </div>
  `)
}

function paymentFailedEmail() {
  return base('ATLAS — Payment Failed', '#EF5B5B', `
    <!-- Top accent bar -->
    <div style="height:3px;background:linear-gradient(90deg,#EF5B5B 0%,#DE4A4A 100%);"></div>

    <div style="padding:36px 40px 40px;">
      <div style="margin-bottom:20px;">${badge('Action Required', '#EF5B5B')}</div>

      <h1 style="margin:0 0 10px;font-size:22px;font-weight:700;color:#FFFFFF;letter-spacing:-0.02em;">Payment failed.</h1>
      <p style="margin:0 0 24px;font-size:14px;color:#6A6A7A;line-height:1.7;">
        We were unable to process your latest payment for ATLAS. Please update your payment method to avoid any interruption to your subscription.
      </p>

      <!-- Info box -->
      <table cellpadding="0" cellspacing="0" border="0" width="100%" style="background:#0F0F14;border-radius:12px;border:1px solid rgba(239,91,91,0.15);margin-bottom:8px;">
        <tr><td style="padding:20px 24px;">
          <div style="font-size:9px;letter-spacing:3px;color:#3A3A4A;text-transform:uppercase;margin-bottom:12px;font-weight:600;">WHAT TO DO</div>
          <table cellpadding="0" cellspacing="0" border="0" width="100%">
            <tr><td style="padding:5px 0;"><table cellpadding="0" cellspacing="0" border="0"><tr><td style="width:24px;font-size:11px;color:#EF5B5B;font-weight:700;">1.</td><td style="font-size:13px;color:#C0C0CC;">Go to your account dashboard</td></tr></table></td></tr>
            <tr><td style="padding:5px 0;"><table cellpadding="0" cellspacing="0" border="0"><tr><td style="width:24px;font-size:11px;color:#EF5B5B;font-weight:700;">2.</td><td style="font-size:13px;color:#C0C0CC;">Open Payment &amp; Billing</td></tr></table></td></tr>
            <tr><td style="padding:5px 0;"><table cellpadding="0" cellspacing="0" border="0"><tr><td style="width:24px;font-size:11px;color:#EF5B5B;font-weight:700;">3.</td><td style="font-size:13px;color:#C0C0CC;">Update your payment method</td></tr></table></td></tr>
          </table>
        </td></tr>
      </table>

      ${tealBtn('Update Payment Method', 'https://www.interlinked.digital/atlas/account')}

      <p style="margin:20px 0 0;font-size:11px;color:#3A3A4A;line-height:1.6;">
        Need help? Contact us at <a href="mailto:interlinked.digital@gmail.com" style="color:#4A4A5A;text-decoration:none;">interlinked.digital@gmail.com</a>
      </p>
    </div>
  `)
}
