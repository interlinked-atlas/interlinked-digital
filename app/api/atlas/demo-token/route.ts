import { NextRequest, NextResponse } from 'next/server'
import { createHmac, timingSafeEqual } from 'crypto'

const TOKEN_TTL_MS = 7 * 24 * 60 * 60 * 1000 // 7 days

function secret() {
  return process.env.SUPABASE_SERVICE_ROLE_KEY!
}

export function generateDemoToken(email: string): string {
  const payload = Buffer.from(JSON.stringify({ email, exp: Date.now() + TOKEN_TTL_MS })).toString('base64url')
  const sig = createHmac('sha256', secret()).update(payload).digest('hex')
  return `${payload}.${sig}`
}

export async function GET(req: NextRequest) {
  const token = req.nextUrl.searchParams.get('token')
  if (!token) return NextResponse.json({ valid: false })

  const dotIdx = token.lastIndexOf('.')
  if (dotIdx === -1) return NextResponse.json({ valid: false })

  const payload = token.slice(0, dotIdx)
  const sig     = token.slice(dotIdx + 1)

  // Verify signature
  const expected = createHmac('sha256', secret()).update(payload).digest('hex')
  if (expected.length !== sig.length) return NextResponse.json({ valid: false })
  if (!timingSafeEqual(Buffer.from(expected), Buffer.from(sig))) {
    return NextResponse.json({ valid: false })
  }

  // Check expiry
  try {
    const { exp } = JSON.parse(Buffer.from(payload, 'base64url').toString())
    if (Date.now() > exp) return NextResponse.json({ valid: false, error: 'expired' })
  } catch {
    return NextResponse.json({ valid: false })
  }

  return NextResponse.json({ valid: true })
}
