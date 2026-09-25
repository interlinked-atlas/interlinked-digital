import 'server-only'
import { createClient } from '@supabase/supabase-js'

/**
 * Sole ATLAS entitlement authority: subscriptions.status = 'active' for the
 * given user. profiles.plan is NEVER an entitlement signal — it is display
 * metadata only. Every route that needs to answer "is this user allowed to
 * use paid ATLAS functionality" must go through this helper, not re-derive
 * its own plan-string check.
 */
export async function hasActiveAtlasSubscription(
  supabaseAdmin: ReturnType<typeof createClient>,
  userId: string
): Promise<boolean> {
  const { data, error } = await supabaseAdmin
    .from('subscriptions')
    .select('status')
    .eq('user_id', userId)
    .eq('status', 'active')
    .maybeSingle()

  if (error) {
    // Fail closed: an inability to verify entitlement is never entitlement.
    console.error('[ATLAS] hasActiveAtlasSubscription query failed:', error.message)
    return false
  }
  return !!data
}
