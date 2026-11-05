import { NextRequest, NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'
import { sendEmail } from '@/lib/email'

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
)

const ADMIN_EMAIL = 'titantinstaller@gmail.com'

async function notifyAdmin(subject: string, body: string) {
  await sendEmail({ to: 'interlinked.digital@gmail.com', template: 'admin-notification', data: { subject, body } })
}

// Admin-only, irreversible account deletion. Requires user_id + matching
// email + an explicit confirm:true flag — three independently-correct
// inputs required before anything destructive happens. Cleans up Storage
// objects (not reachable by DB cascade) before deleting the auth user;
// every other table cascades via ON DELETE CASCADE back to auth.users.
export async function POST(req: NextRequest) {
  const token = req.headers.get('authorization')?.replace('Bearer ', '').trim()
  if (!token) return NextResponse.json({ error: 'Missing authorization' }, { status: 401 })

  const { data: { user: adminUser }, error: authError } = await supabase.auth.getUser(token)
  if (authError || !adminUser) return NextResponse.json({ error: 'Invalid token' }, { status: 401 })
  if (adminUser.email?.toLowerCase() !== ADMIN_EMAIL.toLowerCase())
    return NextResponse.json({ error: 'Forbidden' }, { status: 403 })

  const body = await req.json().catch(() => ({}))
  const { user_id, email, confirm } = body
  if (!user_id || !email) return NextResponse.json({ error: 'user_id and email both required' }, { status: 400 })
  if (confirm !== true) return NextResponse.json({ error: 'confirm:true required' }, { status: 400 })

  // Double-confirmation: target profile must exist and its email must match exactly
  const { data: profile } = await supabase
    .from('profiles')
    .select('id, email')
    .eq('id', user_id)
    .single()

  if (!profile || profile.email?.toLowerCase() !== String(email).toLowerCase()) {
    return NextResponse.json({ error: 'user_id/email mismatch — refusing to delete' }, { status: 400 })
  }

  const { data: kits } = await supabase
    .from('recovery_kits')
    .select('atlaskit_path, txt_path')
    .eq('user_id', user_id)

  await notifyAdmin(
    `⚠️ Account deletion requested — ${profile.email}`,
    `Admin-initiated account deletion starting.\n\nUser ID: ${user_id}\nEmail: ${profile.email}\nRecovery kits to clean: ${kits?.length ?? 0}\nTime: ${new Date().toUTCString()}`
  )

  if (kits?.length) {
    const paths = kits.flatMap(k => [k.atlaskit_path, k.txt_path]).filter(Boolean)
    const { error: storageErr } = await supabase.storage.from('atlas-recovery-kits').remove(paths)
    if (storageErr) console.error('[ATLAS] Storage cleanup failed during account deletion:', storageErr.message)
  }

  const { error: deleteErr } = await supabase.auth.admin.deleteUser(user_id)
  if (deleteErr) {
    await notifyAdmin(`❌ Account deletion FAILED — ${profile.email}`, deleteErr.message)
    return NextResponse.json({ error: deleteErr.message }, { status: 500 })
  }

  await notifyAdmin(`✅ Account deleted — ${profile.email}`, `User ID: ${user_id}\nAll DB rows cascaded, storage objects removed.`)
  return NextResponse.json({ ok: true })
}
