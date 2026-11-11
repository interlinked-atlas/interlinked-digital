import { Resend } from 'resend'

const resend = new Resend(process.env.RESEND_API_KEY)
const FROM = 'ATLAS by InterLinked <atlas@interlinked.digital>'

export type EmailTemplate = 'welcome' | 'subscription-confirmed' | 'subscription-renewed' | 'subscription-cancelled' | 'subscription-cancelled-no-grace' | 'grace-period-reminder' | 'account-suspended' | 'payment-failed' | 'password-reset' | 'new-device-signin' | 'admin-notification' | 'support-received' | 'launch' | 'anticipation' | 'october-announcement' | 'features-pricing-launch' | 'demo-features-announcement' | 'oct31-launch' | 'nov12-launch' | 'release'

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
      subject: 'ATLAS — Subscription Confirmed',
      html: subscriptionConfirmedEmail(data.renewDate ?? ''),
    },
    'subscription-renewed': {
      subject: 'ATLAS — Payment Receipt',
      html: subscriptionRenewedEmail(data.amount ?? '', data.chargeDate ?? '', data.nextRenewDate ?? '', data.receiptUrl ?? ''),
    },
    'subscription-cancelled': {
      subject: 'ATLAS — Subscription Cancelled (10 Days to Reactivate Free)',
      html: subscriptionCancelledEmail(data.deadlineDate ?? ''),
    },
    'subscription-cancelled-no-grace': {
      subject: 'Your ATLAS subscription has been cancelled',
      html: subscriptionCancelledNoGraceEmail(),
    },
    'grace-period-reminder': {
      subject: 'ATLAS — 2 Days Left to Reactivate Free',
      html: gracePeriodReminderEmail(data.deadlineDate ?? ''),
    },
    'account-suspended': {
      subject: 'Your ATLAS account is now permanently closed',
      html: accountSuspendedEmail(),
    },
    'payment-failed': {
      subject: 'ATLAS — Payment Failed',
      html: paymentFailedEmail(),
    },
    'password-reset': {
      subject: 'ATLAS — Reset your password',
      html: passwordResetEmail(data.resetUrl ?? ''),
    },
    'new-device-signin': {
      subject: 'ATLAS — New Device Signed In',
      html: newDeviceSigninEmail(data.deviceName ?? 'Unknown Mac', data.signInTime ?? ''),
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
    'anticipation': {
      subject: 'ATLAS for macOS — Coming Soon',
      html: anticipationEmail(),
    },
    'october-announcement': {
      subject: 'ATLAS — macOS available this October.',
      html: octoberAnnouncementEmail(),
    },
    'features-pricing-launch': {
      subject: 'ATLAS — Plan, Pricing & Features are now live.',
      html: featuresPricingLaunchEmail(),
    },
    'demo-features-announcement': {
      subject: 'ATLAS — New Demo: Features Overview',
      html: demoFeaturesAnnouncementEmail(),
    },
    'oct31-launch': {
      subject: 'ATLAS is here — October 31st.',
      html: oct31LaunchEmail(),
    },
    'nov12-launch': {
      subject: 'ATLAS — New Launch Date: November 12th',
      html: nov12LaunchEmail(),
    },
    'release': {
      subject: 'ATLAS V1 is live — you get it first.',
      html: releaseEmail(),
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

// ─────────────────────────────────────────────
// Layout shell
// ─────────────────────────────────────────────
function base(title: string, body: string) {
  return `<!DOCTYPE html>
<html lang="en" style="background:${BG};">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <!-- Force the dark presentation explicitly — do not let the recipient's
       client auto-pick a theme or invert these colors. -->
  <meta name="color-scheme" content="dark">
  <meta name="supported-color-schemes" content="dark">
  <title>${title}</title>
  <style>
    @font-face{font-family:"SF-Intellivised";src:url("https://www.interlinked.digital/fonts/SF-Intellivised.ttf") format("truetype");font-weight:normal;font-style:normal;}
    :root { color-scheme: dark; supported-color-schemes: dark; }
  </style>
</head>
<body style="margin:0;padding:0;background:${BG};background-color:${BG};-webkit-font-smoothing:antialiased;" bgcolor="${BG}">
<table width="100%" cellpadding="0" cellspacing="0" border="0" style="background:${BG};background-color:${BG};" bgcolor="${BG}">
  <tr><td align="center" style="padding:52px 20px 48px;background:${BG};background-color:${BG};" bgcolor="${BG}">
    <table width="100%" cellpadding="0" cellspacing="0" border="0" style="max-width:520px;">

      <!-- Logo -->
      <tr><td align="center" style="padding-bottom:40px;">
        <table cellpadding="0" cellspacing="0" border="0">
          <tr>
            <td align="center" valign="middle" style="padding-right:12px;">
              <img src="https://www.interlinked.digital/email-assets/atlas-icon.png" width="36" height="36" alt="ATLAS" style="display:block;border:0;width:36px;height:36px;object-fit:contain;">
            </td>
            <td align="left" valign="middle">
              <img src="https://www.interlinked.digital/email-assets/atlas-wordmark.png" width="149" height="31" alt="ATLAS" style="display:block;border:0;">
            </td>
          </tr>
        </table>
      </td></tr>

      <!-- Card -->
      <tr><td style="background:${CARD};background-color:${CARD};border-radius:16px;border:1px solid ${BORDER};overflow:hidden;box-shadow:0 40px 80px rgba(0,0,0,0.6);" bgcolor="${CARD}">
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
  // bgcolor is set explicitly alongside the CSS background — some clients'
  // dark-mode handling can otherwise override an inline style background on
  // a <td>, which would make the button blend into the dark page background.
  return `<table cellpadding="0" cellspacing="0" border="0">
    <tr>
      <td align="center" style="background:${TEAL};background-color:${TEAL};border-radius:10px;" bgcolor="${TEAL}">
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

function subscriptionConfirmedEmail(renewDate: string) {
  const features = [
    'TITAN MEMORY™ — learns every installer you run',
    'TITAN CORE™ — universal engine for PKG, DMG, ZIP &amp; more',
    'Bulk installation &amp; full install history',
    'Uninstall, Rollback &amp; ATLAS RECOVERY KIT™',
    'Built-in virus scanner &amp; ATLAS CLEANER™',
  ]

  return base('ATLAS — Subscription Confirmed', `
    <!-- Top teal bar -->
    <div style="height:2px;background:${TEAL};"></div>

    <div style="padding:36px 36px 40px;">
      ${eyebrow('ATLAS')}
      ${heading('Subscription confirmed.')}
      ${body(`You're now subscribed to <strong style="color:${WHITE};font-weight:600;">ATLAS</strong>.${renewDate ? ` Your subscription renews on <strong style="color:${WHITE};font-weight:600;">${renewDate}</strong>.` : ''}`)}

      ${infoBox(features, TEAL)}

      ${tealBtn('View Account Dashboard', 'https://www.interlinked.digital/atlas/account')}
    </div>
  `)
}

function subscriptionRenewedEmail(amount: string, chargeDate: string, nextRenewDate: string, receiptUrl: string) {
  const rows = [
    `Amount charged: <strong style="color:${WHITE};">${amount}</strong>`,
    chargeDate ? `Billed on: <strong style="color:${WHITE};">${chargeDate}</strong>` : '',
    nextRenewDate ? `Next renewal: <strong style="color:${WHITE};">${nextRenewDate}</strong>` : '',
  ].filter(Boolean)

  return base('ATLAS — Payment Receipt', `
    <!-- Top teal bar -->
    <div style="height:2px;background:${TEAL};"></div>

    <div style="padding:36px 36px 40px;">
      ${eyebrow('Receipt')}
      ${heading('Your ATLAS subscription renewed.')}
      ${body(`Thanks for staying subscribed to <strong style="color:${WHITE};font-weight:600;">ATLAS</strong>. Here's your receipt for this billing period.`)}

      ${infoBox(rows, TEAL)}

      ${tealBtn('View Payment History', 'https://www.interlinked.digital/atlas/account#billing-history')}
      ${receiptUrl ? `<div style="height:10px;"></div>${ghostBtn('View Official Stripe Receipt', receiptUrl, SUBTLE)}` : ''}

      ${divider()}
      <p style="margin:0;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:12px;color:${MUTED};">
        Questions about this charge? <a href="mailto:interlinked.digital@gmail.com" style="color:${SUBTLE};text-decoration:none;">interlinked.digital@gmail.com</a>
      </p>
    </div>
  `)
}

function subscriptionCancelledEmail(deadlineDate: string) {
  return base('ATLAS — Subscription Cancelled', `
    <!-- Top amber bar -->
    <div style="height:2px;background:#F0A030;"></div>

    <div style="padding:36px 36px 40px;">
      ${eyebrow('Subscription Cancelled')}
      ${heading('Your access has ended — but not for good.')}
      ${body(`Your ATLAS subscription has been cancelled and access has ended immediately. Since you already paid for this period, you have <strong style="color:${WHITE};font-weight:600;">10 days</strong> to come back completely free — no new charge, same billing date as before.`)}

      <table cellpadding="0" cellspacing="0" border="0" width="100%" style="background:#0C0C0E;border-radius:10px;border:1px solid ${BORDER};margin:0 0 28px;">
        <tr><td style="padding:18px 20px;">
          <p style="margin:0 0 4px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:10px;font-weight:600;letter-spacing:2.5px;text-transform:uppercase;color:#F0A030;">Reactivation window closes</p>
          <p style="margin:0;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:16px;font-weight:700;color:${WHITE};">${deadlineDate || 'in 10 days'}</p>
        </td></tr>
      </table>

      ${tealBtn('Reactivate My Account', 'https://www.interlinked.digital/atlas/account')}

      ${divider()}
      <p style="margin:0 0 20px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:12px;color:${MUTED};line-height:1.7;">
        If this window passes without reactivating, your account will be permanently closed — you'd need to sign up again (with the same or a different email) and start a new subscription to use ATLAS again. Your install history, logs, and recovery kits are kept either way; they're just not accessible until the account is active again.
      </p>
      <p style="margin:0;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:12px;color:${MUTED};">
        Questions? <a href="mailto:interlinked.digital@gmail.com" style="color:${SUBTLE};text-decoration:none;">interlinked.digital@gmail.com</a>
      </p>
    </div>
  `)
}

function gracePeriodReminderEmail(deadlineDate: string) {
  return base('ATLAS — 2 Days Left to Reactivate', `
    <!-- Top amber bar -->
    <div style="height:2px;background:#F0A030;"></div>

    <div style="padding:36px 36px 40px;">
      ${eyebrow('Reminder')}
      ${heading('Your reactivation window closes in 2 days.')}
      ${body(`You cancelled ATLAS recently, and your free reactivation window is almost up. After that, your account will be <strong style="color:${WHITE};font-weight:600;">permanently closed</strong> and you'd need to sign up and pay again to use ATLAS.`)}

      <table cellpadding="0" cellspacing="0" border="0" width="100%" style="background:#0C0C0E;border-radius:10px;border:1px solid ${BORDER};margin:0 0 28px;">
        <tr><td style="padding:18px 20px;">
          <p style="margin:0 0 4px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:10px;font-weight:600;letter-spacing:2.5px;text-transform:uppercase;color:#F0A030;">Window closes</p>
          <p style="margin:0;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:16px;font-weight:700;color:${WHITE};">${deadlineDate || 'in 2 days'}</p>
        </td></tr>
      </table>

      ${tealBtn('Reactivate My Account', 'https://www.interlinked.digital/atlas/account')}

      ${divider()}
      <p style="margin:0;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:12px;color:${MUTED};">
        Questions? <a href="mailto:interlinked.digital@gmail.com" style="color:${SUBTLE};text-decoration:none;">interlinked.digital@gmail.com</a>
      </p>
    </div>
  `)
}

function accountSuspendedEmail() {
  return base('Your ATLAS account is now permanently closed', `
    <!-- Top red bar -->
    <div style="height:2px;background:#EF5B5B;"></div>

    <div style="padding:36px 36px 40px;">
      ${eyebrow('Account Closed')}
      ${heading('Your 10-day window has ended.')}
      ${body(`Your ATLAS account is now permanently closed — the free reactivation window after cancelling has passed. This account can't be reopened, but you're welcome to sign up again at any time, with this same email or a different one.`)}

      <table cellpadding="0" cellspacing="0" border="0" width="100%" style="background:#0C0C0E;border-radius:10px;border:1px solid ${BORDER};margin:0 0 28px;">
        <tr><td style="padding:18px 20px;">
          <p style="margin:0;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:13px;color:${SUBTLE};line-height:1.7;">
            Your install history, logs, and recovery kits haven't been deleted — they're just no longer accessible on this account. A new subscription starts fresh.
          </p>
        </td></tr>
      </table>

      ${tealBtn('Sign Up Again', 'https://www.interlinked.digital/atlas/plans')}

      ${divider()}
      <p style="margin:0;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:12px;color:${MUTED};">
        Questions? <a href="mailto:interlinked.digital@gmail.com" style="color:${SUBTLE};text-decoration:none;">interlinked.digital@gmail.com</a>
      </p>
    </div>
  `)
}

function subscriptionCancelledNoGraceEmail() {
  return base('ATLAS — Subscription Cancelled', `
    <!-- Top amber bar -->
    <div style="height:2px;background:#F0A030;"></div>

    <div style="padding:36px 36px 40px;">
      ${eyebrow('Subscription Ended')}
      ${heading('Your subscription has been cancelled.')}
      ${body(`Your ATLAS subscription has been cancelled and access has ended immediately. You've already used your one-time free-reactivation window on a previous cancellation, so this cancellation is final — but you're welcome to subscribe again at any time.`)}

      <table cellpadding="0" cellspacing="0" border="0" width="100%" style="background:#0C0C0E;border-radius:10px;border:1px solid ${BORDER};margin:0 0 28px;">
        <tr><td style="padding:18px 20px;">
          <p style="margin:0;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:13px;color:${SUBTLE};line-height:1.7;">
            Re-subscribe from your account dashboard whenever you're ready. Your install history and device registrations are preserved.
          </p>
        </td></tr>
      </table>

      ${ghostBtn('Re-subscribe to ATLAS', 'https://www.interlinked.digital/atlas/checkout?plan=atlas', TEAL)}

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

function newDeviceSigninEmail(deviceName: string, signInTime: string) {
  return base('ATLAS — New Device Signed In', `
    <!-- Top amber bar -->
    <div style="height:2px;background:#F0A030;"></div>

    <div style="padding:36px 36px 40px;">
      ${eyebrow('Security Alert')}
      ${heading('A new device signed in to your ATLAS account.')}
      ${body(`<strong style="color:${WHITE};font-weight:600;">${escapeHtml(deviceName)}</strong> was just activated on your account${signInTime ? ` at <strong style="color:${WHITE};font-weight:600;">${escapeHtml(signInTime)}</strong>` : ''}. If this was you, no action is needed.`)}

      <table cellpadding="0" cellspacing="0" border="0" width="100%" style="background:#0C0C0E;border-radius:10px;border:1px solid ${BORDER};margin:0 0 28px;">
        <tr><td style="padding:18px 20px;">
          <p style="margin:0;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:13px;color:${SUBTLE};line-height:1.7;">
            Wasn't you? Remove this device from your account immediately, then change your password.
          </p>
        </td></tr>
      </table>

      ${tealBtn('Review Devices', 'https://www.interlinked.digital/atlas/account?tab=devices')}

      ${divider()}
      <p style="margin:0;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:12px;color:${MUTED};">
        Need help? <a href="mailto:interlinked.digital@gmail.com" style="color:${SUBTLE};text-decoration:none;">interlinked.digital@gmail.com</a>
      </p>
    </div>
  `)
}

function escapeHtml(str: string): string {
  return str
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;')
}

function adminNotificationEmail(subject: string, bodyText: string) {
  const safeSubject = escapeHtml(subject)
  const lines = bodyText.split('\n').map(l =>
    `<p style="margin:0 0 6px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:13px;color:${SUBTLE};line-height:1.7;">${escapeHtml(l) || '&nbsp;'}</p>`
  ).join('')
  return base(`ATLAS Admin — ${safeSubject}`, `
    <div style="height:2px;background:#7C6FEE;"></div>
    <div style="padding:36px 36px 40px;">
      ${eyebrow('Admin Notification')}
      ${heading(safeSubject)}
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
        'Built-in virus scanner &amp; ATLAS CLEANER™',
        'Uninstall, Rollback &amp; ATLAS RECOVERY KIT™',
      ], TEAL)}

      ${tealBtn('Download ATLAS', 'https://www.interlinked.digital/atlas')}

      ${divider()}
      <p style="margin:0;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:12px;color:${MUTED};line-height:1.6;">
        Questions? Reply to this email or reach us at <a href="mailto:interlinked.digital@gmail.com" style="color:${SUBTLE};text-decoration:none;">interlinked.digital@gmail.com</a>
      </p>
    </div>
  `)
}

const APPLE_LOGO_B64 = 'data:image/svg+xml;base64,PHN2ZyB3aWR0aD0iMTYiIGhlaWdodD0iMTYiIHZpZXdCb3g9IjAgMCAyNCAyNCIgZmlsbD0iIzhBOEE5NiIgeG1sbnM9Imh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnIj48cGF0aCBkPSJNMTguNzEgMTkuNWMtLjgzIDEuMjQtMS43MSAyLjQ1LTMuMDUgMi40Ny0xLjM0LjAzLTEuNzctLjc5LTMuMjktLjc5LTEuNTMgMC0yIC43Ny0zLjI3LjgyLTEuMzEuMDUtMi4zLTEuMzItMy4xNC0yLjUzQzQuMjUgMTcgMi45NCAxMi40NSA0LjcgOS4zOWMuODctMS41MiAyLjQzLTIuNDggNC4xMi0yLjUxIDEuMjgtLjAyIDIuNS44NyAzLjI5Ljg3Ljc4IDAgMi4yNi0xLjA3IDMuOC0uOTEuNjUuMDMgMi40Ny4yNiAzLjY0IDEuOTgtLjA5LjA2LTIuMTcgMS4yOC0yLjE1IDMuODEuMDMgMy4wMiAyLjY1IDQuMDMgMi42OCA0LjA0LS4wMy4wNy0uNDIgMS40NC0xLjM3IDIuODNNMTMgMy41Yy43My0uODMgMS45NC0xLjQ2IDIuOTQtMS41LjEzIDEuMTctLjM0IDIuMzUtMS4wNCAzLjE5LS42OS44NS0xLjgzIDEuNTEtMi45NSAxLjQyLS4xNS0xLjE1LjQxLTIuMzUgMS4wNS0zLjExeiIvPjwvc3ZnPg=='

function anticipationEmail() {
  return base('ATLAS for macOS — Coming Soon', `
    <!-- Top teal/indigo gradient bar -->
    <div style="height:2px;background:linear-gradient(90deg,${TEAL} 0%,${INDIGO} 100%);"></div>

    <div style="padding:36px 36px 40px;">
      ${eyebrow('Coming Soon')}

      <!-- macOS visual treatment -->
      <table cellpadding="0" cellspacing="0" border="0" style="margin:0 0 16px;">
        <tr>
          <td valign="middle" style="padding-right:8px;">
            <img src="${APPLE_LOGO_B64}" width="18" height="18" alt="" style="display:block;border:0;opacity:0.7;">
          </td>
          <td valign="middle">
            <span style="font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:13px;font-weight:500;color:#ADADBA;letter-spacing:0.01em;">macOS</span>
          </td>
        </tr>
      </table>

      ${heading('ATLAS is almost here.')}
      <p style="margin:0 0 24px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:14px;color:#ADADBA;line-height:1.7;letter-spacing:-0.005em;">Something is coming for your Mac. We're putting the finishing touches on ATLAS — you're on the waitlist, so you'll be the first to know when it launches.</p>

      ${eyebrow('Pricing Announcing Soon')}
      <table cellpadding="0" cellspacing="0" border="0" width="100%" style="background:#0C0C0E;border-radius:10px;border:1px solid ${BORDER};margin:0 0 28px;">
        <tr><td style="padding:18px 20px 18px;">
          <p style="margin:0 0 2px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:13px;font-weight:600;color:${WHITE};letter-spacing:-0.01em;">ATLAS</p>
          <p style="margin:0;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:12px;color:#8A8A96;">One plan. Every feature. $30/month.</p>
        </td></tr>
      </table>

      ${divider()}
      <p style="margin:0;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:13px;font-weight:600;color:#ADADBA;line-height:1.6;">
        Windows Version Coming Soon.
      </p>
    </div>
  `)
}

function octoberAnnouncementEmail() {
  return base('ATLAS — macOS available this October.', `
    <!-- Top teal/indigo gradient bar -->
    <div style="height:2px;background:linear-gradient(90deg,${TEAL} 0%,${INDIGO} 100%);"></div>

    <div style="padding:36px 36px 40px;">
      ${eyebrow('Coming October')}

      <!-- macOS badge -->
      <table cellpadding="0" cellspacing="0" border="0" style="margin:0 0 16px;">
        <tr>
          <td valign="middle" style="padding-right:8px;">
            <img src="${APPLE_LOGO_B64}" width="18" height="18" alt="" style="display:block;border:0;opacity:0.7;">
          </td>
          <td valign="middle">
            <span style="font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:13px;font-weight:500;color:#ADADBA;letter-spacing:0.01em;">macOS</span>
          </td>
        </tr>
      </table>

      ${heading('ATLAS for macOS.')}
      <p style="margin:0 0 28px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:14px;color:#ADADBA;line-height:1.7;letter-spacing:-0.005em;">ATLAS for macOS will be available this October. You're on the waitlist — you'll be among the first to hear when it launches.</p>

      ${tealBtn('Learn More', 'https://www.interlinked.digital/atlas')}

      ${divider()}

      <!-- Secondary: Windows teaser -->
      <p style="margin:0 0 4px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:13px;font-weight:600;color:#ADADBA;letter-spacing:-0.01em;">Windows Version of ATLAS Coming Soon.</p>
      <p style="margin:0 0 24px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:12px;color:${MUTED};line-height:1.6;">Stay tuned for more updates.</p>

      ${divider()}

      <p style="margin:0;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:12px;color:${MUTED};line-height:1.6;">
        You're receiving this because you joined the ATLAS waitlist. To unsubscribe, reply with "unsubscribe" or email <a href="mailto:atlas@interlinked.digital?subject=unsubscribe" style="color:${SUBTLE};text-decoration:none;">atlas@interlinked.digital</a>.
      </p>
    </div>
  `)
}

function featuresPricingLaunchEmail() {
  return base('ATLAS — Plan, Pricing & Features are now live.', `
    <!-- Top teal/indigo gradient bar -->
    <div style="height:2px;background:linear-gradient(90deg,${TEAL} 0%,${INDIGO} 100%);"></div>

    <div style="padding:36px 36px 40px;">
      ${eyebrow('Now Available')}
      ${heading('Plan, Pricing & Features are live.')}
      ${body("You're on the ATLAS waitlist, so you're seeing this first. The ATLAS plan, pricing, and full feature breakdown just went live on the site — take a look.")}

      ${tealBtn('Explore ATLAS', 'https://www.interlinked.digital/atlas')}

      ${divider()}
      <p style="margin:0;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:12px;color:${MUTED};line-height:1.6;">
        You're receiving this because you joined the ATLAS waitlist. To unsubscribe, reply with "unsubscribe" or email <a href="mailto:atlas@interlinked.digital?subject=unsubscribe" style="color:${SUBTLE};text-decoration:none;">atlas@interlinked.digital</a>.
      </p>
    </div>
  `)
}

function demoFeaturesAnnouncementEmail() {
  const demoUrl = 'https://www.interlinked.digital/atlas'
  const thumbUrl = 'https://img.youtube.com/vi/q2W9QkBKz2c/maxresdefault.jpg'

  return base('ATLAS — New Demo: Features Overview', `
    <!-- Top teal/indigo gradient bar -->
    <div style="height:2px;background:linear-gradient(90deg,${TEAL} 0%,${INDIGO} 100%);"></div>

    <div style="padding:36px 36px 40px;">
      ${eyebrow('New Demo')}
      ${heading("See ATLAS's Features Overview.")}
      ${body("Check out the new Features Overview to experience ATLAS and its potential. Tap below to watch it — and explore the full feature breakdown on the site.")}

      <!-- Clickable video thumbnail -->
      <a href="${demoUrl}" target="_blank" style="display:block;text-decoration:none;margin-bottom:24px;position:relative;">
        <img src="${thumbUrl}" width="100%" alt="Watch the ATLAS Features Overview demo" style="display:block;border:0;width:100%;border-radius:10px;border:1px solid ${BORDER};">
      </a>

      ${tealBtn('Watch the Demo', demoUrl)}

      ${divider()}
      <p style="margin:0;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:12px;color:${MUTED};line-height:1.6;">
        You're receiving this because you joined the ATLAS waitlist. To unsubscribe, reply with "unsubscribe" or email <a href="mailto:atlas@interlinked.digital?subject=unsubscribe" style="color:${SUBTLE};text-decoration:none;">atlas@interlinked.digital</a>.
      </p>
    </div>
  `)
}

function oct31LaunchEmail() {
  return base('ATLAS is here — October 31st.', `
    <!-- Top teal/indigo gradient bar -->
    <div style="height:2px;background:linear-gradient(90deg,${TEAL} 0%,${INDIGO} 100%);"></div>

    <div style="padding:36px 36px 40px;">
      ${eyebrow('It’s Launch Day')}

      <!-- macOS badge -->
      <table cellpadding="0" cellspacing="0" border="0" style="margin:0 0 16px;">
        <tr>
          <td valign="middle" style="padding-right:8px;">
            <img src="${APPLE_LOGO_B64}" width="18" height="18" alt="" style="display:block;border:0;opacity:0.7;">
          </td>
          <td valign="middle">
            <span style="font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:13px;font-weight:500;color:#ADADBA;letter-spacing:0.01em;">macOS</span>
          </td>
        </tr>
      </table>

      ${heading('ATLAS is here.')}
      <p style="margin:0 0 28px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:14px;color:#ADADBA;line-height:1.7;letter-spacing:-0.005em;">
        You've been waiting — and it's finally here. Starting <strong style="color:${WHITE};font-weight:600;">October 31st</strong>, ATLAS is live for macOS.
        No more remote-install services, no more handing a stranger access to your Mac, no more paying per file. ATLAS installs, tracks,
        and cleanly uninstalls your plugins and software automatically — all on your own machine, privately.
      </p>

      ${infoBox([
        'TITAN MEMORY™ — learns every installer you run',
        'TITAN CORE™ — universal engine for PKG, DMG, ZIP &amp; more',
        'Bulk installation &amp; full install history',
        'Uninstall, Rollback &amp; ATLAS RECOVERY KIT™',
        'Built-in virus scanner &amp; ATLAS CLEANER™',
        'One flat plan — $30/month, everything included',
      ], TEAL)}

      ${divider()}

      <!-- Secondary: Windows teaser -->
      <p style="margin:0 0 4px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:13px;font-weight:600;color:#ADADBA;letter-spacing:-0.01em;">Windows Version of ATLAS Coming Soon.</p>
      <p style="margin:0 0 24px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:12px;color:${MUTED};line-height:1.6;">Stay tuned for more updates.</p>

      ${divider()}

      <p style="margin:0;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:12px;color:${MUTED};line-height:1.6;">
        You're receiving this because you joined the ATLAS waitlist. To unsubscribe, reply with "unsubscribe" or email <a href="mailto:atlas@interlinked.digital?subject=unsubscribe" style="color:${SUBTLE};text-decoration:none;">atlas@interlinked.digital</a>.
      </p>
    </div>
  `)
}

function nov12LaunchEmail() {
  return base('ATLAS — New Launch Date: November 12th', `
    <!-- Top teal/indigo gradient bar -->
    <div style="height:2px;background:linear-gradient(90deg,${TEAL} 0%,${INDIGO} 100%);"></div>

    <div style="padding:36px 36px 40px;">
      ${eyebrow('Updated Release Date')}

      <!-- macOS badge -->
      <table cellpadding="0" cellspacing="0" border="0" style="margin:0 0 16px;">
        <tr>
          <td valign="middle" style="padding-right:8px;">
            <img src="${APPLE_LOGO_B64}" width="18" height="18" alt="" style="display:block;border:0;opacity:0.7;">
          </td>
          <td valign="middle">
            <span style="font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:13px;font-weight:500;color:#ADADBA;letter-spacing:0.01em;">macOS</span>
          </td>
        </tr>
      </table>

      ${heading('A quick update on launch.')}
      <p style="margin:0 0 20px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:14px;color:#ADADBA;line-height:1.7;letter-spacing:-0.005em;">
        We're moving the ATLAS launch to <strong style="color:${WHITE};font-weight:600;">November 12th</strong>.
      </p>
      <p style="margin:0 0 20px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:14px;color:#ADADBA;line-height:1.7;letter-spacing:-0.005em;">
        We ran into a few last-minute things we wanted to get right before putting ATLAS in your hands — rather than rush them out the door, we're taking the extra time to make sure version 1 launches the way it should.
      </p>
      <p style="margin:0 0 28px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:14px;color:#ADADBA;line-height:1.7;letter-spacing:-0.005em;">
        The response to ATLAS has been incredible, and the anticipation for this release is higher than we expected — which is exactly why we want to get it right. Thank you for your patience. You're on the waitlist, so you'll be the first to know the moment it's live.
      </p>

      ${tealBtn('Learn More', 'https://www.interlinked.digital/atlas')}

      ${divider()}

      <!-- Secondary: Windows teaser -->
      <p style="margin:0 0 4px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:13px;font-weight:600;color:#ADADBA;letter-spacing:-0.01em;">Windows Version of ATLAS Coming Soon.</p>
      <p style="margin:0 0 24px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:12px;color:${MUTED};line-height:1.6;">Stay tuned for more updates.</p>

      ${divider()}

      <p style="margin:0;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:12px;color:${MUTED};line-height:1.6;">
        You're receiving this because you joined the ATLAS waitlist. To unsubscribe, reply with "unsubscribe" or email <a href="mailto:atlas@interlinked.digital?subject=unsubscribe" style="color:${SUBTLE};text-decoration:none;">atlas@interlinked.digital</a>.
      </p>
    </div>
  `)
}

function releaseEmail() {
  return base('ATLAS V1 is live', `
    <!-- Top teal/indigo gradient bar -->
    <div style="height:2px;background:linear-gradient(90deg,${TEAL} 0%,${INDIGO} 100%);"></div>

    <div style="padding:36px 36px 40px;">
      ${eyebrow('Waitlist Exclusive · Live Now')}

      <!-- macOS badge -->
      <table cellpadding="0" cellspacing="0" border="0" style="margin:0 0 16px;">
        <tr>
          <td valign="middle" style="padding-right:8px;">
            <img src="${APPLE_LOGO_B64}" width="18" height="18" alt="" style="display:block;border:0;opacity:0.7;">
          </td>
          <td valign="middle">
            <span style="font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:13px;font-weight:500;color:#ADADBA;letter-spacing:0.01em;">macOS</span>
          </td>
        </tr>
      </table>

      ${heading('ATLAS V1 is here. You get it first.')}
      <p style="margin:0 0 28px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:14px;color:#ADADBA;line-height:1.7;letter-spacing:-0.005em;">
        You joined the ATLAS waitlist before anyone else — which means before we open this up to anyone else,
        <strong style="color:${WHITE};font-weight:600;">you're first in line.</strong> ATLAS V1 for macOS is live right now.
        No more remote-install services, no more handing a stranger access to your Mac, no more paying per file.
        ATLAS installs, tracks, and cleanly uninstalls your plugins and software automatically — all on your own machine, privately.
      </p>

      ${infoBox([
        'TITAN MEMORY™ — learns every installer you run',
        'TITAN CORE™ — universal engine for PKG, DMG, ZIP &amp; more',
        'Bulk installation &amp; full install history',
        'Uninstall, Rollback &amp; ATLAS RECOVERY KIT™',
        'Built-in virus scanner &amp; ATLAS CLEANER™',
      ], TEAL)}

      ${tealBtn('Get ATLAS V1', 'https://www.interlinked.digital/atlas')}

      ${divider()}

      <!-- Secondary: Windows teaser -->
      <p style="margin:0 0 4px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:13px;font-weight:600;color:#ADADBA;letter-spacing:-0.01em;">Windows Version of ATLAS Coming Soon.</p>
      <p style="margin:0 0 24px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:12px;color:${MUTED};line-height:1.6;">Stay tuned for more updates.</p>

      ${divider()}

      <p style="margin:0;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:12px;color:${MUTED};line-height:1.6;">
        You're receiving this because you joined the ATLAS waitlist. To unsubscribe, reply with "unsubscribe" or email <a href="mailto:atlas@interlinked.digital?subject=unsubscribe" style="color:${SUBTLE};text-decoration:none;">atlas@interlinked.digital</a>.
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
