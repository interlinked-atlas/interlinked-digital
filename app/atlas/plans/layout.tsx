import type { Metadata } from 'next'

export const metadata: Metadata = {
  title: 'ATLAS - Plans',
  description: 'Choose your ATLAS plan. Standard or Pro — both powered by TITAN CORE™.',
}

export default function PlansLayout({ children }: { children: React.ReactNode }) {
  return <>{children}</>
}
