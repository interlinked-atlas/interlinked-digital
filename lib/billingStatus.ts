// Stripe's own subscription status enum uses American spelling ('canceled'),
// but ATLAS's webhook handlers (handleCancellation/revokeAccessForCustomer in
// app/api/webhooks/stripe/route.ts) write British spelling ('cancelled') to
// profiles.subscription_status. upsertSubscription() previously wrote
// whichever spelling Stripe's raw status string happened to be, so a
// cancellation guard checking only one spelling could miss an
// already-cancelled account and re-run the cancellation (duplicate email,
// duplicate audit-log row). This is the single source of truth for that
// comparison so it can't drift between call sites again.
export function isAlreadyCancelledStatus(status: string | null | undefined): boolean {
  return status === 'cancelled' || status === 'canceled'
}

export interface EffectiveEntitlement {
  profileStatus: string
  subStatus: string
}

// ATLAS policy (2026-10-23): cancel_at_period_end === true revokes ATLAS
// access immediately — Stripe's own `status` stays 'active' throughout that
// window (Stripe only flips status at period end or on an actual delete), so
// entitlement must be computed from BOTH fields together, not status alone.
// This is a pure function of the CURRENT event's own fields: a later event
// reporting cancelAtPeriodEnd === false (the customer reversed the
// cancellation) naturally recomputes 'active' again with no separate
// reversal branch and no risk of a reversal leaving access permanently
// revoked.
export function computeEffectiveEntitlement(
  status: string,
  cancelAtPeriodEnd: boolean
): EffectiveEntitlement {
  const effectivelyCancelled = cancelAtPeriodEnd || status === 'canceled'
  if (effectivelyCancelled) {
    return { profileStatus: 'cancelled', subStatus: 'canceled' }
  }
  if (status === 'active') {
    return { profileStatus: 'active', subStatus: 'active' }
  }
  if (status === 'past_due') {
    return { profileStatus: 'past_due', subStatus: 'past_due' }
  }
  return { profileStatus: status, subStatus: 'incomplete' }
}
