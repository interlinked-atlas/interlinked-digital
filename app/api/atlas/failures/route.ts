import { NextRequest, NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'

// ---------------------------------------------------------------------------
// Email helper — uses Resend API (no SDK needed, just fetch)
// Set RESEND_API_KEY in Vercel env vars. Free tier = 3000 emails/month.
// Sign up at resend.com and verify interlinked.digital as your sending domain.
// ---------------------------------------------------------------------------
async function sendFailureEmail(data: {
  id: string
  userEmail: string
  productName: string
  sourceFilename: string
  failureReason: string
  failureStep: string
  failureType: string
  deviceName: string
  macosVersion: string
  installLog: string
}) {
  const key = process.env.RESEND_API_KEY
  if (!key) return // not configured yet — skip silently

  const subject = `⚠ ATLAS Failure: ${data.productName || data.sourceFilename}`

  const html = `
<div style="font-family:monospace;font-size:13px;color:#111;max-width:700px">
  <h2 style="color:#c00;margin-bottom:4px">ATLAS Install Failure</h2>
  <p style="color:#555;margin-top:0">Failure ID: <strong>${data.id}</strong></p>
  <table style="border-collapse:collapse;width:100%;margin-bottom:16px">
    <tr><td style="padding:4px 8px;background:#f5f5f5;width:160px"><strong>User</strong></td><td style="padding:4px 8px">${data.userEmail}</td></tr>
    <tr><td style="padding:4px 8px;background:#f5f5f5"><strong>Product</strong></td><td style="padding:4px 8px">${data.productName}</td></tr>
    <tr><td style="padding:4px 8px;background:#f5f5f5"><strong>File</strong></td><td style="padding:4px 8px">${data.sourceFilename}</td></tr>
    <tr><td style="padding:4px 8px;background:#f5f5f5"><strong>Reason</strong></td><td style="padding:4px 8px;color:#c00">${data.failureReason}</td></tr>
    <tr><td style="padding:4px 8px;background:#f5f5f5"><strong>Step</strong></td><td style="padding:4px 8px">${data.failureStep}</td></tr>
    <tr><td style="padding:4px 8px;background:#f5f5f5"><strong>Type</strong></td><td style="padding:4px 8px">${data.failureType}</td></tr>
    <tr><td style="padding:4px 8px;background:#f5f5f5"><strong>Device</strong></td><td style="padding:4px 8px">${data.deviceName}</td></tr>
    <tr><td style="padding:4px 8px;background:#f5f5f5"><strong>macOS</strong></td><td style="padding:4px 8px">${data.macosVersion}</td></tr>
  </table>
  ${data.installLog ? `
  <h3 style="margin-bottom:4px">Install Log</h3>
  <pre style="background:#1a1a1a;color:#e0e0e0;padding:12px;border-radius:6px;overflow-x:auto;font-size:11px;line-height:1.5;white-space:pre-wrap">${data.installLog.slice(0, 8000)}</pre>
  ` : ''}
  <p style="color:#888;font-size:11px;margin-top:16px">View in admin dashboard → interlinked.digital/atlas/admin</p>
</div>`

  await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${key}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      from: 'ATLAS <noreply@interlinked.digital>',
      to:   ['interlinked.digital@gmail.com'],
      subject,
      html,
    }),
  })
}

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
)

export async function POST(req: NextRequest) {
  const token = req.headers.get('authorization')?.replace('Bearer ', '').trim()
  if (!token) return NextResponse.json({ error: 'Missing authorization' }, { status: 401 })

  const { data: { user }, error: authError } = await supabase.auth.getUser(token)
  if (authError || !user) return NextResponse.json({ error: 'Invalid token' }, { status: 401 })

  let body: Record<string, unknown>
  try { body = await req.json() }
  catch { return NextResponse.json({ error: 'Invalid JSON' }, { status: 400 }) }

  const {
    product_name, source_filename, failure_reason, failure_step,
    failure_type, steps_attempted, error_output, install_log,
    device_name, hardware_uuid, macos_version
  } = body as Record<string, unknown>

  if (!product_name || !source_filename) {
    return NextResponse.json({ error: 'Missing required fields' }, { status: 400 })
  }

  const { data, error } = await supabase.from('install_failures').insert({
    user_id:         user.id,
    product_name:    product_name,
    source_filename: source_filename,
    failure_reason:  failure_reason  ?? null,
    failure_step:    failure_step    ?? null,
    failure_type:    failure_type    ?? 'unknown',
    steps_attempted: steps_attempted ?? [],
    error_output:    error_output    ?? null,
    install_log:     install_log     ?? null,
    device_name:     device_name     ?? null,
    hardware_uuid:   hardware_uuid   ?? null,
    macos_version:   macos_version   ?? null,
  }).select('id').single()

  if (error) {
    console.error('[ATLAS] install_failures insert failed:', error.message)
    return NextResponse.json({ error: 'Failed to record failure' }, { status: 500 })
  }

  // Email developer immediately — fire and forget, never blocks the response
  sendFailureEmail({
    id: data?.id ?? 'unknown',
    userEmail: user.email ?? 'unknown',
    productName:   String(product_name   ?? ''),
    sourceFilename: String(source_filename ?? ''),
    failureReason: String(failure_reason  ?? ''),
    failureStep:   String(failure_step    ?? ''),
    failureType:   String(failure_type    ?? ''),
    deviceName:    String(device_name     ?? ''),
    macosVersion:  String(macos_version   ?? ''),
    installLog:    typeof install_log === 'string' ? install_log : '',
  }).catch(() => {}) // never throw

  return NextResponse.json({ ok: true, id: data?.id })
}
