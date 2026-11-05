import 'server-only'
import { createClient } from '@supabase/supabase-js'

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
)

/**
 * Fail-open: if the check itself errors (DB hiccup), the request is
 * allowed through rather than blocked, so an infra issue never locks
 * legitimate users out of login/signup.
 */
export async function checkRateLimit(
  key: string,
  route: string,
  max: number,
  windowSeconds: number
): Promise<boolean> {
  const { data, error } = await supabase.rpc('check_rate_limit', {
    p_key: key,
    p_route: route,
    p_max: max,
    p_window_seconds: windowSeconds,
  })

  if (error) {
    console.error(`[ATLAS] checkRateLimit failed for ${route}:`, error.message)
    return true
  }
  return data === true
}

export function getClientIp(req: Request): string {
  return req.headers.get('x-forwarded-for')?.split(',')[0]?.trim() ?? 'unknown'
}
