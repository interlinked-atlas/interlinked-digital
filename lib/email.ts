import { Resend } from 'resend'

const resend = new Resend(process.env.RESEND_API_KEY)
const FROM = 'ATLAS by InterLinked <atlas@interlinked.digital>'

export type EmailTemplate = 'welcome' | 'subscription-confirmed' | 'subscription-cancelled' | 'payment-failed' | 'password-reset' | 'admin-notification' | 'support-received' | 'launch'

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
    'password-reset': {
      subject: 'ATLAS — Reset your password',
      html: passwordResetEmail(data.resetUrl ?? ''),
    },
    'admin-notification': {
      subject: data.subject ?? 'ATLAS Admin Alert',
      html: adminNotificationEmail(data.subject ?? '', data.body ?? ''),
    },
    'support-received': {
      subject: 'ATLAS — We received your support request',
      html: supportReceivedEmail(data.issueType ?? 'General', data.message ?? ''),
    },
    'launch': {
      subject: 'ATLAS is live — Download now',
      html: launchEmail(),
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
const LOGO_URL  = 'data:image/png;base64,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'

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
  <style>@font-face{font-family:"SF-Intellivised";src:url("https://www.interlinked.digital/fonts/SF-Intellivised.ttf") format("truetype");font-weight:normal;font-style:normal;}</style>
</head>
<body style="margin:0;padding:0;background:${BG};-webkit-font-smoothing:antialiased;">
<style>@font-face{font-family:"SF-Intellivised";src:url("https://www.interlinked.digital/fonts/SF-Intellivised.ttf") format("truetype");font-weight:normal;font-style:normal;}</style>
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
      ${eyebrow(`ATLAS ${plan}`)}
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
      ${body(`Your ATLAS subscription has been cancelled and access has ended immediately. You can re-subscribe at any time to restore full access.`)}

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

function passwordResetEmail(resetUrl: string) {
  return base('ATLAS — Reset your password', `
    <!-- Top indigo bar -->
    <div style="height:2px;background:${INDIGO};"></div>

    <div style="padding:36px 36px 40px;">
      ${eyebrow('Password Reset')}
      ${heading('Reset your password.')}
      ${body("We received a request to reset the password for your ATLAS account. Click the button below to choose a new password. This link expires in 1 hour.")}

      <table cellpadding="0" cellspacing="0" border="0" style="margin:0 0 28px;">
        <tr>
          <td align="center" style="background:${INDIGO};border-radius:10px;">
            <a href="${resetUrl}" style="display:inline-block;padding:13px 28px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:13px;font-weight:700;letter-spacing:-0.01em;color:#FFFFFF;text-decoration:none;">Reset Password →</a>
          </td>
        </tr>
      </table>

      ${divider()}
      <p style="margin:0;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:12px;color:${MUTED};line-height:1.6;">
        If you didn't request a password reset, you can safely ignore this email — your password won't change.
      </p>
    </div>
  `)
}

function adminNotificationEmail(subject: string, bodyText: string) {
  const lines = bodyText.split('\n').map(l =>
    `<p style="margin:0 0 6px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:13px;color:${SUBTLE};line-height:1.7;">${l || '&nbsp;'}</p>`
  ).join('')
  return base(`ATLAS Admin — ${subject}`, `
    <div style="height:2px;background:#7C6FEE;"></div>
    <div style="padding:36px 36px 40px;">
      ${eyebrow('Admin Notification')}
      ${heading(subject)}
      <table cellpadding="0" cellspacing="0" border="0" width="100%" style="background:#0C0C0E;border-radius:10px;border:1px solid ${BORDER};margin:0 0 28px;">
        <tr><td style="padding:18px 20px;">${lines}</td></tr>
      </table>
      ${divider()}
      <p style="margin:0;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:11px;color:${MUTED};">
        ATLAS Admin · interlinked.digital
      </p>
    </div>
  `)
}

function launchEmail() {
  return base('ATLAS is live', `
    <!-- Top teal/indigo gradient bar -->
    <div style="height:2px;background:linear-gradient(90deg,${TEAL} 0%,${INDIGO} 100%);"></div>

    <div style="padding:36px 36px 40px;">
      ${eyebrow('Now Available')}
      ${heading('ATLAS is live.')}
      ${body("You're on the waitlist — so you're first. ATLAS for macOS is available right now. Download it, sign up, and automate your software installations in seconds.")}

      ${infoBox([
        'TITAN MEMORY™ — learns every installer you run',
        'TITAN CORE™ — universal engine for PKG, DMG, ZIP &amp; more',
        'TITAN VSCAN™ — built-in malware scanner (Pro)',
        'One-click rollback &amp; recovery (Pro)',
        'Standard and Pro plans available',
      ], TEAL)}

      ${tealBtn('Download ATLAS', 'https://www.interlinked.digital/atlas')}

      ${divider()}
      <p style="margin:0;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:12px;color:${MUTED};line-height:1.6;">
        Questions? Reply to this email or reach us at <a href="mailto:interlinked.digital@gmail.com" style="color:${SUBTLE};text-decoration:none;">interlinked.digital@gmail.com</a>
      </p>
    </div>
  `)
}

function supportReceivedEmail(issueType: string, message: string) {
  const preview = message.length > 180 ? message.slice(0, 180) + '…' : message
  return base('ATLAS — Support Request Received', `
    <!-- Top indigo bar -->
    <div style="height:2px;background:linear-gradient(90deg,#3ECFB2 0%,#5E6AD2 100%);"></div>

    <div style="padding:36px 36px 40px;">
      ${eyebrow('Support')}
      ${heading('We got your message.')}
      ${body("Thanks for reaching out. We've received your support request and will get back to you as soon as possible — typically within 24 hours.")}

      <table cellpadding="0" cellspacing="0" border="0" width="100%" style="background:#0C0C0E;border-radius:10px;border:1px solid rgba(255,255,255,0.08);margin:0 0 28px;">
        <tr><td style="padding:18px 20px;">
          <p style="margin:0 0 6px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:10px;font-weight:600;letter-spacing:2.5px;text-transform:uppercase;color:#525260;">${issueType}</p>
          <p style="margin:0;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:13px;color:#8A8A96;line-height:1.7;">${preview.replace(/\n/g, '<br>')}</p>
        </td></tr>
      </table>

      ${divider()}
      <p style="margin:0;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:12px;color:#525260;line-height:1.6;">
        You can also reply directly to this email and we'll see it.<br>
        <a href="mailto:interlinked.digital@gmail.com" style="color:#8A8A96;text-decoration:none;">interlinked.digital@gmail.com</a>
      </p>
    </div>
  `)
}
