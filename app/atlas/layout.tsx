import type { Metadata } from 'next'

export const metadata: Metadata = {
  title: 'ATLAS by InterLinked',
  description: 'The World\'s First Autonomous Installation App. Subscribe now.',
  openGraph: {
    title: 'ATLAS by InterLinked',
    description: 'The World\'s First Autonomous Installation App.',
    url: 'https://www.interlinked.digital/atlas',
    siteName: 'ATLAS by InterLinked',
  },
  twitter: {
    card: 'summary',
    title: 'ATLAS by InterLinked',
    description: 'The World\'s First Autonomous Installation App.',
  },
}

export default function ATLASLayout({ children }: { children: React.ReactNode }) {
  return <>{children}</>
}
