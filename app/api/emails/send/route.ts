import { NextRequest, NextResponse } from 'next/server'
import { sendEmail } from '@/lib/email'

export async function POST(req: NextRequest) {
  const secret = req.headers.get('x-internal-secret')
  if (secret !== process.env.INTERNAL_API_SECRET) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  }

  const { to, template, data } = await req.json()
  if (!to || !template) return NextResponse.json({ error: 'Missing to or template' }, { status: 400 })

  const { error } = await sendEmail({ to, template, data })
  if (error) return NextResponse.json({ error: 'Send failed', detail: String(error) }, { status: 500 })
  return NextResponse.json({ success: true })
}
