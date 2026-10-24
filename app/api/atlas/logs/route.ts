import { NextRequest, NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'
import { buildInstallLogRow, decideWritePath } from '@/lib/installLogIdempotency'

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
)

// Hard ceilings — generous enough for real install logs, small enough to block abuse.
const MAX_CONTENT_LENGTH  = 200_000   // ~200 KB of log text
const MAX_FIELD_LENGTH    = 500       // filename / app_name / device_name / log_type
const MAX_BODY_BYTES      = 1_000_000 // overall JSON body ceiling, checked before parsing
// Matches every literal logType the Mac app actually sends (Core/InstallLogger.swift,
// Sources/ATLAS/ContentView.swift, UI/InstallFeedbackPrompt.swift, Engine/TitanMemory.swift).
const ALLOWED_LOG_TYPES = new Set([
  'install', 'uninstall', 'failed', 'crashed', 'confirmed-success',
  'install-failure-guided', 'install-failure-feedback',
  'install-demo', 'install-activation', 'install-warning',
])

// Redact values that look like secrets before they're ever written to the database.
// Intentionally broad patterns — false positives just mean an extra [REDACTED], which
// is an acceptable tradeoff for a diagnostic log that may contain copy-pasted output.
const REDACTION_PATTERNS: RegExp[] = [
  /Bearer\s+[A-Za-z0-9\-_.]{10,}/gi,                         // Authorization: Bearer <token>
  /sbp_[A-Za-z0-9]{10,}/g,                                   // Supabase personal access tokens
  /sb_(publishable|secret)_[A-Za-z0-9_\-]{10,}/g,            // Supabase project API keys
  /eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}/g, // JWTs
  /ghp_[A-Za-z0-9]{20,}/g,                                   // GitHub personal access tokens
  /sk_(live|test)_[A-Za-z0-9]{10,}/g,                        // Stripe secret keys
  /(password|passwd|pwd)\s*[:=]\s*\S+/gi,                    // password: ...
  /(api[_-]?key|access[_-]?token|secret)\s*[:=]\s*\S+/gi,    // api_key: ... / secret=...
]

// Replaces "/Users/<name>" with "/Users/[user]" wherever it appears inside log text —
// same intent as Core/RecoveryKit.swift's sanitizedHomePath, but for free-form log
// content rather than a single structured field. Only the account-name segment is
// replaced; everything after it (the actual diagnostic path) is preserved, so this
// does not destroy recovery-relevant information.
const HOME_PATH_PATTERN = /\/Users\/[^/\s]+/g

function redact(text: string): string {
  let out = text.replace(HOME_PATH_PATTERN, '/Users/[user]')
  for (const pattern of REDACTION_PATTERNS) {
    out = out.replace(pattern, '[REDACTED]')
  }
  return out
}

function isNonEmptyString(v: unknown): v is string {
  return typeof v === 'string' && v.length > 0
}

export async function POST(req: NextRequest) {
  const token = req.headers.get('authorization')?.replace('Bearer ', '').trim()
  if (!token) {
    return NextResponse.json({ error: 'Missing authorization' }, { status: 401 })
  }

  const { data: { user }, error: authError } = await supabase.auth.getUser(token)
  if (authError || !user) {
    return NextResponse.json({ error: 'Invalid token' }, { status: 401 })
  }

  // Reject oversized bodies before attempting to parse them.
  const contentLengthHeader = req.headers.get('content-length')
  if (contentLengthHeader && Number(contentLengthHeader) > MAX_BODY_BYTES) {
    return NextResponse.json({ error: 'Request body too large' }, { status: 413 })
  }

  let rawBody: unknown
  try {
    const text = await req.text()
    if (text.length > MAX_BODY_BYTES) {
      return NextResponse.json({ error: 'Request body too large' }, { status: 413 })
    }
    rawBody = JSON.parse(text)
  } catch {
    // Do not log the raw payload on a parse failure — it may be malformed/oversized/garbage.
    return NextResponse.json({ error: 'Invalid JSON body' }, { status: 400 })
  }

  if (typeof rawBody !== 'object' || rawBody === null) {
    return NextResponse.json({ error: 'Invalid request body' }, { status: 400 })
  }
  const body = rawBody as Record<string, unknown>

  const { log_type, app_name, filename, content, device_name, hardware_uuid, client_log_id } = body

  if (!isNonEmptyString(log_type) || !isNonEmptyString(filename) || !isNonEmptyString(content)) {
    return NextResponse.json({ error: 'Missing or invalid required fields' }, { status: 400 })
  }
  if (!ALLOWED_LOG_TYPES.has(log_type)) {
    return NextResponse.json({ error: 'Invalid log_type' }, { status: 400 })
  }
  if (content.length > MAX_CONTENT_LENGTH) {
    return NextResponse.json({ error: 'Log content exceeds maximum size' }, { status: 413 })
  }
  for (const [name, value] of Object.entries({ filename, app_name, device_name })) {
    if (value !== undefined && (typeof value !== 'string' || value.length > MAX_FIELD_LENGTH)) {
      return NextResponse.json({ error: `Invalid ${name}` }, { status: 400 })
    }
  }
  if (hardware_uuid !== undefined && typeof hardware_uuid !== 'string') {
    return NextResponse.json({ error: 'Invalid hardware_uuid' }, { status: 400 })
  }
  if (client_log_id !== undefined && (typeof client_log_id !== 'string' || client_log_id.length > MAX_FIELD_LENGTH)) {
    return NextResponse.json({ error: 'Invalid client_log_id' }, { status: 400 })
  }

  const row = {
    ...buildInstallLogRow({
      userId: user.id, // derived from the verified token — never from client-supplied data
      appName: app_name as string | undefined,
      filename,
      logType: log_type,
      redactedContent: redact(content),
      deviceName: device_name as string | undefined,
      hardwareUuid: hardware_uuid as string | undefined,
      clientLogId: client_log_id as string | undefined,
    }),
    installed_at: new Date().toISOString(),
  }

  // client_log_id is only sent for the log types that have a stable,
  // globally-unique on-disk filename (see the migration's comment for why
  // the others must never be deduped this way). Only those use the
  // idempotent upsert path — everything else keeps the exact prior insert
  // behavior, unchanged.
  //
  // NOTE: this upsert path requires migration
  // 20261022010000_install_logs_client_log_id.sql to be applied first (the
  // client_log_id column and its partial unique index). It is unreachable
  // today because the Mac app does not yet send client_log_id — dormant
  // until both that migration and the corresponding Mac app update ship
  // together, per instruction not to apply this migration or depend on it
  // in production before a separately authorized release step.
  const { error: insertError } = decideWritePath(client_log_id as string | undefined) === 'idempotent_upsert'
    ? await supabase.from('install_logs').upsert(row, {
        onConflict: 'user_id,client_log_id',
        ignoreDuplicates: true,
      })
    : await supabase.from('install_logs').insert(row)

  if (insertError) {
    // Log only the error message, never the payload — avoids re-leaking unredacted content on failure.
    console.error('[ATLAS] install_logs insert failed:', insertError.message)
    return NextResponse.json({ error: 'Failed to save log' }, { status: 500 })
  }

  return NextResponse.json({ ok: true })
}
