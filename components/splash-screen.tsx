"use client"

import { useState, useEffect } from "react"
import { cn } from "@/lib/utils"

interface SplashScreenProps {
  onComplete: () => void
}

export function SplashScreen({ onComplete }: SplashScreenProps) {
  const [phase, setPhase] = useState(0)
  
  useEffect(() => {
    // Phase 1: Logo appears (0.5s delay)
    const timer1 = setTimeout(() => setPhase(1), 500)
    // Phase 2: Orbital lines animate (1.5s)
    const timer2 = setTimeout(() => setPhase(2), 1500)
    // Phase 3: Text appears (2.5s)
    const timer3 = setTimeout(() => setPhase(3), 2500)
    // Phase 4: Begin exit (4s)
    const timer4 = setTimeout(() => setPhase(4), 4000)
    // Complete (5s)
    const timer5 = setTimeout(() => onComplete(), 5000)
    
    return () => {
      clearTimeout(timer1)
      clearTimeout(timer2)
      clearTimeout(timer3)
      clearTimeout(timer4)
      clearTimeout(timer5)
    }
  }, [onComplete])

  return (
    <div 
      className={cn(
        "fixed inset-0 z-50 bg-[#0a0a0a] flex items-center justify-center transition-opacity duration-1000",
        phase >= 4 ? "opacity-0 pointer-events-none" : "opacity-100"
      )}
    >
      {/* Scanning lines effect */}
      <div className="absolute inset-0 overflow-hidden pointer-events-none">
        <div 
          className={cn(
            "absolute inset-0 transition-opacity duration-500",
            phase >= 1 ? "opacity-100" : "opacity-0"
          )}
          style={{
            background: `repeating-linear-gradient(
              0deg,
              transparent,
              transparent 2px,
              rgba(255, 255, 255, 0.01) 2px,
              rgba(255, 255, 255, 0.01) 4px
            )`
          }}
        />
      </div>

      {/* Center content */}
      <div className="relative flex flex-col items-center">
        {/* INTERLINKED Logo Icon */}
        <div 
          className={cn(
            "relative w-32 h-32 mb-12 transition-all duration-1000",
            phase >= 1 ? "opacity-100 scale-100" : "opacity-0 scale-90"
          )}
        >
          <img 
            src="/images/interlinked-icon.png" 
            alt="INTERLINKED"
            className={cn(
              "w-full h-full object-contain invert transition-all duration-700",
              phase >= 2 ? "animate-pulse-slow" : ""
            )}
          />
          
          {/* Orbital ring animation */}
          <div 
            className={cn(
              "absolute inset-[-20px] border border-white/10 rounded-full transition-all duration-1000",
              phase >= 2 ? "opacity-100 scale-100 animate-spin-slow" : "opacity-0 scale-75"
            )}
          />
          <div 
            className={cn(
              "absolute inset-[-40px] border border-white/5 rounded-full transition-all duration-1000 delay-200",
              phase >= 2 ? "opacity-100 scale-100 animate-spin-slower" : "opacity-0 scale-75"
            )}
          />
        </div>

        {/* Loading bar */}
        <div 
          className={cn(
            "w-48 h-px bg-white/10 mb-8 overflow-hidden transition-opacity duration-500",
            phase >= 2 ? "opacity-100" : "opacity-0"
          )}
        >
          <div 
            className={cn(
              "h-full bg-gradient-to-r from-transparent via-white/60 to-transparent transition-transform duration-[2000ms] ease-out",
              phase >= 2 ? "translate-x-48" : "-translate-x-48"
            )}
          />
        </div>

        {/* Text */}
        <div 
          className={cn(
            "text-center transition-all duration-700",
            phase >= 3 ? "opacity-100 translate-y-0" : "opacity-0 translate-y-4"
          )}
        >
          <p className="text-[10px] tracking-[0.5em] text-white/30 uppercase mb-2">
            Initializing
          </p>
          <h1 className="text-2xl tracking-[0.4em] text-white/80 font-light">
            INTERLINKED<span className="text-xs align-super text-white/40 ml-1">®</span>
          </h1>
        </div>

        {/* Corner accents */}
        <div className={cn(
          "absolute -top-20 -left-20 w-8 h-8 border-l border-t border-white/10 transition-opacity duration-500",
          phase >= 2 ? "opacity-100" : "opacity-0"
        )} />
        <div className={cn(
          "absolute -top-20 -right-20 w-8 h-8 border-r border-t border-white/10 transition-opacity duration-500",
          phase >= 2 ? "opacity-100" : "opacity-0"
        )} />
        <div className={cn(
          "absolute -bottom-20 -left-20 w-8 h-8 border-l border-b border-white/10 transition-opacity duration-500",
          phase >= 2 ? "opacity-100" : "opacity-0"
        )} />
        <div className={cn(
          "absolute -bottom-20 -right-20 w-8 h-8 border-r border-b border-white/10 transition-opacity duration-500",
          phase >= 2 ? "opacity-100" : "opacity-0"
        )} />
      </div>

      {/* Bottom status text */}
      <div 
        className={cn(
          "absolute bottom-12 left-1/2 -translate-x-1/2 transition-all duration-500",
          phase >= 3 ? "opacity-100" : "opacity-0"
        )}
      >
        <p className="text-[9px] tracking-[0.3em] text-white/20 uppercase">
          Systems Online
        </p>
      </div>
    </div>
  )
}
