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
        "relative group h-72 w-full rounded-xl border transition-all duration-300 block overflow-hidden",
        isHidden ? "cursor-default" : href ? "cursor-pointer" : "cursor-default"
      )}
      style={{
        background: "#0C0E1C",
        borderColor: isActive ? "rgba(62,207,178,0.3)" : "#1E2240",
        boxShadow: isActive ? "0 0 40px rgba(62,207,178,0.05)" : "none",
      }}
      onMouseEnter={e => {
        if (!isHidden) {
          const el = e.currentTarget as HTMLElement
          el.style.borderColor = "rgba(62,207,178,0.45)"
          el.style.boxShadow = "0 0 32px rgba(62,207,178,0.08)"
        }
      }}
      onMouseLeave={e => {
        const el = e.currentTarget as HTMLElement
        el.style.borderColor = isActive ? "rgba(62,207,178,0.3)" : "#1E2240"
        el.style.boxShadow = isActive ? "0 0 40px rgba(62,207,178,0.05)" : "none"
      }}
    >
      {/* Corner accents */}
      <div className="absolute top-0 left-0 w-8 h-8 pointer-events-none"
        style={{ borderLeft: "1px solid rgba(62,207,178,0.25)", borderTop: "1px solid rgba(62,207,178,0.25)" }} />
      <div className="absolute bottom-0 right-0 w-8 h-8 pointer-events-none"
        style={{ borderRight: "1px solid rgba(62,207,178,0.25)", borderBottom: "1px solid rgba(62,207,178,0.25)" }} />

      {/* Top teal strip when active */}
      {isActive && (
        <div className="absolute top-0 inset-x-0 h-px"
          style={{ background: "linear-gradient(90deg, transparent, rgba(62,207,178,0.5), transparent)" }} />
      )}

      <div className={cn("flex flex-col items-center justify-center h-full px-6", isHidden && "blur-sm")}>
        {isHidden ? (
          <>
            <div className="h-16 w-16 rounded-lg mb-4" style={{ background: "#1E2240" }} />
            <div className="h-4 w-24 rounded mb-3" style={{ background: "#1E2240" }} />
            <div className="h-3 w-16 rounded" style={{ background: "#13151F" }} />
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
                      ? "blur(6px) drop-shadow(0 0 14px rgba(62,207,178,0.4))"
                      : "blur(2px) opacity(0.7)",
                  }}
                  onMouseEnter={e => {
                    (e.currentTarget as HTMLImageElement).style.filter =
                      "blur(0px) drop-shadow(0 0 18px rgba(62,207,178,0.5))"
                  }}
                  onMouseLeave={e => {
                    (e.currentTarget as HTMLImageElement).style.filter = isActive
                      ? "blur(6px) drop-shadow(0 0 14px rgba(62,207,178,0.4))"
                      : "blur(2px) opacity(0.7)"
                  }}
                />
              </div>
            )}

            <h3 style={{
              fontFamily: "'SF-Intellivised', -apple-system, sans-serif",
              fontSize: "22px",
              fontWeight: "normal",
              letterSpacing: "6px",
              color: "#E8ECFF",
              marginBottom: "6px",
              textIndent: "6px",
            }}>
              {name?.replace("®", "")}
              {name?.includes("®") && (
                <sup style={{ fontSize: "0.4em", color: "rgba(255,255,255,0.3)", verticalAlign: "super" }}>®</sup>
              )}
            </h3>

            {status && (
              <span style={{
                fontSize: "9px",
                fontWeight: 700,
                letterSpacing: "2.5px",
                color: isActive ? "#3ECFB2" : "#353860",
                textTransform: "uppercase",
                marginBottom: "12px",
              }}>
                {status}
              </span>
            )}

            {availability && (
              <div style={{ display: "flex", gap: "8px", marginTop: "4px" }}>
                {availability.mac && (
                  <span style={{
                    fontSize: "9px", letterSpacing: "1px", color: "#4A5280",
                    padding: "3px 8px", borderRadius: "4px",
                    border: "1px solid #1E2240", background: "#0A0D1C",
                  }}>macOS</span>
                )}
                {availability.windows && (
                  <span style={{
                    fontSize: "9px", letterSpacing: "1px", color: "#4A5280",
                    padding: "3px 8px", borderRadius: "4px",
                    border: "1px solid #1E2240", background: "#0A0D1C",
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
