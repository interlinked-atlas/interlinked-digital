"use client"

import { useEffect, useRef } from "react"

interface LiquidMetalTextProps {
  text: string
  className?: string
}

export function LiquidMetalText({ text, className = "" }: LiquidMetalTextProps) {
  const containerRef = useRef<HTMLDivElement>(null)

  useEffect(() => {
    const container = containerRef.current
    if (!container) return

    const letters = container.querySelectorAll<HTMLSpanElement>(".metal-letter")
    
    // Animate each letter with staggered liquid metal sweep
    const animateSweep = () => {
      letters.forEach((letter, index) => {
        const delay = index * 150
        
        setTimeout(() => {
          letter.classList.add("sweeping")
          setTimeout(() => {
            letter.classList.remove("sweeping")
          }, 800)
        }, delay)
      })
    }

    // Initial animation
    const initialTimeout = setTimeout(animateSweep, 500)
    
    // Repeat animation every 5 seconds
    const interval = setInterval(animateSweep, 5000)

    return () => {
      clearTimeout(initialTimeout)
      clearInterval(interval)
    }
  }, [])

  return (
    <div ref={containerRef} className={`inline-flex ${className}`}>
      {text.split("").map((char, index) => (
        <span
          key={index}
          className="metal-letter relative inline-block"
          style={{
            fontFamily: "'Aerodome', sans-serif",
          }}
        >
          <span className="relative z-10 text-white/90">{char}</span>
          <span 
            className="absolute inset-0 text-transparent bg-clip-text metal-shine pointer-events-none"
            aria-hidden="true"
          >
            {char}
          </span>
        </span>
      ))}
    </div>
  )
}
