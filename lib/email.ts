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
  if (error) { console.error('[email] send error:', JSON.stringify(error)); return { result: null, error: JSON.stringify(error) } }
  return { result, error }
}

// ─────────────────────────────────────────────
// Design tokens — matches interlinked.digital/atlas
// ─────────────────────────────────────────────
const BG        = '#080809'
const CARD      = '#111113'
const BORDER    = 'rgba(255,255,255,0.08)'
const TEAL      = '#3ECFB2'
const INDIGO    = '#5E6AD2'
const WHITE     = '#FFFFFF'
const MUTED     = '#525260'
const SUBTLE    = '#8A8A96'
const LOGO_URL  = 'https://www.interlinked.digital/atlas-logo.png'

// ─────────────────────────────────────────────
// Layout shell
// ─────────────────────────────────────────────
function base(title: string, body: string) {
  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>${title}</title>
</head>
<body style="margin:0;padding:0;background:${BG};-webkit-font-smoothing:antialiased;">
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
              <span style="font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:22px;font-weight:300;letter-spacing:10px;color:${WHITE};text-transform:uppercase;display:inline-block;padding-left:2px;">ATLAS</span>
            </td>
          </tr>
        </table>
      </td></tr>

      <!-- Card -->
      <tr><td style="background:${CARD};border-radius:16px;border:1px solid ${BORDER};overflow:hidden;box-shadow:0 40px 80px rgba(0,0,0,0.6);">
        ${body}
      </td></tr>

      <!-- Footer -->
      <tr><td align="center" style="padding-top:28px;">
        <p style="margin:0 0 6px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:10px;letter-spacing:2.5px;text-transform:uppercase;color:#252530;">INTERLINKED DIGITAL</p>
        <p style="margin:0;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:11px;color:#2A2A38;">
          <a href="https://www.interlinked.digital/atlas/account" style="color:#32323F;text-decoration:none;">Manage account</a>
          &nbsp;&nbsp;·&nbsp;&nbsp;
          <a href="https://www.interlinked.digital/atlas" style="color:#32323F;text-decoration:none;">interlinked.digital</a>
        </p>
      </td></tr>

    </table>
  </td></tr>
</table>
</body>
</html>`
}

// ─────────────────────────────────────────────
// Reusable components
// ─────────────────────────────────────────────
function eyebrow(text: string) {
  return `<p style="margin:0 0 14px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:10px;font-weight:600;letter-spacing:3px;text-transform:uppercase;color:${MUTED};">${text}</p>`
}

function heading(text: string) {
  return `<h1 style="margin:0 0 12px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:24px;font-weight:700;letter-spacing:-0.03em;line-height:1.2;color:${WHITE};">${text}</h1>`
}

function body(text: string) {
  return `<p style="margin:0 0 24px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:14px;color:${MUTED};line-height:1.7;letter-spacing:-0.005em;">${text}</p>`
}

function tealBtn(text: string, url: string) {
  return `<table cellpadding="0" cellspacing="0" border="0">
    <tr>
      <td align="center" style="background:${TEAL};border-radius:10px;">
        <a href="${url}" style="display:inline-block;padding:13px 28px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:13px;font-weight:700;letter-spacing:-0.01em;color:#080809;text-decoration:none;">${text} →</a>
      </td>
    </tr>
  </table>`
}

function ghostBtn(text: string, url: string, color: string) {
  return `<table cellpadding="0" cellspacing="0" border="0">
    <tr>
      <td align="center" style="border:1px solid ${color}44;border-radius:10px;">
        <a href="${url}" style="display:inline-block;padding:12px 28px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:13px;font-weight:600;letter-spacing:-0.01em;color:${color};text-decoration:none;">${text}</a>
      </td>
    </tr>
  </table>`
}

function infoBox(rows: string[], accentColor: string) {
  const items = rows.map(r =>
    `<tr><td style="padding:5px 0;">
      <table cellpadding="0" cellspacing="0" border="0"><tr>
        <td style="width:18px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:11px;font-weight:700;color:${accentColor};vertical-align:top;padding-top:1px;">✓</td>
        <td style="font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:13px;color:#ADADBA;letter-spacing:-0.005em;">${r}</td>
      </tr></table>
    </td></tr>`
  ).join('')
  return `<table cellpadding="0" cellspacing="0" border="0" width="100%" style="background:#0C0C0E;border-radius:10px;border:1px solid ${BORDER};margin:20px 0 24px;">
    <tr><td style="padding:18px 20px;">
      <table cellpadding="0" cellspacing="0" border="0" width="100%">${items}</table>
    </td></tr>
  </table>`
}

function divider() {
  return `<table cellpadding="0" cellspacing="0" border="0" width="100%" style="margin:24px 0;">
    <tr><td style="height:1px;background:${BORDER};font-size:0;">&nbsp;</td></tr>
  </table>`
}

// ─────────────────────────────────────────────
// Templates
// ─────────────────────────────────────────────
function welcomeEmail(name: string) {
  return base('Welcome to ATLAS', `
    <!-- Top teal bar -->
    <div style="height:2px;background:linear-gradient(90deg,${TEAL} 0%,${INDIGO} 100%);"></div>

    <div style="padding:36px 36px 40px;">
      ${eyebrow('New Account')}
      ${heading(`Welcome, ${name}.`)}
      ${body('Your ATLAS account is active. Download ATLAS for macOS, sign in with this email, and start automating your software installations.')}

      ${infoBox([
        'One-click software installation',
        'Installation history &amp; logs',
        'Real-time account sync',
        'Notifications &amp; alerts',
      ], TEAL)}

      ${tealBtn('Open Account Dashboard', 'https://www.interlinked.digital/atlas/account')}

      ${divider()}
      <p style="margin:0;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:12px;color:${MUTED};line-height:1.6;">
        Already have ATLAS installed? Sign in with this email to activate your account on this device.
      </p>
    </div>
  `)
}

function subscriptionConfirmedEmail(plan: string, renewDate: string) {
  const isPro    = plan.toLowerCase() === 'pro'
  const accent   = isPro ? TEAL : INDIGO
  const features = isPro
    ? ['Up to 3 devices', 'Unlimited installs', 'Bulk installation', 'TITAN CORE™ &amp; Smart Storage', 'Uninstall &amp; Rollback']
    : ['Single-device access', '3 installs per day', 'Install history', 'Notifications']

  return base(`ATLAS ${plan} — Confirmed`, `
    <!-- Top accent bar -->
    <div style="height:2px;background:${accent};"></div>

    <div style="padding:36px 36px 40px;">
      ${eyebrow(`Atlas ${plan}`)}
      ${heading('Subscription confirmed.')}
      ${body(`You're now on <strong style="color:${WHITE};font-weight:600;">ATLAS ${plan}</strong>.${renewDate ? ` Your subscription renews on <strong style="color:${WHITE};font-weight:600;">${renewDate}</strong>.` : ''}`)}

      ${infoBox(features, accent)}

      ${tealBtn('View Account Dashboard', 'https://www.interlinked.digital/atlas/account')}
    </div>
  `)
}

function subscriptionCancelledEmail(endDate: string) {
  return base('ATLAS — Subscription Cancelled', `
    <!-- Top amber bar -->
    <div style="height:2px;background:#F0A030;"></div>

    <div style="padding:36px 36px 40px;">
      ${eyebrow('Subscription Ended')}
      ${heading('Your subscription has been cancelled.')}
      ${body(endDate
        ? `You'll have full access until <strong style="color:${WHITE};font-weight:600;">${endDate}</strong>. After that, your account reverts to limited access.`
        : `Your ATLAS subscription has ended. You can re-subscribe at any time to restore full access.`
      )}

      <table cellpadding="0" cellspacing="0" border="0" width="100%" style="background:#0C0C0E;border-radius:10px;border:1px solid ${BORDER};margin:0 0 28px;">
        <tr><td style="padding:18px 20px;">
          <p style="margin:0;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:13px;color:${SUBTLE};line-height:1.7;">
            Changed your mind? Re-subscribe from your account dashboard at any time. Your install history and device registrations are preserved.
          </p>
        </td></tr>
      </table>

      ${ghostBtn('Re-subscribe to ATLAS', 'https://www.interlinked.digital/atlas', TEAL)}

      ${divider()}
      <p style="margin:0;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:12px;color:${MUTED};">
        Questions? <a href="mailto:interlinked.digital@gmail.com" style="color:${SUBTLE};text-decoration:none;">interlinked.digital@gmail.com</a>
      </p>
    </div>
  `)
}

function paymentFailedEmail() {
  return base('ATLAS — Payment Failed', `
    <!-- Top red bar -->
    <div style="height:2px;background:#EF5B5B;"></div>

    <div style="padding:36px 36px 40px;">
      ${eyebrow('Action Required')}
      ${heading('Payment failed.')}
      ${body("We couldn't process your latest ATLAS payment. Please update your payment method to avoid any interruption to your subscription.")}

      <table cellpadding="0" cellspacing="0" border="0" width="100%" style="background:#0C0C0E;border-radius:10px;border:1px solid ${BORDER};margin:0 0 28px;">
        <tr><td style="padding:18px 20px;">
          <table cellpadding="0" cellspacing="0" border="0" width="100%">
            ${['Go to your account dashboard', 'Open Payment &amp; Billing', 'Update your payment method'].map((step, i) =>
              `<tr><td style="padding:5px 0;">
                <table cellpadding="0" cellspacing="0" border="0"><tr>
                  <td style="width:22px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:11px;font-weight:700;color:#EF5B5B;vertical-align:top;padding-top:1px;">${i+1}.</td>
                  <td style="font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:13px;color:#ADADBA;">${step}</td>
                </tr></table>
              </td></tr>`
            ).join('')}
          </table>
        </td></tr>
      </table>

      ${tealBtn('Update Payment Method', 'https://www.interlinked.digital/atlas/account')}

      ${divider()}
      <p style="margin:0;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:12px;color:${MUTED};">
        Need help? <a href="mailto:interlinked.digital@gmail.com" style="color:${SUBTLE};text-decoration:none;">interlinked.digital@gmail.com</a>
      </p>
    </div>
  `)
}
