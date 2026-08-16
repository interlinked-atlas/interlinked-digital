import { NextRequest, NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
)

// Returns short-lived signed URLs for the two encrypted blobs — for use by the Mac app.
// The Mac app downloads and decrypts client-side using the DEK from /key.
// For browser downloads (website), use /download instead (server-side decrypt).
export async function GET(req: NextRequest) {
  const token = req.headers.get('authorization')?.replace('Bearer ', '')
  if (!token) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

  const { data: { user }, error: authErr } = await supabase.auth.getUser(token)
  if (authErr || !user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

  const { data: profile } = await supabase
    .from('profiles')
    .select('plan')
    .eq('id', user.id)
    .single()
  if (profile?.plan !== 'pro') {
    return NextResponse.json({ error: 'Cloud Recovery Kit requires ATLAS Pro' }, { status: 403 })
  }

  const kitId = req.nextUrl.searchParams.get('kit_id')
  if (!kitId) return NextResponse.json({ error: 'kit_id required' }, { status: 400 })

  // Ownership enforced: row must belong to this authenticated user
  const { data: kitRow, error: kitErr } = await supabase
    .from('recovery_kits')
    .select('atlaskit_path, txt_path')
    .eq('id', kitId)
    .eq('user_id', user.id)
    .eq('is_deleted', false)
    .single()

  if (kitErr || !kitRow) {
    return NextResponse.json({ error: 'Recovery Kit not found' }, { status: 404 })
  }

  const [atlaskitSigned, txtSigned] = await Promise.all([
    supabase.storage.from('atlas-recovery-kits').createSignedUrl(kitRow.atlaskit_path, 3600),
    supabase.storage.from('atlas-recovery-kits').createSignedUrl(kitRow.txt_path, 3600),
  ])

  if (atlaskitSigned.error || !atlaskitSigned.data) {
    return NextResponse.json({ error: 'Could not create atlaskit download URL' }, { status: 500 })
  }
  if (txtSigned.error || !txtSigned.data) {
    return NextResponse.json({ error: 'Could not create txt download URL' }, { status: 500 })
  }

  return NextResponse.json({
    atlaskit_download_url: atlaskitSigned.data.signedUrl,
    txt_download_url:      txtSigned.data.signedUrl,
  })
}
