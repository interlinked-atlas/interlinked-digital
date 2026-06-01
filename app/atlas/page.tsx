'use client'

import { useState } from 'react'
import Image from 'next/image'
import Link from 'next/link'
import { Check, Download, X, Menu } from 'lucide-react'

export default function AtlasPage() {
  const [isVideoModalOpen, setIsVideoModalOpen] = useState(false)
  const [isMobileMenuOpen, setIsMobileMenuOpen] = useState(false)

  const scrollToSection = (id: string) => {
    const element = document.getElementById(id)
    if (element) {
      element.scrollIntoView({ behavior: 'smooth' })
    }
    setIsMobileMenuOpen(false)
  }

  return (
    <div className="min-h-screen bg-[#0a0a0f] text-white">
      {/* Navigation */}
      <nav className="fixed top-0 left-0 right-0 z-50 bg-[#0a0a0f]/80 backdrop-blur-xl border-b border-white/5">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="flex items-center justify-between h-16">
            <div className="flex items-center gap-2">
              <Image 
                src="/images/atlas-icon.png" 
                alt="ATLAS" 
                width={32} 
                height={32}
                className="w-8 h-8"
              />
              <span className="text-xl font-semibold tracking-wide">ATLAS</span>
            </div>
            
            {/* Desktop Navigation */}
            <div className="hidden md:flex items-center gap-8">
              <button onClick={() => scrollToSection('pricing')} className="text-sm text-white/60 hover:text-white transition-colors">Pricing</button>
              <button onClick={() => scrollToSection('download')} className="text-sm text-white/60 hover:text-white transition-colors">Download</button>
            </div>

            <div className="hidden md:block">
              <Link 
                href="/atlas/signup"
                className="px-4 py-2 bg-gradient-to-r from-[#7c6fee] to-[#4ecdc4] rounded-lg text-sm font-medium hover:opacity-90 transition-opacity"
              >
                Get ATLAS
              </Link>
            </div>

            {/* Mobile Menu Button */}
            <button 
              className="md:hidden p-2"
              onClick={() => setIsMobileMenuOpen(!isMobileMenuOpen)}
            >
              <Menu className="w-6 h-6" />
            </button>
          </div>
        </div>

        {/* Mobile Navigation */}
        {isMobileMenuOpen && (
          <div className="md:hidden bg-[#0d0d1a] border-t border-white/5">
            <div className="px-4 py-4 space-y-4">
              <button onClick={() => scrollToSection('pricing')} className="block w-full text-left text-sm text-white/60 hover:text-white transition-colors">Pricing</button>
              <button onClick={() => scrollToSection('download')} className="block w-full text-left text-sm text-white/60 hover:text-white transition-colors">Download</button>
              <Link 
                href="/atlas/signup"
                className="w-full px-4 py-2 bg-gradient-to-r from-[#7c6fee] to-[#4ecdc4] rounded-lg text-sm font-medium text-center block"
              >
                Get ATLAS
              </Link>
            </div>
          </div>
        )}
      </nav>

      {/* Hero Section */}
      <section className="relative pt-32 pb-20 px-4 sm:px-6 lg:px-8 overflow-hidden">
        {/* Background Effects */}
        <div className="absolute inset-0 bg-gradient-to-b from-[#7c6fee]/10 via-transparent to-transparent" />
        <div className="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 w-[800px] h-[800px] bg-gradient-to-r from-[#7c6fee]/20 to-[#4ecdc4]/20 rounded-full blur-3xl opacity-30" />
        
        <div className="relative max-w-7xl mx-auto">
          <div className="text-center mb-16">
            {/* Logo */}
            <div className="flex justify-center mb-8">
              <Image 
                src="/images/atlas-icon.png" 
                alt="ATLAS Logo" 
                width={120} 
                height={120}
                className="w-24 h-24 md:w-32 md:h-32"
              />
            </div>

            {/* Headline */}
            <h1 className="text-5xl md:text-7xl lg:text-8xl font-bold mb-6 bg-gradient-to-r from-[#7c6fee] to-[#4ecdc4] bg-clip-text text-transparent">
              ATLAS
            </h1>
            
            {/* Placeholder for future content */}
            <div className="mb-10">
              {/* Content will be added here later */}
            </div>
          </div>

          {/* Placeholder for future image */}
          <div className="relative max-w-4xl mx-auto">
            {/* Image will be added here later */}
          </div>
        </div>
      </section>

      {/* Pricing Section */}
      <section id="pricing" className="py-20 px-4 sm:px-6 lg:px-8 bg-[#0d0d1a]">
        <div className="max-w-7xl mx-auto">
          <div className="text-center mb-16">
            <h2 className="text-3xl md:text-4xl font-bold mb-4">ATLAS Subscription Plans</h2>
            <p className="text-white/50 max-w-2xl mx-auto">Choose the plan that works for you</p>
          </div>

          <div className="grid grid-cols-1 md:grid-cols-2 gap-8 max-w-4xl mx-auto">
            {/* Standard Plan */}
            <div className="p-8 bg-[#1a1a2e] rounded-2xl border border-white/10">
              <h3 className="text-2xl font-semibold mb-2">Standard</h3>
              <p className="text-white/50 text-sm mb-4">Perfect for casual users</p>
              <div className="mb-6">
                <span className="text-5xl font-bold">$14.99</span>
                <span className="text-white/50">/month</span>
              </div>
              
              <div className="mb-6">
                <p className="text-xs uppercase tracking-wider text-white/40 mb-3">Included</p>
                <ul className="space-y-3">
                  <li className="flex items-center gap-3 text-white/70">
                    <Check className="w-5 h-5 text-[#4ecdc4] flex-shrink-0" />
                    Standard installations
                  </li>
                  <li className="flex items-center gap-3 text-white/70">
                    <Check className="w-5 h-5 text-[#4ecdc4] flex-shrink-0" />
                    Core ATLAS workflow tools
                  </li>
                  <li className="flex items-center gap-3 text-white/70">
                    <Check className="w-5 h-5 text-[#4ecdc4] flex-shrink-0" />
                    Single computer activation
                  </li>
                  <li className="flex items-center gap-3 text-white/70">
                    <Check className="w-5 h-5 text-[#4ecdc4] flex-shrink-0" />
                    Up to 3 installs daily
                  </li>
                </ul>
              </div>
              
              <div className="mb-8">
                <p className="text-xs uppercase tracking-wider text-white/40 mb-3">Limitations</p>
                <ul className="space-y-2 text-sm text-white/40">
                  <li className="flex items-center gap-2">
                    <X className="w-4 h-4 flex-shrink-0" />
                    Bulk queue installs disabled
                  </li>
                  <li className="flex items-center gap-2">
                    <X className="w-4 h-4 flex-shrink-0" />
                    Uninstall Manager unavailable
                  </li>
                  <li className="flex items-center gap-2">
                    <X className="w-4 h-4 flex-shrink-0" />
                    Recovery System unavailable
                  </li>
                </ul>
              </div>
              
              <Link 
                href="/atlas/signup?plan=atlas-basic"
                className="block w-full py-4 text-center border border-white/20 rounded-xl font-medium hover:bg-white/5 transition-colors"
              >
                Get Standard
              </Link>
            </div>

            {/* Pro Plan */}
            <div className="relative p-8 bg-gradient-to-b from-[#1a1a2e] to-[#0d0d1a] rounded-2xl border border-[#7c6fee]/30 shadow-lg shadow-[#7c6fee]/10">
              <span className="absolute -top-3 left-1/2 -translate-x-1/2 px-4 py-1 bg-gradient-to-r from-[#7c6fee] to-[#4ecdc4] rounded-full text-xs font-medium">Most Popular</span>
              <h3 className="text-2xl font-semibold mb-2">Pro</h3>
              <p className="text-white/50 text-sm mb-4">For professionals and studios</p>
              <div className="mb-6">
                <span className="text-5xl font-bold">$29.99</span>
                <span className="text-white/50">/month</span>
              </div>
              
              <div className="mb-8">
                <p className="text-xs uppercase tracking-wider text-white/40 mb-3">Everything in Standard, plus</p>
                <ul className="space-y-3">
                  <li className="flex items-center gap-3 text-white/70">
                    <Check className="w-5 h-5 text-[#4ecdc4] flex-shrink-0" />
                    Unlimited installations
                  </li>
                  <li className="flex items-center gap-3 text-white/70">
                    <Check className="w-5 h-5 text-[#4ecdc4] flex-shrink-0" />
                    Bulk queue installation support
                  </li>
                  <li className="flex items-center gap-3 text-white/70">
                    <Check className="w-5 h-5 text-[#4ecdc4] flex-shrink-0" />
                    Smart Uninstall Manager
                  </li>
                  <li className="flex items-center gap-3 text-white/70">
                    <Check className="w-5 h-5 text-[#4ecdc4] flex-shrink-0" />
                    Recovery System
                  </li>
                  <li className="flex items-center gap-3 text-white/70">
                    <Check className="w-5 h-5 text-[#4ecdc4] flex-shrink-0" />
                    Up to 3 computer activations
                  </li>
                  <li className="flex items-center gap-3 text-white/70">
                    <Check className="w-5 h-5 text-[#4ecdc4] flex-shrink-0" />
                    Faster workflow management
                  </li>
                  <li className="flex items-center gap-3 text-white/70">
                    <Check className="w-5 h-5 text-[#4ecdc4] flex-shrink-0" />
                    Future updates included
                  </li>
                </ul>
              </div>
              
              <Link 
                href="/atlas/signup?plan=atlas-pro"
                className="block w-full py-4 text-center bg-gradient-to-r from-[#7c6fee] to-[#4ecdc4] rounded-xl font-medium hover:opacity-90 transition-opacity"
              >
                Get Pro
              </Link>
            </div>
          </div>
          
          {/* Enterprise CTA */}
          <div className="mt-12 text-center">
            <p className="text-white/50 mb-4">Need a custom solution for your team or studio?</p>
            <a 
              href="mailto:interlinked.digital@gmail.com"
              className="inline-flex items-center gap-2 text-[#4ecdc4] hover:text-[#7c6fee] transition-colors"
            >
              Contact us for Enterprise pricing
              <svg className="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M17 8l4 4m0 0l-4 4m4-4H3" />
              </svg>
            </a>
          </div>
        </div>
      </section>

      {/* Download Section */}
      <section id="download" className="py-20 px-4 sm:px-6 lg:px-8">
        <div className="max-w-7xl mx-auto">
          <div className="text-center mb-16">
            <h2 className="text-3xl md:text-4xl font-bold mb-4">Download ATLAS</h2>
            <p className="text-white/50 max-w-2xl mx-auto">Get started in seconds</p>
          </div>

          <div className="max-w-md mx-auto">
            <div className="p-8 bg-[#1a1a2e] rounded-2xl border border-white/10 text-center">
              {/* macOS Icon */}
              <div className="inline-flex items-center justify-center w-16 h-16 bg-white/10 rounded-2xl mb-6">
                <svg viewBox="0 0 24 24" className="w-10 h-10 text-white" fill="currentColor">
                  <path d="M18.71 19.5c-.83 1.24-1.71 2.45-3.05 2.47-1.34.03-1.77-.79-3.29-.79-1.53 0-2 .77-3.27.82-1.31.05-2.3-1.32-3.14-2.53C4.25 17 2.94 12.45 4.7 9.39c.87-1.52 2.43-2.48 4.12-2.51 1.28-.02 2.5.87 3.29.87.78 0 2.26-1.07 3.81-.91.65.03 2.47.26 3.64 1.98-.09.06-2.17 1.28-2.15 3.81.03 3.02 2.65 4.03 2.68 4.04-.03.07-.42 1.44-1.38 2.83M13 3.5c.73-.83 1.94-1.46 2.94-1.5.13 1.17-.34 2.35-1.04 3.19-.69.85-1.83 1.51-2.95 1.42-.15-1.15.41-2.35 1.05-3.11z"/>
                </svg>
              </div>
              
              <h3 className="text-xl font-semibold mb-2">ATLAS for macOS</h3>
              <p className="text-white/50 text-sm mb-4">Requires macOS 11.0 or later</p>
              
              <span className="inline-block px-3 py-1 bg-white/10 rounded-full text-xs font-medium mb-6">v1.0.0</span>
              
              <a 
                href="#"
                className="block w-full py-3 bg-gradient-to-r from-[#7c6fee] to-[#4ecdc4] rounded-xl font-medium hover:opacity-90 transition-opacity mb-4"
              >
                <Download className="w-5 h-5 inline-block mr-2" />
                Download for macOS
              </a>
              
              <p className="text-white/40 text-xs">
                Already have a license? Download and enter your key to activate.
              </p>
            </div>
          </div>
        </div>
      </section>

      {/* Footer */}
      <footer className="py-12 px-4 sm:px-6 lg:px-8 border-t border-white/5">
        <div className="max-w-7xl mx-auto">
          <div className="flex flex-col md:flex-row items-center justify-between gap-8">
            <div className="flex items-center gap-2">
              <Image 
                src="/images/atlas-icon.png" 
                alt="ATLAS" 
                width={24} 
                height={24}
                className="w-6 h-6"
              />
              <span className="text-lg font-semibold">ATLAS</span>
            </div>
            
            <div className="flex flex-wrap items-center justify-center gap-6 text-sm text-white/50">
              <button onClick={() => scrollToSection('hero')} className="hover:text-white transition-colors">Home</button>
              <button onClick={() => scrollToSection('pricing')} className="hover:text-white transition-colors">Pricing</button>
              <button onClick={() => scrollToSection('download')} className="hover:text-white transition-colors">Download</button>
              <a href="mailto:atlas.bytitan@gmail.com" className="hover:text-white transition-colors">Contact</a>
            </div>
            
            <div className="flex items-center gap-6 text-sm text-white/50">
              <a href="#" className="hover:text-white transition-colors">Terms</a>
              <a href="#" className="hover:text-white transition-colors">Privacy</a>
            </div>
          </div>
          
          <div className="mt-8 pt-8 border-t border-white/5 text-center text-sm text-white/40">
            <p>&copy; 2025 InterLinked. All rights reserved.</p>
          </div>
        </div>
      </footer>

      {/* Video Modal */}
      {isVideoModalOpen && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/80 backdrop-blur-sm p-4">
          <div className="relative w-full max-w-4xl bg-[#1a1a2e] rounded-2xl overflow-hidden">
            <button 
              onClick={() => setIsVideoModalOpen(false)}
              className="absolute top-4 right-4 z-10 p-2 bg-black/50 rounded-full hover:bg-black/70 transition-colors"
            >
              <X className="w-5 h-5" />
            </button>
            <div className="aspect-video bg-[#0a0a0f] flex items-center justify-center">
              <p className="text-white/50">Demo video placeholder</p>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}
