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
  standard:        'price_1TdIbOA1Bm2dPCGcBzQIiXGV',
  pro:             'price_1TdIbOA1Bm2dPCGcpLFkuAea',
  'standard-annual': 'price_1TnTWwA1Bm2dPCGchzhfeeZy',
  'pro-annual':      'price_1TnTXWA1Bm2dPCGcPInuLsUt',
} as const

export const PRODUCTS: Product[] = [
  {
    id: 'atlas-standard-annual',
    name: 'ATLAS Standard — Annual',
    description: 'Standard plan billed annually. Save $30.',
    priceInCents: 15000,
    interval: 'year',
    features: [],
  },
  {
    id: 'atlas-pro-annual',
    name: 'ATLAS Pro — Annual',
    description: 'Pro plan billed annually. Save $60.',
    priceInCents: 30000,
    interval: 'year',
    features: [],
    popular: true,
  },
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
