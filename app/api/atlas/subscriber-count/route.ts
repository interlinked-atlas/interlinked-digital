import { NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
)

// Display offset — only you and I know this
const DISPLAY_OFFSET = 1000
const DAILY_INCREMENT = 4
const START_DATE = new Date('2026-07-12T00:00:00Z')

export async function GET() {
  const { count } = await supabase
    .from('atlas_waitlist')
    .select('*', { count: 'exact', head: true })

  const real = count ?? 0
  const daysSinceStart = Math.floor((Date.now() - START_DATE.getTime()) / 86_400_000)
  const display = real + DISPLAY_OFFSET + (daysSinceStart * DAILY_INCREMENT)

  return NextResponse.json({ count: display })
}
