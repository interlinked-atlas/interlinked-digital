"use client"

import { useState, useEffect } from "react"
import { cn } from "@/lib/utils"
import { ChevronLeft, ChevronRight, X } from "lucide-react"

interface Product {
  name?: string
  status?: string
  isActive?: boolean
  isHidden?: boolean
  iconSrc?: string
}

interface ProductCarouselProps {
  products: Product[]
  isOpen: boolean
  onClose: () => void
}

export function ProductCarousel({ products, isOpen, onClose }: ProductCarouselProps) {
  const [currentIndex, setCurrentIndex] = useState(0)
  const [isAnimating, setIsAnimating] = useState(false)
  const [isVisible, setIsVisible] = useState(false)

  useEffect(() => {
    if (isOpen) {
      setCurrentIndex(0)
      setTimeout(() => setIsVisible(true), 50)
    } else {
      setIsVisible(false)
    }
  }, [isOpen])

  const goToPrevious = () => {
    if (isAnimating) return
    setIsAnimating(true)
    setCurrentIndex((prev) => (prev === 0 ? products.length - 1 : prev - 1))
    setTimeout(() => setIsAnimating(false), 500)
  }

  const goToNext = () => {
    if (isAnimating) return
    setIsAnimating(true)
    setCurrentIndex((prev) => (prev === products.length - 1 ? 0 : prev + 1))
    setTimeout(() => setIsAnimating(false), 500)
  }

  const handleClose = () => {
    setIsVisible(false)
    setTimeout(onClose, 300)
  }

  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if (!isOpen) return
      if (e.key === "ArrowLeft") goToPrevious()
      if (e.key === "ArrowRight") goToNext()
      if (e.key === "Escape") handleClose()
    }
    window.addEventListener("keydown", handleKeyDown)
    return () => window.removeEventListener("keydown", handleKeyDown)
  }, [isOpen, isAnimating])

  if (!isOpen) return null

  const product = products[currentIndex]

  return (
    <div 
      className={cn(
        "fixed inset-0 z-50 flex items-center justify-center transition-all duration-300",
        isVisible ? "opacity-100" : "opacity-0"
      )}
    >
      {/* Backdrop */}
      <div 
        className="absolute inset-0 bg-[#0a0a0a]/95 backdrop-blur-md"
        onClick={handleClose}
      />

      {/* Close button */}
      <button
        onClick={handleClose}
        className="absolute top-8 right-8 z-10 p-2 text-white/40 hover:text-white/80 transition-colors duration-300"
        aria-label="Close gallery"
      >
        <X className="w-6 h-6" />
      </button>

      {/* Navigation arrows */}
      <button
        onClick={goToPrevious}
        className="absolute left-8 z-10 p-3 text-white/30 hover:text-white/70 transition-all duration-300 hover:scale-110"
        aria-label="Previous product"
      >
        <ChevronLeft className="w-10 h-10" />
      </button>

      <button
        onClick={goToNext}
        className="absolute right-8 z-10 p-3 text-white/30 hover:text-white/70 transition-all duration-300 hover:scale-110"
        aria-label="Next product"
      >
        <ChevronRight className="w-10 h-10" />
      </button>

      {/* Product card - enlarged */}
      <div 
        className={cn(
          "relative z-10 transition-all duration-500 ease-out",
          isVisible ? "scale-100 opacity-100" : "scale-90 opacity-0"
        )}
      >
        <div
          className={cn(
            "relative group h-[28rem] w-[24rem] rounded-xl border bg-white/[0.03] backdrop-blur-sm transition-all duration-500",
            product.isActive 
              ? "border-white/25 shadow-[0_0_80px_rgba(255,255,255,0.08)]" 
              : "border-white/10",
            product.isHidden && "select-none"
          )}
        >
          {/* Subtle corner accents */}
          <div className={cn(
            "absolute top-0 left-0 w-12 h-12 border-l-2 border-t-2 rounded-tl-xl transition-all duration-500",
            product.isActive ? "border-white/40" : "border-white/15",
            product.isHidden && "border-white/5"
          )} />
          <div className={cn(
            "absolute bottom-0 right-0 w-12 h-12 border-r-2 border-b-2 rounded-br-xl transition-all duration-500",
            product.isActive ? "border-white/40" : "border-white/15",
            product.isHidden && "border-white/5"
          )} />

          {/* Content */}
          <div className={cn(
            "flex flex-col items-center justify-center h-full px-8 transition-all duration-500",
            product.isHidden && "blur-sm"
          )}>
            {product.isHidden ? (
              <>
                <div className="h-24 w-24 bg-white/10 rounded-xl mb-6" />
                <div className="h-6 w-32 bg-white/10 rounded mb-4" />
                <div className="h-4 w-20 bg-white/5 rounded" />
              </>
            ) : (
              <>
                {product.iconSrc && (
                  <div className="relative mb-8">
                    <img
                      src={product.iconSrc || "/placeholder.svg"}
                      alt={`${product.name} icon`}
                      className="w-32 h-32 object-contain"
                    />
                  </div>
                )}
                <h3 className="text-3xl font-light tracking-[0.3em] text-white mb-6">
                  {product.name}
                </h3>
                {product.status && (
                  <span className={cn(
                    "text-sm tracking-[0.2em] uppercase px-4 py-2 rounded-full border transition-all duration-300",
                    product.isActive 
                      ? "text-white/80 border-white/25 bg-white/5" 
                      : "text-white/50 border-white/10"
                  )}>
                    {product.status}
                  </span>
                )}
              </>
            )}
          </div>

          {/* Glow effect for active card */}
          {product.isActive && (
            <div className="absolute inset-0 rounded-xl bg-gradient-to-t from-white/[0.03] to-transparent pointer-events-none" />
          )}
        </div>
      </div>

      {/* Pagination dots */}
      <div className="absolute bottom-12 flex gap-3">
        {products.map((_, index) => (
          <button
            key={index}
            onClick={() => {
              if (!isAnimating) {
                setIsAnimating(true)
                setCurrentIndex(index)
                setTimeout(() => setIsAnimating(false), 500)
              }
            }}
            className={cn(
              "w-2 h-2 rounded-full transition-all duration-300",
              index === currentIndex 
                ? "bg-white/80 w-6" 
                : "bg-white/20 hover:bg-white/40"
            )}
            aria-label={`Go to product ${index + 1}`}
          />
        ))}
      </div>
    </div>
  )
}
