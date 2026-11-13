import { NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'

// Public, unauthenticated — the app checks this before showing ATLAS
// Browser. Same reasoning as app/api/atlas/catalog/route.ts: no per-user
// data involved.
const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
)

export async function GET() {
  const { data, error } = await supabase
    .from('atlas_settings')
    .select('value')
    .eq('key', 'browser_maintenance')
    .maybeSingle()

  if (error) return NextResponse.json({ error: error.message }, { status: 500 })
  return NextResponse.json({ maintenance: data?.value === 'true' })
}
