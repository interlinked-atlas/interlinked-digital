// ONE-TIME TEST — sends the release template from lib/email.ts
// to a single hardcoded address only.
// Does NOT query atlas_waitlist. Does NOT call any blast endpoint. Does NOT loop.
import { config } from 'dotenv'
config({ path: '.env.local' })

const TO = 'titantinstaller@gmail.com' // hardcoded — no list, no loop

async function main() {
  const { sendEmail } = await import('./lib/email')

  console.log('SAFETY CHECK — recipient:', TO)
  console.log('Template: release (from lib/email.ts)')
  console.log('Sending...')

  const { result, error } = await sendEmail({ to: TO, template: 'release' })

  if (error) {
    console.error('SEND FAILED:', error)
    process.exit(1)
  }

  console.log('SENT:', result)
}

main()
