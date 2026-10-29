import Link from "next/link"

export default function NotFound() {
  return (
    <div className="min-h-screen bg-[#0a0a0a] text-white relative overflow-hidden">
      <div
        className="fixed inset-0 opacity-[0.015] pointer-events-none"
        style={{
          backgroundImage: `url("data:image/svg+xml,%3Csvg viewBox='0 0 256 256' xmlns='http://www.w3.org/2000/svg'%3E%3Cfilter id='noise'%3E%3CfeTurbulence type='fractalNoise' baseFrequency='0.9' numOctaves='4' stitchTiles='stitch'/%3E%3C/filter%3E%3Crect width='100%25' height='100%25' filter='url(%23noise)'/%3E%3C/svg%3E")`,
        }}
      />

      <main className="relative z-10 min-h-screen flex flex-col items-center justify-center px-6 text-center">
        <p className="text-xs tracking-[0.3em] text-white/30 uppercase mb-4">404</p>
        <h1 className="text-2xl md:text-3xl tracking-[0.05em] text-white/80 mb-8">
          This page doesn&apos;t exist.
        </h1>
        <Link
          href="/"
          className="text-xs tracking-[0.2em] text-white/40 hover:text-white/80 transition-colors duration-300 uppercase"
        >
          Back to InterLinked
        </Link>
      </main>
    </div>
  )
}
