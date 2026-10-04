import { NextRequest, NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'
import { sendEmail } from '@/lib/email'

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
)

// POST /api/atlas/admin/blast
// Body: { secret: string, template: 'launch' | ..., dryRun?: boolean, exclude?: string[], only?: string[] }
// Requires ATLAS_ADMIN_SECRET env var to match.
// dryRun=true returns email list without sending.
// exclude is an optional explicit list of addresses to drop from the
// atlas_waitlist result before sending/counting — e.g. a known synthetic
// test fixture address that happens to be a real row in the table.
// only is an optional explicit allow-list — when provided, the recipient
// set is the intersection of atlas_waitlist and `only`, i.e. it narrows the
// run to specific addresses (e.g. retrying just the ones that failed a
// previous run) without ever being able to add anyone who isn't already a
// real atlas_waitlist row. exclude/only only ever remove recipients from
// the atlas_waitlist result; they can never add one.
export async function POST(req: NextRequest) {
  const { secret, template = 'launch', dryRun = false, exclude = [], only } = await req.json()

  if (!process.env.ATLAS_ADMIN_SECRET || secret !== process.env.ATLAS_ADMIN_SECRET) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  }

  // Fetch all waitlist emails
  const { data: rows, error } = await supabase
    .from('atlas_waitlist')
    .select('email')
    .order('signed_up_at', { ascending: true })

  if (error) {
    return NextResponse.json({ error: error.message }, { status: 500 })
  }

  const excludeSet = new Set((exclude as string[]).map((e) => e.toLowerCase()))
  const onlySet = only ? new Set((only as string[]).map((e) => e.toLowerCase())) : null
  const emails = (rows ?? [])
    .map((r: { email: string }) => r.email)
    .filter(Boolean)
    .filter((e: string) => !excludeSet.has(e.toLowerCase()))
    .filter((e: string) => !onlySet || onlySet.has(e.toLowerCase()))

  if (dryRun) {
    return NextResponse.json({ count: emails.length, emails, dryRun: true })
  }

  // Send sequentially with a fixed delay between each individual request —
  // Resend's limit is 10 requests/second, and the previous implementation
  // fired up to 10 requests concurrently per batch, which collided with that
  // ceiling and produced 429s. 150ms between sends keeps us well under it
  // (~6.6/sec) without relying on batch-level concurrency at all.
  const DELAY_MS = 150
  let sent = 0
  const failed: string[] = []

  for (let i = 0; i < emails.length; i++) {
    const email = emails[i]
    const { error: sendErr } = await sendEmail({ to: email, template })
    if (sendErr) {
      failed.push(email)
    } else {
      sent++
    }
    if (i + 1 < emails.length) {
      await new Promise(r => setTimeout(r, DELAY_MS))
    }
  }

  return NextResponse.json({
    total: emails.length,
    sent,
    failed: failed.length,
    failedEmails: failed,
  })
}
