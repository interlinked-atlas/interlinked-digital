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
      style={{ background: "#07080F" }}
    >
      {/* Subtle grid */}
      <div
        className="absolute inset-0 pointer-events-none"
        style={{
          backgroundImage: `
            linear-gradient(rgba(62,207,178,0.02) 1px, transparent 1px),
            linear-gradient(90deg, rgba(62,207,178,0.02) 1px, transparent 1px)
          `,
          backgroundSize: "60px 60px",
          opacity: phase >= 1 ? 1 : 0,
          transition: "opacity 0.6s ease",
        }}
      />

      <div className="relative flex flex-col items-center gap-10">
        {/* Logo */}
        <div
          className={cn("relative transition-all duration-1000", phase >= 1 ? "opacity-100 scale-100" : "opacity-0 scale-90")}
          style={{ width: "90px", height: "90px" }}
        >
          <img
            src="/images/interlinked-icon.png"
            alt="InterLinked"
            className={cn("w-full h-full object-contain transition-all duration-700", phase >= 2 ? "animate-pulse-slow" : "")}
            style={{ filter: "drop-shadow(0 0 14px rgba(62,207,178,0.3))" }}
          />
          {["-16px", "-28px"].map((inset, i) => (
            <div
              key={i}
              className={cn(
                "absolute rounded-full transition-all duration-700",
                i === 0 ? "animate-spin-slow" : "animate-spin-slower",
                phase >= 2 ? "opacity-100" : "opacity-0"
              )}
              style={{
                inset,
                border: `1px solid rgba(62,207,178,${i === 0 ? "0.18" : "0.1"})`,
              }}
            />
          ))}
        </div>

        {/* Wordmark */}
        <div
          className={cn("text-center transition-all duration-700", phase >= 3 ? "opacity-100 translate-y-0" : "opacity-0 translate-y-2")}
        >
          <p style={{
            fontFamily: "'BomberEscort', -apple-system, BlinkMacSystemFont, sans-serif",
            fontSize: "28px",
            fontWeight: "normal",
            letterSpacing: "0.12em",
            color: "rgba(220,228,255,0.82)",
            lineHeight: 1,
            display: "inline-flex",
            alignItems: "baseline",
          }}>
            InterLinked
            <sup style={{
              fontSize: "0.28em",
              color: "rgba(62,207,178,0.45)",
              marginLeft: "3px",
              verticalAlign: "super",
              letterSpacing: 0,
              fontFamily: "-apple-system, sans-serif",
            }}>©</sup>
          </p>
        </div>

        {/* Loading bar */}
        <div
          className={cn("transition-all duration-700", phase >= 2 ? "opacity-100" : "opacity-0")}
          style={{ width: "120px", height: "1px", background: "#1E2240", borderRadius: "1px", overflow: "hidden" }}
        >
          <div
            style={{
              height: "100%",
              background: "linear-gradient(90deg, #3ECFB2, #5B8DEF)",
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
