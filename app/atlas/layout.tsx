import type { Metadata } from 'next'

export const metadata: Metadata = {
  title: 'ATLAS — Join the Waitlist ✧ View Demo',
  description: 'The World\'s First Autonomous Installation App. Join the waitlist and watch the demo.',
  openGraph: {
    title: 'Join the Waitlist ✧ View Demo',
    description: 'The World\'s First Autonomous Installation App.',
    url: 'https://www.interlinked.digital/atlas',
    siteName: 'ATLAS by InterLinked',
  },
  twitter: {
    card: 'summary',
    title: 'Join the Waitlist ✧ View Demo',
    description: 'The World\'s First Autonomous Installation App.',
  },
}

export default function ATLASLayout({ children }: { children: React.ReactNode }) {
  return <>{children}</>
}
