import { NextResponse } from 'next/server'

// Disabled 2026-10-19: this route sold the obsolete standard/pro price tiers
// ($14.99/$29.99), bypassing lib/products.ts's current single-$30-plan
// allowlist. Its only caller anywhere in the repo was the dormant,
// unrouted app/atlas/_page-launch.tsx. Kept as a safe stub (not deleted)
// so it's available to be re-pointed at the current allowlisted checkout
// mechanism (app/actions/stripe.ts) when the real launch flow is built.
export async function POST() {
  return NextResponse.json(
    { error: 'This checkout endpoint is no longer active.' },
    { status: 410 }
  )
}
