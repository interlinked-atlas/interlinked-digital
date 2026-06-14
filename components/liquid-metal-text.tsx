"use client"

import { useEffect, useRef } from "react"

export function InterLinkedWordmark() {
  const ref = useRef<HTMLSpanElement>(null)

  useEffect(() => {
    const el = ref.current
    if (!el) return
    const letters = el.querySelectorAll<HTMLSpanElement>(".il-letter")

    const sweep = () => {
      letters.forEach((l, i) => {
        setTimeout(() => {
          l.style.color = "var(--il-text)"
          l.style.textShadow = "0 0 18px var(--il-border-hover)"
          setTimeout(() => {
            l.style.color = ""
            l.style.textShadow = ""
          }, 600)
        }, i * 80)
      })
    }

    const t = setTimeout(sweep, 600)
    const iv = setInterval(sweep, 5000)
    return () => { clearTimeout(t); clearInterval(iv) }
  }, [])

  const word = "InterLinked"

  return (
    <span
      style={{
        display: "inline-flex",
        alignItems: "baseline",
        fontFamily: "'Vipnagorgialla', -apple-system, BlinkMacSystemFont, sans-serif",
        fontSize: "clamp(36px, 5.5vw, 60px)",
        fontWeight: "normal",
        letterSpacing: "0.12em",
        color: "var(--il-primary)",
        lineHeight: 1,
      }}
    >
      <span ref={ref} style={{ display: "inline-flex", alignItems: "baseline" }}>
        {word.split("").map((char, i) => (
          <span
            key={i}
            className="il-letter"
            style={{
              display: "inline-block",
              transition: "color 0.3s ease, text-shadow 0.3s ease",
              color: "inherit",
            }}
          >
            {char}
          </span>
        ))}
      </span>
      <sup
        style={{
          fontSize: "0.28em",
          color: "var(--il-secondary)",
          marginLeft: "3px",
          verticalAlign: "super",
          letterSpacing: 0,
          fontFamily: "-apple-system, sans-serif",
        }}
      >
        ©
      </sup>
    </span>
  )
}

export function LiquidMetalText({ text, className = "" }: { text: string; className?: string }) {
  return (
    <span className={className} style={{ fontFamily: "'SF-Intellivised', -apple-system, sans-serif" }}>
      {text}
    </span>
  )
}
