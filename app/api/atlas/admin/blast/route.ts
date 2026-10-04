import { NextRequest, NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'
import { sendEmail } from '@/lib/email'

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
)

// POST /api/atlas/admin/blast
// Body: { secret: string, template: 'launch' | ..., dryRun?: boolean }
// Requires ATLAS_ADMIN_SECRET env var to match.
// dryRun=true returns email list without sending.
export async function POST(req: NextRequest) {
  const { secret, template = 'launch', dryRun = false } = await req.json()

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

  const emails = (rows ?? []).map((r: { email: string }) => r.email).filter(Boolean)

  if (dryRun) {
    return NextResponse.json({ count: emails.length, emails, dryRun: true })
  }

  // Send in batches of 10 to avoid rate-limiting Resend
  const BATCH = 10
  let sent = 0
  const failed: string[] = []

  for (let i = 0; i < emails.length; i += BATCH) {
    const batch = emails.slice(i, i + BATCH)
    await Promise.allSettled(
      batch.map(async (email) => {
        const { error: sendErr } = await sendEmail({ to: email, template })
        if (sendErr) {
          failed.push(email)
        } else {
          sent++
        }
      })
    )
    // Brief pause between batches to respect Resend rate limits
    if (i + BATCH < emails.length) {
      await new Promise(r => setTimeout(r, 300))
    }
  }

  return NextResponse.json({
    total: emails.length,
    sent,
    failed: failed.length,
    failedEmails: failed,
  })
}
