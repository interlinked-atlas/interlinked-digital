"use client"

import { useState } from "react"
import { ProductCard } from "@/components/product-card"
import { InterLinkedWordmark } from "@/components/liquid-metal-text"
import { SplashScreen } from "@/components/splash-screen"

export default function Home() {
  const [showSplash, setShowSplash] = useState(true)
  const [showContent, setShowContent] = useState(false)

  return (
    <>
      {showSplash && (
        <SplashScreen onComplete={() => { setShowSplash(false); setShowContent(true) }} />
      )}

      <div
        style={{ opacity: showContent ? 1 : 0, transition: "opacity 0.6s ease", background: "var(--il-bg)" }}
        className="min-h-screen relative overflow-hidden"
      >
        {/* Background grid */}
        <div
          className="fixed inset-0 pointer-events-none"
          style={{
            backgroundImage: `
              linear-gradient(var(--il-border) 1px, transparent 1px),
              linear-gradient(90deg, var(--il-border) 1px, transparent 1px)
            `,
            backgroundSize: "60px 60px",
            opacity: 0.6,
          }}
        />
        {/* Radial glow */}
        <div
          className="fixed inset-0 pointer-events-none"
          style={{
            background: "radial-gradient(ellipse 60% 40% at 50% 0%, var(--il-glow) 0%, transparent 70%)",
          }}
        />

        <main className="relative z-10 min-h-screen flex flex-col">
          {/* ── Hero ── */}
          <section className="flex-1 flex flex-col items-center justify-center px-6 pt-24 pb-12">
            <div className="text-center mb-16">
              <h1 className="animate-fade-in-1" style={{ lineHeight: 1, marginBottom: "0" }}>
                <InterLinkedWordmark />
              </h1>
            </div>
          </section>

          {/* ── Products ── */}
          <section className="w-full max-w-sm mx-auto px-6 pb-24">
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

          {/* ── Footer ── */}
          <footer
            className="animate-fade-in-3"
            style={{
              padding: "20px",
              textAlign: "center",
              color: "var(--il-border-hover)",
              fontSize: "10px",
              letterSpacing: "2px",
            }}
          >
            INTERLINKED© · ALL RIGHTS RESERVED
          </footer>
        </main>
      </div>
    </>
  )
}
