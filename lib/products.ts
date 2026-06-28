export interface Product {
  id: string
  name: string
  description: string
  priceInCents: number
  interval: 'month' | 'year'
  features: string[]
  limitations?: string[]
  popular?: boolean
}

// Live Stripe price IDs — must match PRICE_PLAN in webhooks/stripe/route.ts
export const PRICE_IDS = {
  standard: 'price_1TdIbOA1Bm2dPCGcBzQIiXGV',
  pro:      'price_1TdIbOA1Bm2dPCGcpLFkuAea',
} as const

export const PRODUCTS: Product[] = [
  {
    id: 'atlas-standard',
    name: 'ATLAS Standard',
    description: 'Everything you need to automate your software installations.',
    priceInCents: 1499, // $14.99
    interval: 'month',
    features: [
      'One-click software installation',
      'Up to 3 installs per day',
      'Installation history (last 5)',
      'Real-time account sync',
      'Notifications & alerts',
      'Single device',
    ],
  },
  {
    id: 'atlas-pro',
    name: 'ATLAS Pro',
    description: 'Built for professional producers, engineers, studios, and advanced workflows.',
    priceInCents: 2999, // $29.99
    interval: 'month',
    features: [
      'Everything in Standard',
      'Unlimited installs',
      'Bulk queue installation',
      'TITAN CORE™ smart installer',
      'Smart Storage management',
      'Virus Scanner (VirusTotal)',
      'Uninstall & Rollback',
      'Up to 3 devices',
      'Full installation history',
    ],
    popular: true,
  },
]
