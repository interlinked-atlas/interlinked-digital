import type { Metadata } from 'next'

export const metadata: Metadata = {
  title: 'ATLAS — Join the Waitlist',
  description: 'The World\'s First Autonomous Installation App. Sign up to be notified when ATLAS launches.',
  openGraph: {
    title: 'Join the Waitlist for ATLAS.',
    description: 'The World\'s First Autonomous Installation App.',
    url: 'https://www.interlinked.digital/atlas',
    siteName: 'ATLAS by InterLinked',
  },
  twitter: {
    card: 'summary',
    title: 'Join the Waitlist for ATLAS.',
    description: 'The World\'s First Autonomous Installation App.',
  },
}

export default function ATLASLayout({ children }: { children: React.ReactNode }) {
  return <>{children}</>
}
