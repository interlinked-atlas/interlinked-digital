import { NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
)

// Display offset — frozen as of 2026-11-02. No longer auto-increments;
// only real atlas_waitlist signups move this number from here on.
const FROZEN_OFFSET = 1452

export async function GET() {
  const { count } = await supabase
    .from('atlas_waitlist')
    .select('*', { count: 'exact', head: true })

  const real = count ?? 0
  const display = real + FROZEN_OFFSET

  return NextResponse.json({ count: display })
}
