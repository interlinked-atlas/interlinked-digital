"use client"

import { cn } from "@/lib/utils"
import Link from "next/link"

interface ProductCardProps {
  name?: string
  status?: string
  isActive?: boolean
  isHidden?: boolean
  iconSrc?: string
  href?: string
  availability?: { mac?: boolean; windows?: boolean }
}

export function ProductCard({
  name, status, isActive = false, isHidden = false, iconSrc, href, availability,
}: ProductCardProps) {
  const CardWrapper = href ? Link : "div"
  const wrapperProps = href ? { href } : {}

  return (
    <CardWrapper
      {...(wrapperProps as any)}
      className={cn(
        "il-product-card relative group h-72 w-full rounded-xl block overflow-hidden",
        isActive && "il-active",
        isHidden ? "cursor-default" : href ? "cursor-pointer" : "cursor-default"
      )}
    >
      {/* Corner accents */}
      <div className="absolute top-0 left-0 w-8 h-8 pointer-events-none"
        style={{ borderLeft: "1px solid var(--il-border-hover)", borderTop: "1px solid var(--il-border-hover)" }} />
      <div className="absolute bottom-0 right-0 w-8 h-8 pointer-events-none"
        style={{ borderRight: "1px solid var(--il-border-hover)", borderBottom: "1px solid var(--il-border-hover)" }} />

      {/* Top accent strip when active */}
      {isActive && (
        <div className="absolute top-0 inset-x-0 h-px"
          style={{ background: "linear-gradient(90deg, transparent, var(--il-primary), transparent)", opacity: 0.5 }} />
      )}

      <div className={cn("flex flex-col items-center justify-center h-full px-6", isHidden && "blur-sm")}>
        {isHidden ? (
          <>
            <div className="h-16 w-16 rounded-lg mb-4" style={{ background: "var(--il-border)" }} />
            <div className="h-4 w-24 rounded mb-3" style={{ background: "var(--il-border)" }} />
            <div className="h-3 w-16 rounded" style={{ background: "var(--il-border)", opacity: 0.5 }} />
          </>
        ) : (
          <>
            {iconSrc && (
              <div className="relative mb-6">
                <img
                  src={iconSrc}
                  alt={`${name} icon`}
                  className="w-20 h-20 object-contain transition-all duration-500"
                  style={{
                    filter: isActive
                      ? "drop-shadow(0 0 14px var(--il-glow)) brightness(0.95)"
                      : "brightness(0.75) saturate(0.8)",
                  }}
                  onMouseEnter={e => {
                    (e.currentTarget as HTMLImageElement).style.filter =
                      "drop-shadow(0 0 18px var(--il-border-hover)) brightness(1.05)"
                  }}
                  onMouseLeave={e => {
                    (e.currentTarget as HTMLImageElement).style.filter = isActive
                      ? "drop-shadow(0 0 14px var(--il-glow)) brightness(0.95)"
                      : "brightness(0.75) saturate(0.8)"
                  }}
                />
              </div>
            )}

            <h3 style={{
              fontFamily: "'SF-Intellivised', -apple-system, sans-serif",
              fontSize: "22px",
              fontWeight: "normal",
              letterSpacing: "6px",
              color: "var(--il-primary)",
              marginBottom: "6px",
              textIndent: "6px",
            }}>
              {name?.replace("®", "")}
              {name?.includes("®") && (
                <sup style={{ fontSize: "0.4em", color: "var(--il-secondary)", verticalAlign: "super" }}>®</sup>
              )}
            </h3>

            {status && (
              <span style={{
                fontSize: "9px",
                fontWeight: 700,
                letterSpacing: "2.5px",
                color: isActive ? "var(--il-primary)" : "var(--il-secondary)",
                textTransform: "uppercase",
                marginBottom: "12px",
                opacity: isActive ? 1 : 0.6,
              }}>
                {status}
              </span>
            )}

            {availability && (
              <div style={{ display: "flex", gap: "8px", marginTop: "4px" }}>
                {availability.mac && (
                  <span style={{
                    fontSize: "9px", letterSpacing: "1px", color: "var(--il-secondary)",
                    padding: "3px 8px", borderRadius: "4px",
                    border: "1px solid var(--il-border)", background: "transparent",
                  }}>macOS</span>
                )}
                {availability.windows && (
                  <span style={{
                    fontSize: "9px", letterSpacing: "1px", color: "var(--il-secondary)",
                    padding: "3px 8px", borderRadius: "4px",
                    border: "1px solid var(--il-border)", background: "transparent",
                  }}>Windows</span>
                )}
              </div>
            )}
          </>
        )}
      </div>
    </CardWrapper>
  )
}
