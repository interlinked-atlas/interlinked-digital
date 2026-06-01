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

    const animateSweep = () => {
      letters.forEach((letter, index) => {
        setTimeout(() => {
          letter.classList.add("sweeping")
          setTimeout(() => letter.classList.remove("sweeping"), 900)
        }, index * 130)
      })
    }

    const t0 = setTimeout(animateSweep, 400)
    const iv = setInterval(animateSweep, 5500)
    return () => { clearTimeout(t0); clearInterval(iv) }
  }, [])

  return (
    <div ref={containerRef} className={`inline-flex ${className}`}>
      {text.split("").map((char, index) => (
        <span
          key={index}
          className="metal-letter relative inline-block"
          style={{ fontFamily: "'SF-Intellivised', -apple-system, sans-serif" }}
        >
          <span className="relative z-10" style={{ color: "rgba(232,236,255,0.88)" }}>{char}</span>
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
