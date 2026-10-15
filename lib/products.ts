export interface Product {
  id: string
  name: string
  description: string
  priceInCents: number
  interval: 'month' | 'year'
  features: string[]
  popular?: boolean
}

// Live Stripe price IDs — must match PRICE_PLAN in webhooks/stripe/route.ts
export const PRICE_IDS = {
  // Current ATLAS plan — $30/month only, no annual option
  'atlas':        'price_1U9uOBA1Bm2dPCGc73d3ZbA5',
  // Legacy prices retained for backward-compat webhook processing
  'standard':           'price_1TdIbOA1Bm2dPCGcBzQIiXGV',
  'pro':                'price_1TdIbOA1Bm2dPCGcpLFkuAea',
  'standard-annual':    'price_1TnTWwA1Bm2dPCGchzhfeeZy',
  'pro-annual':         'price_1TnTXWA1Bm2dPCGcPInuLsUt',
} as const

export const PRODUCTS: Product[] = [
  {
    id: 'atlas',
    name: 'ATLAS',
    description: 'The complete ATLAS subscription, billed monthly.',
    priceInCents: 3000,
    interval: 'month',
    features: [
      'One-click software installation',
      'Bulk queue installation',
      'TITAN CORE™ smart installer',
      'TITAN MEMORY™ pattern learning',
      'Smart Storage management',
      'Virus Scanner (VirusTotal)',
      'Uninstall & Rollback',
      'ATLAS CLEANER™',
      'Recovery Kit & Recovery Mode',
      'Full installation history',
      'Up to 3 devices',
      '25 installs/month',
      'Notifications & alerts',
    ],
    popular: true,
  },
]
