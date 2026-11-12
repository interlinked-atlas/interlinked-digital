"use client"

import { useState, useEffect } from "react"
import { cn } from "@/lib/utils"

interface SplashScreenProps { onComplete: () => void }

export function SplashScreen({ onComplete }: SplashScreenProps) {
  const [phase, setPhase] = useState(0)

  useEffect(() => {
    const t1 = setTimeout(() => setPhase(1), 400)
    const t2 = setTimeout(() => setPhase(2), 1400)
    const t3 = setTimeout(() => setPhase(3), 2400)
    const t4 = setTimeout(() => setPhase(4), 3800)
    const t5 = setTimeout(() => onComplete(), 4800)
    return () => [t1,t2,t3,t4,t5].forEach(clearTimeout)
  }, [onComplete])

  return (
    <div
      className={cn(
        "fixed inset-0 z-50 flex items-center justify-center transition-opacity duration-1000",
        phase >= 4 ? "opacity-0 pointer-events-none" : "opacity-100"
      )}
      style={{ background: "var(--il-bg)" }}
    >
      {/* Subtle grid */}
      <div
        className="absolute inset-0 pointer-events-none"
        style={{
          backgroundImage: `
            linear-gradient(var(--il-border) 1px, transparent 1px),
            linear-gradient(90deg, var(--il-border) 1px, transparent 1px)
          `,
          backgroundSize: "60px 60px",
          opacity: phase >= 1 ? 0.5 : 0,
          transition: "opacity 0.6s ease",
        }}
      />

      <div className="relative flex flex-col items-center gap-10">
        {/* Logo */}
        <div
          className={cn("relative transition-all duration-1000", phase >= 1 ? "opacity-100 scale-100" : "opacity-0 scale-90")}
          style={{ width: "220px" }}
        >
          <img
            src="/images/interlinked-logo-full.png"
            alt="InterLinked"
            className={cn("il-logo-dark w-full h-auto object-contain transition-all duration-700", phase >= 2 ? "animate-pulse-slow" : "")}
            style={{ filter: "drop-shadow(0 0 14px var(--il-glow))" }}
          />
          <img
            src="/images/interlinked-logo-full-light.png"
            alt="InterLinked"
            className={cn("il-logo-light w-full h-auto object-contain transition-all duration-700", phase >= 2 ? "animate-pulse-slow" : "")}
            style={{ filter: "drop-shadow(0 0 14px var(--il-glow))" }}
          />
        </div>

        {/* Loading bar */}
        <div
          className={cn("transition-all duration-700", phase >= 2 ? "opacity-100" : "opacity-0")}
          style={{ width: "120px", height: "1px", background: "var(--il-border)", borderRadius: "1px", overflow: "hidden" }}
        >
          <div
            style={{
              height: "100%",
              background: "linear-gradient(90deg, var(--il-secondary), var(--il-primary))",
              borderRadius: "1px",
              transition: "width 2.5s ease",
              width: phase >= 2 ? "100%" : "0%",
            }}
          />
        </div>
      </div>
    </div>
  )
}
