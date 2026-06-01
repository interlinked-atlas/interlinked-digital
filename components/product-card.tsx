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
  availability?: {
    mac?: boolean
    windows?: boolean
  }
}

export function ProductCard({ name, status, isActive = false, isHidden = false, iconSrc, href, availability }: ProductCardProps) {
  const CardWrapper = href ? Link : "div"
  const wrapperProps = href ? { href } : {}
  
  return (
    <CardWrapper
      {...wrapperProps as any}
      className={cn(
        "relative group h-72 w-full rounded-lg border border-white/10 bg-white/[0.02] backdrop-blur-sm transition-all duration-500 block",
        href && "cursor-pointer",
        isActive && "border-white/20 bg-white/[0.04] shadow-[0_0_40px_rgba(255,255,255,0.05)]",
        isHidden && "select-none",
        !isHidden && "hover:border-white/30 hover:bg-white/[0.05] hover:shadow-[0_0_60px_rgba(255,255,255,0.08)]"
      )}
    >
      {/* Subtle corner accents */}
      <div className={cn(
        "absolute top-0 left-0 w-8 h-8 border-l border-t transition-all duration-500",
        isActive ? "border-white/30" : "border-white/10",
        isHidden && "border-white/5"
      )} />
      <div className={cn(
        "absolute bottom-0 right-0 w-8 h-8 border-r border-b transition-all duration-500",
        isActive ? "border-white/30" : "border-white/10",
        isHidden && "border-white/5"
      )} />

      {/* Content */}
      <div className={cn(
        "flex flex-col items-center justify-center h-full px-6 transition-all duration-500",
        isHidden && "blur-sm"
      )}>
        {isHidden ? (
          <>
            <div className="h-16 w-16 bg-white/10 rounded-lg mb-4" />
            <div className="h-4 w-24 bg-white/10 rounded mb-3" />
            <div className="h-3 w-16 bg-white/5 rounded" />
          </>
        ) : (
          <>
            {iconSrc && (
              <div className="relative mb-6">
                <img
                  src={iconSrc || "/placeholder.svg"}
                  alt={`${name} icon`}
                  className={cn(
                    "w-20 h-20 object-contain transition-all duration-700 ease-out",
                    isActive 
                      ? "blur-md opacity-60 group-hover:blur-none group-hover:opacity-100" 
                      : "blur-[2px] opacity-80 group-hover:blur-[1px] group-hover:opacity-90"
                  )}
                />
              </div>
            )}
            <h3 className={cn(
              "text-2xl font-light tracking-[0.3em] mb-4 transition-all duration-700 ease-out",
              isActive 
                ? "text-white blur-md group-hover:blur-none" 
                : "text-white/90"
            )}>
              {name}
            </h3>
            {status && !availability && (
              <span className={cn(
                "text-xs tracking-[0.2em] uppercase px-3 py-1 rounded-full border transition-all duration-300",
                isActive 
                  ? "text-white/80 border-white/20 bg-white/5" 
                  : "text-white/50 border-white/10"
              )}>
                {status}
              </span>
            )}
            {availability && (
              <div className="flex flex-col items-center gap-2">
                {availability.mac && (
                  <span className="flex items-center gap-2 text-xs tracking-[0.15em] text-white/70">
                    <svg viewBox="0 0 24 24" className="w-4 h-4" fill="currentColor">
                      <path d="M18.71 19.5c-.83 1.24-1.71 2.45-3.05 2.47-1.34.03-1.77-.79-3.29-.79-1.53 0-2 .77-3.27.82-1.31.05-2.3-1.32-3.14-2.53C4.25 17 2.94 12.45 4.7 9.39c.87-1.52 2.43-2.48 4.12-2.51 1.28-.02 2.5.87 3.29.87.78 0 2.26-1.07 3.81-.91.65.03 2.47.26 3.64 1.98-.09.06-2.17 1.28-2.15 3.81.03 3.02 2.65 4.03 2.68 4.04-.03.07-.42 1.44-1.38 2.83M13 3.5c.73-.83 1.94-1.46 2.94-1.5.13 1.17-.34 2.35-1.04 3.19-.69.85-1.83 1.51-2.95 1.42-.15-1.15.41-2.35 1.05-3.11z"/>
                    </svg>
                    Now Available for Mac
                  </span>
                )}
                {availability.windows === false && (
                  <span className="text-xs tracking-[0.15em] text-white/40">
                    Windows Coming Soon
                  </span>
                )}
              </div>
            )}
          </>
        )}
      </div>

      {/* Glow effect for active card */}
      {isActive && (
        <div className="absolute inset-0 rounded-lg bg-gradient-to-t from-white/[0.02] to-transparent pointer-events-none" />
      )}
    </CardWrapper>
  )
}
