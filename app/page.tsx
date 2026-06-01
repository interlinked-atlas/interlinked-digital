"use client"

import { useState } from "react"
import { ProductCard } from "@/components/product-card"
import { LiquidMetalText } from "@/components/liquid-metal-text"
import { SplashScreen } from "@/components/splash-screen"
import { ProductCarousel } from "@/components/product-carousel"

const products = [
  {
    name: "ATLAS®",
    status: "Now Available",
    isActive: true,
    iconSrc: "/images/atlas-icon.png"
  }
]

export default function Home() {
  const [showSplash, setShowSplash] = useState(true)
  const [showContent, setShowContent] = useState(false)
  const [carouselOpen, setCarouselOpen] = useState(false)

  const handleSplashComplete = () => {
    setShowSplash(false)
    setShowContent(true)
  }

  return (
    <>
      {showSplash && <SplashScreen onComplete={handleSplashComplete} />}
      
      <div className={`min-h-screen bg-[#0a0a0a] text-white relative overflow-hidden transition-opacity duration-500 ${showContent ? 'opacity-100' : 'opacity-0'}`}>
        {/* Subtle noise texture overlay */}
        <div 
          className="fixed inset-0 opacity-[0.015] pointer-events-none"
          style={{
            backgroundImage: `url("data:image/svg+xml,%3Csvg viewBox='0 0 256 256' xmlns='http://www.w3.org/2000/svg'%3E%3Cfilter id='noise'%3E%3CfeTurbulence type='fractalNoise' baseFrequency='0.9' numOctaves='4' stitchTiles='stitch'/%3E%3C/filter%3E%3Crect width='100%25' height='100%25' filter='url(%23noise)'/%3E%3C/svg%3E")`,
          }}
        />

        {/* Ambient gradient */}
        <div className="fixed inset-0 bg-gradient-to-b from-transparent via-transparent to-white/[0.02] pointer-events-none" />

        {/* Main content */}
        <main className="relative z-10 min-h-screen flex flex-col">
          {/* Hero Section with Logo */}
          <section className="flex-1 flex flex-col items-center justify-center px-6 pt-24 pb-12">
            {/* Logo / Wordmark */}
            <div className="text-center mb-16">
              <h1 className="text-4xl md:text-5xl lg:text-6xl font-normal tracking-[0.3em] mb-4 animate-fade-in-1">
                <LiquidMetalText text="INTERLINKED" />
                <span className="text-sm md:text-base align-super text-white/50 ml-1">®</span>
              </h1>
              <p className="text-xs md:text-sm tracking-[0.3em] text-white/30 uppercase font-sans animate-fade-in-2">
                connection, by design.
              </p>
            </div>
          </section>

          

          {/* Products Section */}
          <section id="products" className="w-full max-w-md mx-auto px-6 py-16">
            <div className="animate-fade-in-box-1">
              <ProductCard 
                name="ATLAS®" 
                status="Now Available" 
                isActive={true}
                iconSrc="/images/atlas-icon.png"
                href="/atlas"
                availability={{ mac: true, windows: false }}
              />
            </div>
          </section>

          {/* Subtle divider line */}
          <div className="w-px h-24 bg-gradient-to-b from-transparent via-white/10 to-transparent mx-auto" />

          {/* Footer */}
          <footer id="contact" className="py-12 text-center">
            <a 
              href="/contact" 
              className="text-xs tracking-[0.2em] text-white/40 hover:text-white/80 transition-colors duration-300 uppercase mb-6 inline-block"
            >
              Contact
            </a>
            <p className="text-xs tracking-[0.15em] text-white/20">
              © INTERLINKED®
            </p>
          </footer>
        </main>
      </div>

      {/* Product Carousel Modal */}
      <ProductCarousel 
        products={products}
        isOpen={carouselOpen}
        onClose={() => setCarouselOpen(false)}
      />
    </>
  )
}
