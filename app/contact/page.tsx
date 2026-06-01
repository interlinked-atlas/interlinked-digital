import Link from "next/link"

export default function ContactPage() {
  return (
    <div className="min-h-screen bg-[#0a0a0a] text-white relative overflow-hidden">
      {/* Subtle noise texture overlay */}
      <div 
        className="fixed inset-0 opacity-[0.015] pointer-events-none"
        style={{
          backgroundImage: `url("data:image/svg+xml,%3Csvg viewBox='0 0 256 256' xmlns='http://www.w3.org/2000/svg'%3E%3Cfilter id='noise'%3E%3CfeTurbulence type='fractalNoise' baseFrequency='0.9' numOctaves='4' stitchTiles='stitch'/%3E%3C/filter%3E%3Crect width='100%25' height='100%25' filter='url(%23noise)'/%3E%3C/svg%3E")`,
        }}
      />

      {/* Main content */}
      <main className="relative z-10 min-h-screen flex flex-col items-center justify-center px-6">
        <Link 
          href="/"
          className="absolute top-8 left-8 text-xs tracking-[0.2em] text-white/40 hover:text-white/80 transition-colors duration-300 uppercase"
        >
          Back
        </Link>
        
        <a 
          href="mailto:interlinked.digital@gmail.com"
          className="text-lg md:text-xl tracking-[0.15em] text-white/60 hover:text-white transition-colors duration-300"
        >
          interlinked.digital@gmail.com
        </a>
      </main>
    </div>
  )
}
