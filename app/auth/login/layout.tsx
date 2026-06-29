import type { Metadata } from 'next'

export const metadata: Metadata = {
  title: 'ATLAS - Account',
  description: 'Sign in to your ATLAS account.',
}

export default function LoginLayout({ children }: { children: React.ReactNode }) {
  return <>{children}</>
}
