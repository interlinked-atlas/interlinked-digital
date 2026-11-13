import { NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'

// Public, unauthenticated — this is the "ATLAS Browser" catalog the app
// fetches on every platform. No per-user data here, so no auth/entitlement
// check (unlike every /api/atlas/admin/* route). Platform filtering (mac
// vs win) happens client-side in the app, not via a query param, since the
// whole list is only a few hundred rows.
const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
)

export async function GET() {
  const { data, error } = await supabase
    .from('atlas_catalog')
    .select('id, name, brand, category, platform, image_url, external_url, sort_order')
    .order('category', { ascending: true })
    .order('sort_order', { ascending: true })

  if (error) return NextResponse.json({ error: error.message }, { status: 500 })
  return NextResponse.json(data ?? [])
}
