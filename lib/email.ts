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
// Email templates
// ─────────────────────────────────────────────

function base(title: string, body: string) {
  return `<!DOCTYPE html>
<html><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>${title}</title></head>
<body style="margin:0;padding:0;background:#07080F;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;">
<table width="100%" cellpadding="0" cellspacing="0" style="background:#07080F;padding:40px 20px;">
  <tr><td align="center">
    <table width="100%" cellpadding="0" cellspacing="0" style="max-width:520px;">
      <!-- Logo -->
      <tr><td align="center" style="padding-bottom:32px;">
        <span style="font-family:monospace;font-size:28px;letter-spacing:12px;color:#FFFFFF;font-weight:300;">ATLAS</span>
        <div style="font-size:10px;letter-spacing:3px;color:#44444E;margin-top:4px;text-transform:uppercase;">by InterLinked©</div>
      </td></tr>
      <!-- Card -->
      <tr><td style="background:#0E0E10;border-radius:16px;border:1px solid rgba(255,255,255,0.07);overflow:hidden;">
        ${body}
      </td></tr>
      <!-- Footer -->
      <tr><td align="center" style="padding-top:28px;">
        <div style="font-size:10px;color:#252845;letter-spacing:1px;">
          © InterLinked. All rights reserved.<br>
          <a href="https://www.interlinked.digital/atlas/account" style="color:#44444E;">Manage account</a>
          &nbsp;·&nbsp;
          <a href="https://www.interlinked.digital" style="color:#44444E;">interlinked.digital</a>
        </div>
      </td></tr>
    </table>
  </td></tr>
</table>
</body></html>`
}

function section(content: string) {
  return `<div style="padding:28px 32px;">${content}</div>`
}

function tealBtn(text: string, url: string) {
  return `<a href="${url}" style="display:inline-block;padding:12px 28px;background:linear-gradient(135deg,#3ECFB2,#2ABEAA);color:#07080F;font-size:13px;font-weight:700;text-decoration:none;border-radius:10px;letter-spacing:-0.01em;margin-top:20px;">${text}</a>`
}

function welcomeEmail(name: string) {
  return base('Welcome to ATLAS', section(`
    <h1 style="margin:0 0 8px;font-size:20px;font-weight:700;color:#FFFFFF;">Welcome, ${name}!</h1>
    <p style="margin:0 0 16px;font-size:14px;color:#8A8A96;line-height:1.6;">
      Your ATLAS account is ready. Download ATLAS for macOS and sign in to start automating your software installations.
    </p>
    <div style="background:#07080F;border-radius:10px;border:1px solid #1E2240;padding:16px;margin:16px 0;">
      <div style="font-size:10px;color:#44444E;letter-spacing:2px;text-transform:uppercase;margin-bottom:8px;">What's included</div>
      <div style="font-size:13px;color:#D0D8F0;line-height:1.8;">
        ✓ One-click software installation<br>
        ✓ Installation history &amp; logs<br>
        ✓ Real-time sync across devices
      </div>
    </div>
    ${tealBtn('Download ATLAS', 'https://www.interlinked.digital/atlas/account')}
    <p style="margin:20px 0 0;font-size:11px;color:#44444E;">
      Already downloaded? Sign in to ATLAS with this email address.
    </p>
  `))
}

function subscriptionConfirmedEmail(plan: string, renewDate: string) {
  return base(`ATLAS ${plan} — Confirmed`, section(`
    <div style="display:inline-block;padding:4px 12px;background:${plan === 'Pro' ? 'rgba(240,160,48,0.1)' : 'rgba(91,141,239,0.1)'};border:1px solid ${plan === 'Pro' ? 'rgba(240,160,48,0.3)' : 'rgba(91,141,239,0.3)'};border-radius:6px;font-size:10px;font-weight:800;letter-spacing:2px;color:${plan === 'Pro' ? '#F0A030' : '#5B8DEF'};margin-bottom:16px;">ATLAS ${plan.toUpperCase()}</div>
    <h1 style="margin:0 0 8px;font-size:20px;font-weight:700;color:#FFFFFF;">Subscription confirmed</h1>
    <p style="margin:0 0 16px;font-size:14px;color:#8A8A96;line-height:1.6;">
      You're now on the <strong style="color:#FFFFFF;">ATLAS ${plan}</strong> plan.
      ${renewDate ? `Your subscription renews on <strong style="color:#FFFFFF;">${renewDate}</strong>.` : ''}
    </p>
    ${tealBtn('View Account', 'https://www.interlinked.digital/atlas/account')}
  `))
}

function subscriptionCancelledEmail(endDate: string) {
  return base('ATLAS Subscription Cancelled', section(`
    <h1 style="margin:0 0 8px;font-size:20px;font-weight:700;color:#FFFFFF;">Subscription cancelled</h1>
    <p style="margin:0 0 16px;font-size:14px;color:#8A8A96;line-height:1.6;">
      Your ATLAS subscription has been cancelled.
      ${endDate ? `You'll continue to have access until <strong style="color:#FFFFFF;">${endDate}</strong>.` : ''}
    </p>
    <p style="font-size:14px;color:#8A8A96;">Changed your mind? You can re-subscribe at any time.</p>
    <a href="https://www.interlinked.digital/atlas" style="display:inline-block;padding:12px 28px;background:rgba(62,207,178,0.1);border:1px solid rgba(62,207,178,0.3);color:#3ECFB2;font-size:13px;font-weight:600;text-decoration:none;border-radius:10px;margin-top:20px;">Re-subscribe</a>
  `))
}

function paymentFailedEmail() {
  return base('ATLAS — Payment Failed', section(`
    <h1 style="margin:0 0 8px;font-size:20px;font-weight:700;color:#FFFFFF;">Payment failed</h1>
    <p style="margin:0 0 16px;font-size:14px;color:#8A8A96;line-height:1.6;">
      We couldn't process your last payment for ATLAS. Please update your payment method to keep your subscription active.
    </p>
    ${tealBtn('Update Payment Method', 'https://www.interlinked.digital/atlas/account')}
  `))
}
