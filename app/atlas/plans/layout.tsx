import type { Metadata } from 'next'

export const metadata: Metadata = {
  title: 'ATLAS - Plans',
  description: 'ATLAS — one plan, everything included. $30/month or $300/year.',
}

export default function PlansLayout({ children }: { children: React.ReactNode }) {
  return <>{children}</>
}
