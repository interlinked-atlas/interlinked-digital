// Pure decision logic extracted from app/atlas/checkout/success/page.tsx's
// post-checkout polling loop, so the "has the webhook landed yet" decision
// can be unit-tested without a real Supabase client or timers. This does
// NOT grant entitlement — it only decides whether the success page should
// keep waiting, declare the subscription active, or give up and move on
// (still never claiming access itself; the account page's own Realtime
// subscription on `subscriptions` remains the actual source of truth).

export type PollOutcome = 'active' | 'retry' | 'give_up'

export function nextPollOutcome(
  subscriptionStatus: string | null | undefined,
  attempt: number,
  maxAttempts: number
): PollOutcome {
  if (subscriptionStatus === 'active') return 'active'
  if (attempt + 1 >= maxAttempts) return 'give_up'
  return 'retry'
}
