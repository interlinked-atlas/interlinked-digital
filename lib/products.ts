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

export const PRODUCTS: Product[] = [
  {
    id: 'atlas-basic',
    name: 'ATLAS Basic',
    description: 'Perfect for casual users who need the essential ATLAS experience.',
    priceInCents: 1499, // $14.99
    interval: 'month',
    features: [
      'Standard installations',
      'Core ATLAS workflow tools',
      'Single computer activation',
      'Up to 3 installs daily',
    ],
    limitations: [
      'Bulk queue installs disabled',
      'Uninstall Manager unavailable',
      'Recovery System unavailable',
    ],
  },
  {
    id: 'atlas-pro',
    name: 'ATLAS Pro',
    description: 'Built for professional producers, engineers, studios, and advanced workflows.',
    priceInCents: 2999, // $29.99
    interval: 'month',
    features: [
      'Everything in Basic',
      'Unlimited installations',
      'Bulk queue installation support',
      'Smart Uninstall Manager',
      'Recovery System',
      'Up to 3 computer activations',
      'Faster workflow management',
      'Future updates included',
    ],
    popular: true,
  },
]
