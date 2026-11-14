'use client'

import { useState, useEffect, useRef, useCallback } from 'react'
import { useTheme } from 'next-themes'

const FEATURES: Record<string, { title: string; body: string }> = {
  install: {
    title: 'Installation',
    body: "Drop in a plugin or software installer and ATLAS handles the install automatically — no manual drag-and-drop into system folders, no guessing where a format needs to go. One click, and it's installed correctly.",
  },
  uninstall: {
    title: 'Uninstallation',
    body: 'ATLAS removes exactly what it installed, nothing more — including the install receipts and leftover files most uninstallers skip, so your system folders stay clean and organized instead of accumulating orphaned files over time.',
  },
  recovery: {
    title: 'Recovery / Rollback',
    body: 'If an install needs to be undone, ATLAS can roll it back — restoring your system to the way it was before that install, when that’s possible for the install in question.',
  },
  'recovery-kit': {
    title: 'ATLAS Recovery Kit™',
    body: 'A cloud backup of your ATLAS install history. If you move to a new Mac or need to restore your setup, ATLAS Recovery Kit™ keeps that history backed up and available, so you’re not starting over from scratch.',
  },
  cleaner: {
    title: 'ATLAS Cleaner™',
    body: 'Finds leftover files from software that was removed outside of ATLAS, so your Mac doesn’t quietly accumulate clutter from installers and plugins you no longer use.',
  },
  formats: {
    title: 'Product Format Management',
    body: 'Plugins can come in several formats — AU, VST, VST3, AAX, and more. ATLAS keeps track of which formats of a product are installed and where, so you always know the status of each format instead of hunting through system folders yourself.',
  },
  browser: {
    title: 'ATLAS Browser™',
    body: 'Browse and select from available catalogs of plugins, apps, and sample content — all in one place inside ATLAS. Filter by category or brand and see full details for each product before you decide. ATLAS does not host any files.',
  },
}

const FEATURE_TABS: { key: string; label: string }[] = [
  { key: 'install', label: 'Installation' },
  { key: 'uninstall', label: 'Uninstallation' },
  { key: 'recovery', label: 'Recovery / Rollback' },
  { key: 'recovery-kit', label: 'ATLAS Recovery Kit™' },
  { key: 'cleaner', label: 'ATLAS Cleaner™' },
  { key: 'formats', label: 'Product Format Management' },
  { key: 'browser', label: 'ATLAS Browser (NEW)' },
]

const PLAN_BULLETS = [
  'Up to 3 devices',
  '25 installs / month, per device',
  'TITAN CORE™',
  'Smart Storage',
  'Full install history',
  'Bulk installation',
  'Uninstall & Rollback',
  'Trash install file',
  'ATLAS CLEANER™',
  'ATLAS RECOVERY KIT™',
  'Cloud Backup',
  'Built-In Virus Scanner',
]

const REVIEWS: { quote: string; author: string }[] = [
  { quote: 'ATLAS changed the way my production is set up.', author: 'Marcus T., Producer' },
  { quote: 'This changed the game for me — I was able to recover my audio plugins!', author: 'Jordan K., Sound Engineer' },
  { quote: "Finally, an installer that doesn't leave a mess behind.", author: 'Dana R., Composer' },
  { quote: 'Recovery Kit saved my entire setup after a Mac migration.', author: 'Alicia M., Mix Engineer' },
  { quote: 'Takes the guesswork out of installing plugins across formats.', author: 'Theo B., Sound Designer' },
  { quote: 'My entire sample library migrated over without a single missing file.', author: 'Priya S., Audio Editor' },
  { quote: "Uninstalls are actually clean now — no more leftover junk in my plugin folders.", author: 'Chris L., Mastering Engineer' },
  { quote: 'Wish I had this years ago — it just works, every time.', author: 'Nina F., Beatmaker' },
]

const FAQS: { q: string; a: string }[] = [
  { q: 'What is ATLAS?', a: 'ATLAS is an autonomous installation application for macOS, designed to make installing software effortless, dependable, and refined.' },
  { q: 'What operating systems does ATLAS support?', a: 'ATLAS supports macOS 12 Monterey or later. Windows is Coming Soon.' },
  { q: 'Can ATLAS be shared?', a: 'ATLAS Subscribers can have up to 3 devices, each with its own 25-install-per-month allowance.' },
  { q: 'Can ATLAS fail?', a: 'ATLAS automates installation, but it cannot guarantee that every installer will work. Some installers may be unsupported, unusual, damaged, require interaction, or otherwise fail.' },
  { q: 'Can I use my own files?', a: 'Yes. ATLAS allows you to use your own files and installers.' },
]

export default function ATLASLaunchPage() {
  const { theme, setTheme } = useTheme()
  const [mounted, setMounted] = useState(false)
  useEffect(() => {
    setMounted(true)
    if (typeof window !== 'undefined' && window.matchMedia) {
      const prefersLight = window.matchMedia('(prefers-color-scheme: light)').matches
      setTheme(prefersLight ? 'light' : 'dark')
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])
  const isDark = !mounted || theme !== 'light'

  const [scrollY, setScrollY] = useState(0)
  const [selectedFeature, setSelectedFeature] = useState('install')
  const [faqOpen, setFaqOpen] = useState<Record<number, boolean>>({})
  const [supportOpen, setSupportOpen] = useState(false)
  const [logoDrag, setLogoDrag] = useState({ x: 0, y: 0 })
  const dragState = useRef<{ dragging: boolean; originX: number; originY: number }>({ dragging: false, originX: 0, originY: 0 })

  useEffect(() => {
    const onScroll = () => setScrollY(window.scrollY || 0)
    window.addEventListener('scroll', onScroll, { passive: true })
    return () => window.removeEventListener('scroll', onScroll)
  }, [])

  const onLogoDragMove = useCallback((e: MouseEvent) => {
    if (!dragState.current.dragging) return
    setLogoDrag({ x: e.clientX - dragState.current.originX, y: e.clientY - dragState.current.originY })
  }, [])
  const stopLogoDrag = useCallback(() => { dragState.current.dragging = false }, [])
  useEffect(() => {
    window.addEventListener('mousemove', onLogoDragMove)
    window.addEventListener('mouseup', stopLogoDrag)
    return () => {
      window.removeEventListener('mousemove', onLogoDragMove)
      window.removeEventListener('mouseup', stopLogoDrag)
    }
  }, [onLogoDragMove, stopLogoDrag])
  const startLogoDrag = (e: React.MouseEvent) => {
    e.preventDefault()
    dragState.current = { dragging: true, originX: e.clientX - logoDrag.x, originY: e.clientY - logoDrag.y }
  }

  const scrollBlur = Math.max(0, Math.min(16, scrollY / 18))
  const scrollFade = Math.max(0.15, 1 - scrollY / 400)

  const palette = isDark
    ? { bg: '#07080F', bgCard: '#111115', bgFooter: '#0B0B0D', text: '#E8ECFF', textMuted: '#525260', textSubtle: '#B8BEDC', border: 'rgba(232,236,255,0.08)' }
    : { bg: '#F2F4FF', bgCard: '#FFFFFF', bgFooter: '#E7EAFB', text: '#0D1035', textMuted: '#6B7299', textSubtle: '#3A3F66', border: 'rgba(13,16,53,0.08)' }

  const toggleBorder = isDark ? '#1E2240' : '#DDE2F5'
  const toggleIconColor = isDark ? 'rgba(255,255,255,0.38)' : '#4A5280'
  const shimmerGradient = isDark
    ? 'linear-gradient(100deg, #E8ECFF 40%, #3ECFB2 50%, #E8ECFF 60%)'
    : 'linear-gradient(100deg, #0D1035 40%, #3ECFB2 50%, #0D1035 60%)'

  const logoUrl = isDark ? '/launch/interlinked-logo-dark.png' : '/launch/interlinked-logo-light.png'
  const shotHeaderUrl = isDark ? '/launch/shot-header-dark.png' : '/launch/shot-header-light.png'
  const shotAppUrl = isDark ? '/launch/shot-app-dark.png' : '/launch/shot-app-light.png'

  const activeFeature = FEATURES[selectedFeature] ?? FEATURES.install

  const toggleFaq = (i: number) => setFaqOpen(prev => ({ ...prev, [i]: !prev[i] }))

  const tabStyle = (key: string): React.CSSProperties => {
    const active = selectedFeature === key
    return {
      fontFamily: "-apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif",
      fontSize: 14, fontWeight: 600, borderRadius: 20, padding: '9px 16px', cursor: 'pointer',
      transition: 'color 0.2s ease, border-color 0.2s ease, background 0.2s ease',
      color: active ? '#3ECFB2' : palette.textSubtle,
      border: active ? '1px solid rgba(62,207,178,0.5)' : `1px solid ${palette.border}`,
      background: active ? 'rgba(62,207,178,0.1)' : 'transparent',
    }
  }

  return (
    <main style={{ margin: 0, fontFamily: "'Inter', -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif", background: palette.bg }}>
      <style jsx global>{`
        @font-face { font-family: 'SF-Intellivised'; src: url('/fonts/SF-Intellivised.ttf') format('truetype'); }
        html { scroll-behavior: smooth; }
        .launch-btn { text-decoration: none; display: inline-flex; align-items: center; justify-content: center; cursor: pointer; border: none; }
        .launch-login-btn { display: inline-block; padding: 5px 12px; border-radius: 7px; background: none; font-size: 12px; font-weight: 500; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; cursor: pointer; letter-spacing: -0.01em; line-height: 20px; text-decoration: none; transition: border-color 0.2s ease, color 0.2s ease; }
        .launch-login-btn:hover { border-color: rgba(62,207,178,0.4) !important; color: #3ECFB2 !important; }
        .launch-theme-toggle { width: 30px; height: 30px; border-radius: 7px; background: none; padding: 0; flex-shrink: 0; display: flex; align-items: center; justify-content: center; cursor: pointer; transition: border-color 0.2s ease, color 0.2s ease, background 0.2s ease; }
        @keyframes launchThemeToggleJiggle {
          0%, 100% { transform: rotate(0deg); }
          15% { transform: rotate(-16deg); }
          30% { transform: rotate(13deg); }
          45% { transform: rotate(-10deg); }
          60% { transform: rotate(7deg); }
          75% { transform: rotate(-4deg); }
          90% { transform: rotate(2deg); }
        }
        .launch-theme-toggle-jiggle { animation: launchThemeToggleJiggle 0.7s ease-in-out 1.4s 1 both; }

        @keyframes launchHeroUnblur { from { filter: blur(10px); opacity: 0; } to { filter: blur(0); opacity: 1; } }
        @keyframes launchHeroFadeIn { from { opacity: 0; } to { opacity: 1; } }
        @keyframes launchHeroSlideLeft { from { opacity: 0; transform: translateX(-48px); } to { opacity: 1; transform: translateX(0); } }
        @keyframes launchHeroSlideRight { from { opacity: 0; transform: translateX(48px); } to { opacity: 1; transform: translateX(0); } }
        .launch-anim-logo-icon { animation: launchHeroUnblur 0.9s ease-out both; }
        .launch-anim-logo-text { animation: launchHeroFadeIn 1.3s ease-out both; animation-delay: 0.25s; }
        .launch-anim-logo-sub { animation: launchHeroFadeIn 1.1s ease-out both; animation-delay: 0.55s; }
        .launch-anim-shot-left { animation: launchHeroSlideLeft 0.8s cubic-bezier(0.16,1,0.3,1) both; animation-delay: 0.7s; }
        .launch-anim-shot-right { animation: launchHeroSlideRight 0.8s cubic-bezier(0.16,1,0.3,1) both; animation-delay: 0.85s; }

        @keyframes launchScrollCueBounce { 0%, 100% { transform: translateY(0); opacity: 0.55; } 50% { transform: translateY(6px); opacity: 1; } }
        .launch-scroll-cue { animation: launchScrollCueBounce 2.2s ease-in-out infinite; animation-delay: 1.6s; }

        @keyframes launchSubscribeShimmer { 0% { background-position: -150% 0; } 100% { background-position: 250% 0; } }
        .launch-shimmer-text { background-size: 250% 100%; background-position: -150% 0; -webkit-background-clip: text; background-clip: text; color: transparent; animation: launchSubscribeShimmer 8s linear infinite; animation-delay: 1s; }

        .launch-btn-primary { box-shadow: 0 8px 28px rgba(62,207,178,0.35), inset 0 1px 0 rgba(255,255,255,0.3); border: 1px solid rgba(255,255,255,0.22); transition: transform 0.2s ease, box-shadow 0.2s ease; }
        .launch-btn-primary:hover { transform: translateY(-2px); box-shadow: 0 12px 34px rgba(62,207,178,0.5), inset 0 1px 0 rgba(255,255,255,0.35); }
        .launch-btn-secondary { background: rgba(232,236,255,0.05); border: 1px solid rgba(232,236,255,0.16); backdrop-filter: blur(6px); box-shadow: inset 0 1px 0 rgba(255,255,255,0.06); transition: transform 0.2s ease, background 0.2s ease, border-color 0.2s ease; }
        .launch-btn-secondary:hover { transform: translateY(-2px); background: rgba(232,236,255,0.09); border-color: rgba(232,236,255,0.28); }
        .launch-os-req { font-family: 'Space Grotesk', -apple-system, sans-serif; }

        .launch-review-banner { width: 100%; }
        .launch-review-slide {
          position: absolute; top: 0; left: 0; right: 0;
          display: flex; flex-direction: column; align-items: center; gap: 4px;
          opacity: 0; animation: launchReviewCycle 36s ease-in-out infinite;
        }
        .launch-review-stars { color: #FFD469; font-size: 15px; letter-spacing: 2px; line-height: 1; }
        .launch-review-quote { color: var(--launch-review-text); font-style: italic; font-weight: 500; font-size: 18px; text-align: center; max-width: 560px; line-height: 1.35; transition: color 0.3s ease; }
        .launch-review-author { color: var(--launch-review-author); font-size: 12px; font-weight: 600; letter-spacing: 0.4px; margin-top: 1px; transition: color 0.3s ease; }
        @keyframes launchReviewCycle {
          0% { opacity: 0; transform: translateY(6px); }
          2% { opacity: 1; transform: translateY(0); }
          7% { opacity: 1; transform: translateY(0); }
          9% { opacity: 0; transform: translateY(-6px); }
          100% { opacity: 0; }
        }

        @keyframes launchFlowFileUp {
          0% { offset-distance: 0%; opacity: 0; }
          6% { opacity: 1; }
          92% { opacity: 1; }
          100% { offset-distance: 100%; opacity: 0; }
        }
        .launch-flow-file {
          position: absolute; width: 18px; height: 18px; border-radius: 5px;
          display: flex; align-items: center; justify-content: center;
          offset-path: path('M 160,280 C 112,230 222,190 160,145 C 108,105 224,62 160,25');
          animation: launchFlowFileUp 5.2s cubic-bezier(0.37,0,0.63,1) infinite;
        }
        @keyframes launchScreenArrivalGlow { 0%, 100% { opacity: 0.4; } 50% { opacity: 1; } }
        @keyframes launchScreenArrivalFlash { 0%, 100% { opacity: 0.5; } 50% { opacity: 1; } }
        .launch-screen-glow { animation: launchScreenArrivalGlow 0.87s ease-in-out infinite; }
        .launch-screen-glow-fill { animation: launchScreenArrivalFlash 0.87s ease-in-out infinite; }
        .launch-faq-item { border-bottom: 1px solid var(--launch-faq-border, rgba(232,236,255,0.08)); }
        .launch-faq-q { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; font-size: 14px; font-weight: 600; display: flex; align-items: center; justify-content: space-between; gap: 12px; padding: 10px 2px; cursor: pointer; list-style: none; user-select: none; background: none; border: none; width: 100%; text-align: left; }
        .launch-faq-q:focus-visible { outline: 2px solid #3ECFB2; outline-offset: 2px; border-radius: 4px; }
        .launch-faq-chevron { flex-shrink: 0; transition: transform 0.5s cubic-bezier(0.16,1,0.3,1); }
        .launch-faq-a { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; font-size: 13px; line-height: 1.6; padding: 0 2px 12px; margin: 0; }

        @media (min-width: 681px) {
          html { zoom: 1; }
        }

        @media (max-width: 680px) {
          .launch-hero-section { height: auto !important; min-height: 100vh !important; max-height: none !important; overflow: visible !important; padding: 56px 20px 40px !important; }
          .launch-hero-top, .launch-hero-bottom { transform: none !important; }
          .launch-hero-logo-icon { width: 64px !important; height: 64px !important; }
          .launch-hero-logo-text { font-size: 34px !important; letter-spacing: 14px !important; padding-left: 14px !important; }
          .launch-hero-line1 { font-size: 18px !important; }
          .launch-hero-subscribe { font-size: 30px !important; }
          .launch-hero-cta-row { flex-direction: column !important; width: 100%; max-width: 260px; }
          .launch-hero-cta-row .launch-btn { width: 100%; }
          .launch-hero-shots, .launch-hero-visual { display: none !important; }
          .launch-section-pad { padding-left: 20px !important; padding-right: 20px !important; }
          .launch-plan-grid { grid-template-columns: repeat(2, 1fr) !important; }
        }

        /* Tablet range (iPad portrait/landscape, Surface, etc.): the hero's
           screenshot mockups and visualizer are absolutely positioned at
           desktop-only pixel offsets and collide with the centered title
           text once the viewport is too narrow to fit all three side by
           side, well before the 680px mobile breakpoint kicks in. Hide them
           here the same way mobile does, but keep desktop font sizing since
           there's still plenty of width for it. */
        @media (min-width: 681px) and (max-width: 1300px) {
          .launch-hero-shots, .launch-hero-visual { display: none !important; }
        }

        @media (max-width: 320px) {
          .launch-hero-logo-icon { width: 52px !important; height: 52px !important; }
          .launch-hero-logo-text { font-size: 26px !important; letter-spacing: 10px !important; padding-left: 10px !important; }
          .launch-hero-subscribe { font-size: 24px !important; }
          .launch-plan-grid { grid-template-columns: 1fr !important; }
        }
      `}</style>

      {/* Top-right bar: Login + Dark/Light toggle */}
      <div style={{ position: 'fixed', top: 16, right: 16, zIndex: 50, display: 'flex', alignItems: 'center', gap: 8 }}>
        <a href="https://www.interlinked.digital/auth/login" className="launch-login-btn" style={{ border: `1px solid ${toggleBorder}`, color: toggleIconColor }}>Login</a>
        <button
          className="launch-theme-toggle launch-theme-toggle-jiggle"
          onClick={() => setTheme(isDark ? 'light' : 'dark')}
          title={isDark ? 'Switch to light mode' : 'Switch to dark mode'}
          style={{ border: `1px solid ${toggleBorder}`, color: toggleIconColor }}
        >
          {isDark ? (
            <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><circle cx="12" cy="12" r="5" /><line x1="12" y1="1" x2="12" y2="3" /><line x1="12" y1="21" x2="12" y2="23" /><line x1="4.22" y1="4.22" x2="5.64" y2="5.64" /><line x1="18.36" y1="18.36" x2="19.78" y2="19.78" /><line x1="1" y1="12" x2="3" y2="12" /><line x1="21" y1="12" x2="23" y2="12" /><line x1="4.22" y1="19.78" x2="5.64" y2="18.36" /><line x1="18.36" y1="5.64" x2="19.78" y2="4.22" /></svg>
          ) : (
            <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z" /></svg>
          )}
        </button>
      </div>

      {/* ================= HERO ================= */}
      <div className="launch-hero-section" style={{ width: '100%', height: 886, minHeight: 640, maxHeight: 980, background: palette.bg, transition: 'background 0.3s ease', boxSizing: 'border-box', padding: '24px 48px', display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', position: 'relative', overflow: 'hidden', left: 0, top: -26 }}>

        <div className="launch-hero-top" style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 28, transform: 'translateY(-110px)' }}>

          <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 12, transform: 'translateY(26px)' }}>
            <img className="launch-anim-logo-icon launch-hero-logo-icon" src="/launch/atlas-logo-icon.png" alt="ATLAS" style={{ width: 96, height: 96, objectFit: 'contain', display: 'block' }} />
            <div className="launch-anim-logo-text launch-hero-logo-text" style={{ fontFamily: "'SF-Intellivised', -apple-system, sans-serif", fontSize: 60, fontWeight: 'normal', letterSpacing: 34, color: palette.text, textTransform: 'uppercase', paddingLeft: 34, lineHeight: 1, transition: 'color 0.3s ease' }}>ATLAS</div>
            <div className="launch-anim-logo-sub" onMouseDown={startLogoDrag} style={{ display: 'flex', alignItems: 'center', gap: 8, marginTop: -26, transform: `translate(${logoDrag.x}px, ${logoDrag.y}px)`, cursor: dragState.current.dragging ? 'grabbing' : 'grab', userSelect: 'none', touchAction: 'none' }}>
              <span style={{ fontStyle: 'italic', fontSize: 14, color: palette.textMuted }}>by</span>
              <img src={logoUrl} alt="InterLinked" draggable={false} style={{ width: 130, height: 'auto', display: 'block', opacity: 0.85, pointerEvents: 'none' }} />
            </div>
          </div>

        <div className="launch-hero-bottom" style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 28, transform: 'translateY(145px)' }}>

          <h1 style={{ textAlign: 'center', margin: 0, fontWeight: 'normal' }}>
            <div className="launch-hero-line1" style={{ fontSize: 30, fontWeight: 700, color: palette.text, transition: 'color 0.3s ease', marginTop: 24 }}>is officially <span style={{ fontStyle: 'italic', fontWeight: 600 }}>here</span>.</div>
            <div className="launch-shimmer-text launch-hero-subscribe" style={{ fontSize: 56, fontWeight: 800, marginTop: -10, letterSpacing: -0.5, display: 'inline-block', backgroundImage: shimmerGradient }}>Subscribe Now.</div>
          </h1>

          <div className="launch-hero-cta-row" style={{ display: 'flex', gap: 16, zIndex: 5, alignItems: 'flex-start' }}>
            <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 10 }}>
              <a href="/atlas/plans" className="launch-btn launch-btn-primary" style={{ background: '#3ECFB2', color: palette.text, fontWeight: 800, fontSize: 16, padding: '16px 32px', borderRadius: 999, gap: 8, transition: 'color 0.3s ease' }}>
                <img src="/launch/apple-logo.png" alt="" style={{ width: 22, height: 22, objectFit: 'contain', display: 'block' }} />
                Get ATLAS V1
              </a>
              <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 3 }}>
                <div className="launch-os-req" style={{ display: 'flex', alignItems: 'center', gap: 6, fontSize: 12, fontWeight: 500, color: palette.textMuted, letterSpacing: 1.6 }}>
                  <img src="/launch/apple-logo.png" alt="" style={{ width: 15, height: 15, objectFit: 'contain', opacity: 0.8 }} />
                  macOS Monterey or Above.
                </div>
                <div className="launch-os-req" style={{ display: 'flex', alignItems: 'center', gap: 6, fontSize: 12, fontWeight: 500, color: palette.textMuted, letterSpacing: 1.6, opacity: 0.7 }}>
                  <img src="/launch/windows-logo.png" alt="" style={{ width: 16, height: 16, objectFit: 'contain', opacity: 0.85 }} />
                  Windows Version Coming Soon.
                </div>
              </div>
            </div>
            <a href="#demo" className="launch-btn launch-btn-secondary" style={{ color: palette.text, fontWeight: 700, fontSize: 16, padding: '16px 32px', borderRadius: 999, border: `1px solid ${palette.border}` }}>
              View Demo
            </a>
          </div>

          <div className="launch-review-banner" style={{ position: 'relative', height: 54, display: 'flex', alignItems: 'center', justifyContent: 'center', marginTop: 22, ['--launch-review-text' as any]: palette.text, ['--launch-review-author' as any]: palette.textMuted }}>
            {REVIEWS.map((r, i) => (
              <div className="launch-review-slide" key={r.author} style={{ animationDelay: `${i * 4.5}s` }}>
                <div className="launch-review-stars">★★★★★</div>
                <div className="launch-review-quote">“{r.quote}”</div>
                <div className="launch-review-author">— {r.author}</div>
              </div>
            ))}
          </div>

        </div>
        </div>

        <div className="launch-hero-shots" style={{ position: 'absolute', left: 40, top: 267, width: 422, height: 378 }}>
          <div className="launch-anim-shot-left" style={{ position: 'absolute', top: 0, left: 0, width: 360, height: 260, borderRadius: 10, boxShadow: '0 30px 60px rgba(0,0,0,0.35)', overflow: 'hidden', border: `1px solid ${palette.border}` }}>
            <img src={shotHeaderUrl} alt="ATLAS splash screen" style={{ width: '100%', height: '100%', objectFit: 'cover', display: 'block' }} />
          </div>
          <div className="launch-anim-shot-right" style={{ position: 'absolute', top: 140, left: 90, width: 330, height: 220, borderRadius: 10, boxShadow: '0 30px 60px rgba(0,0,0,0.45)', overflow: 'hidden', border: `1px solid ${palette.border}` }}>
            <img src={shotAppUrl} alt="ATLAS drop-files window" style={{ width: '100%', height: '100%', objectFit: 'cover', display: 'block' }} />
          </div>
        </div>

        <div className="launch-hero-visual" style={{ position: 'absolute', right: 50, top: 310, width: 320, height: 350, filter: `blur(${scrollBlur * 0.35}px)`, opacity: scrollFade, transition: 'filter 0.05s linear, opacity 0.05s linear', transform: 'scale(1.45)', transformOrigin: 'center', pointerEvents: 'none' }}>

          {/* Mac screen (top) — glows on each file arrival */}
          <div style={{ position: 'absolute', top: 0, left: '50%', transform: 'translateX(-50%)', width: 150, height: 108 }}>
            <div className="launch-screen-glow" style={{ position: 'absolute', inset: -40, borderRadius: '50%', background: 'radial-gradient(circle, rgba(62,207,178,0.75) 0%, rgba(62,207,178,0.25) 45%, transparent 72%)', filter: 'blur(18px)' }} />
            <div style={{ position: 'absolute', top: 0, left: 0, width: 150, height: 96, borderRadius: 10, border: `2px solid ${palette.textMuted}`, background: '#0C0C12' }}>
              <div className="launch-screen-glow-fill" style={{ position: 'absolute', inset: 3, borderRadius: 4, background: 'radial-gradient(circle at 50% 60%, rgba(62,207,178,0.5), rgba(62,207,178,0.05) 70%)' }} />
            </div>
            <div style={{ position: 'absolute', top: 96, left: '50%', transform: 'translateX(-50%)', width: 44, height: 9, background: palette.textMuted, borderRadius: '0 0 3px 3px' }} />
            <div style={{ position: 'absolute', top: 105, left: '50%', transform: 'translateX(-50%)', width: 68, height: 4, background: palette.textMuted, borderRadius: 2, opacity: 0.8 }} />
          </div>

          {/* ATLAS app window (bottom) — files leave from here */}
          <div style={{ position: 'absolute', bottom: 0, left: '50%', transform: 'translateX(-50%)', width: 132, height: 88, borderRadius: 9, border: `1px solid ${palette.border}`, background: palette.bgCard, boxShadow: '0 16px 36px rgba(0,0,0,0.25)' }}>
            <div style={{ position: 'absolute', top: 0, left: 0, right: 0, height: 20, borderBottom: `1px solid ${palette.border}`, display: 'flex', alignItems: 'center', gap: 4, padding: '0 8px', boxSizing: 'border-box' }}>
              <div style={{ width: 6, height: 6, borderRadius: '50%', background: '#E05555' }} />
              <div style={{ width: 6, height: 6, borderRadius: '50%', background: '#E0B155' }} />
              <div style={{ width: 6, height: 6, borderRadius: '50%', background: '#55C27A' }} />
            </div>
            <img src="/launch/atlas-logo-icon.png" alt="" style={{ position: 'absolute', top: 38, left: '50%', transform: 'translateX(-50%)', width: 30, height: 30, objectFit: 'contain', opacity: 0.9 }} />
          </div>

          {/* Ambient vertical light column connecting app to screen */}
          <div style={{ position: 'absolute', bottom: 100, left: '50%', transform: 'translateX(-50%)', width: 2, height: 154, background: 'linear-gradient(to top, rgba(62,207,178,0.3), rgba(94,106,210,0.12) 50%, transparent)', filter: 'blur(3px)' }} />

          {/* Files leaving the app — varied audio-software/file icon chips, each
              traveling the same smooth curved path up to the screen. */}
          <div className="launch-flow-file" style={{ animationDelay: '0s', background: '#3ECFB2' }}>
            <svg viewBox="0 0 20 20"><path d="M4 13V9 M8 15V5 M12 16V4 M16 12V10" stroke="#06211D" strokeWidth={2} strokeLinecap="round" /></svg>
          </div>
          <div className="launch-flow-file" style={{ animationDelay: '-0.87s', background: '#5E6AD2' }}>
            <svg viewBox="0 0 20 20"><circle cx="7" cy="14" r="2.4" fill="#fff" /><circle cx="15" cy="11" r="2.4" fill="#fff" /><path d="M9.4 14V5.5L17.4 4V11" stroke="#fff" strokeWidth={1.6} fill="none" strokeLinecap="round" /></svg>
          </div>
          <div className="launch-flow-file" style={{ animationDelay: '-1.73s', background: '#F0A030' }}>
            <svg viewBox="0 0 20 20"><circle cx="10" cy="10" r="6.5" fill="none" stroke="#3A2600" strokeWidth={1.8} /><line x1="10" y1="10" x2="10" y2="5" stroke="#3A2600" strokeWidth={1.8} strokeLinecap="round" /></svg>
          </div>
          <div className="launch-flow-file" style={{ animationDelay: '-2.6s', background: '#E8ECFF' }}>
            <svg viewBox="0 0 20 20"><path d="M5 2.5h7l3 3V17.5H5z" fill="none" stroke="#20244A" strokeWidth={1.6} strokeLinejoin="round" /><path d="M12 2.5v3h3" fill="none" stroke="#20244A" strokeWidth={1.6} strokeLinejoin="round" /></svg>
          </div>
          <div className="launch-flow-file" style={{ animationDelay: '-3.47s', background: '#E05555' }}>
            <svg viewBox="0 0 20 20"><circle cx="10" cy="5.5" r="2.4" fill="#fff" /><path d="M10 8v5 M6.5 17l2-4h3l2 4" stroke="#fff" strokeWidth={1.7} strokeLinecap="round" fill="none" /></svg>
          </div>
          <div className="launch-flow-file" style={{ animationDelay: '-4.33s', background: '#3ECFB2' }}>
            <svg viewBox="0 0 20 20"><rect x="3" y="5" width="14" height="10" rx="1.5" fill="none" stroke="#06211D" strokeWidth={1.6} /><path d="M3 8h14" stroke="#06211D" strokeWidth={1.6} /></svg>
          </div>
        </div>

        <div style={{ position: 'absolute', left: 0, right: 0, bottom: 0, height: 180, background: `linear-gradient(to bottom, transparent, ${palette.bg})`, transition: 'background 0.3s ease', pointerEvents: 'none', zIndex: 25 }} />

        <div style={{ position: 'absolute', left: 0, right: 0, bottom: 4, zIndex: 30, display: 'flex', justifyContent: 'center', pointerEvents: 'none' }}>
          <a href="#demo" className="launch-scroll-cue" style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 4, textDecoration: 'none', cursor: 'pointer', pointerEvents: 'auto' }}>
            <span style={{ fontSize: 10, fontWeight: 600, letterSpacing: 1.5, textTransform: 'uppercase', color: palette.textMuted }}>Scroll to explore</span>
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke={palette.textMuted} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><polyline points="6 9 12 15 18 9" /></svg>
          </a>
        </div>
      </div>

      {/* ================= DEMO ================= */}
      <div id="demo" className="launch-section-pad" style={{ width: '100%', background: palette.bg, transition: 'background 0.3s ease', padding: '72px 48px', boxSizing: 'border-box', display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 20 }}>
        <div style={{ fontSize: 10, fontWeight: 700, letterSpacing: 3, textTransform: 'uppercase', color: '#3ECFB2' }}>DEMO</div>
        <h2 style={{ fontSize: 26, fontWeight: 700, letterSpacing: '-0.035em', color: palette.text, textAlign: 'center', margin: 0 }}>See ATLAS in Action</h2>
        <p style={{ fontSize: 14, color: palette.textMuted, textAlign: 'center', maxWidth: 480, margin: 0 }}>A closer look at ATLAS&apos;s Features Overview — see installation, uninstallation, rollback, and more in action.</p>
        <div style={{ width: '100%', maxWidth: 680, height: 1, background: palette.border, margin: '8px auto' }} />
        <div style={{ width: '100%', maxWidth: 760, aspectRatio: '16/9', background: palette.bgCard, borderRadius: 14, border: `1px solid ${palette.border}`, overflow: 'hidden' }}>
          <iframe src="https://www.youtube.com/embed/q2W9QkBKz2c?rel=0&modestbranding=1&color=white&fs=0" title="ATLAS Demo" allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture" allowFullScreen style={{ width: '100%', height: '100%', border: 'none', display: 'block' }} />
        </div>
      </div>

      {/* ================= FEATURES / PLAN ================= */}
      <div className="launch-section-pad" style={{ width: '100%', background: palette.bg, transition: 'background 0.3s ease', padding: '24px 48px 72px', boxSizing: 'border-box', display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 20 }}>
        <h2 style={{ fontFamily: "-apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif", fontSize: 34, fontWeight: 700, letterSpacing: '-0.02em', color: '#3ECFB2', textAlign: 'center', margin: 0 }}>Features</h2>
        <p style={{ fontFamily: "-apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif", fontSize: 15, color: palette.textSubtle, textAlign: 'center', margin: '-8px 0 0' }}>Select a feature to see what it does.</p>

        <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8, justifyContent: 'center', width: '100%', maxWidth: 760 }}>
          {FEATURE_TABS.map(tab => (
            <button key={tab.key} onClick={() => setSelectedFeature(tab.key)} style={tabStyle(tab.key)}>{tab.label}</button>
          ))}
        </div>

        <div style={{ fontFamily: "-apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif", fontSize: 16, lineHeight: 1.6, color: palette.text, background: 'rgba(62,207,178,0.06)', border: '1px solid rgba(62,207,178,0.18)', borderRadius: 14, padding: 16, width: '100%', maxWidth: 760, textAlign: 'left', boxSizing: 'border-box' }}>
          <span style={{ display: 'block', fontWeight: 700, color: '#3ECFB2', marginBottom: 6, fontSize: 16 }}>{activeFeature.title}</span>
          {activeFeature.body}
        </div>

        <h3 style={{ fontFamily: "-apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif", fontSize: 18, fontWeight: 700, color: palette.text, textAlign: 'center', margin: '4px 0 0' }}>Everything in the ATLAS plan</h3>
        <div className="launch-plan-grid" style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: '18px 10px', width: '100%', maxWidth: 760, justifyContent: 'center' }}>
          {PLAN_BULLETS.map(label => (
            <div key={label} style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 6, textAlign: 'center', fontFamily: "-apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif", fontSize: 14, lineHeight: 1.35, color: palette.textSubtle }}>
              <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="#3ECFB2" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round"><polyline points="20 6 9 17 4 12" /></svg>
              <span>{label}</span>
            </div>
          ))}
        </div>
      </div>

      {/* ================= FAQ ================= */}
      <div className="launch-section-pad" style={{ width: '100%', background: palette.bg, transition: 'background 0.3s ease', padding: '24px 48px 80px', boxSizing: 'border-box', display: 'flex', flexDirection: 'column', alignItems: 'center', ['--launch-faq-border' as any]: palette.border }}>
        <div style={{ width: '100%', maxWidth: 600 }}>
          <h2 style={{ fontFamily: "-apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif", fontSize: 17, fontWeight: 700, color: '#3ECFB2', textAlign: 'center', margin: '0 0 6px' }}>FAQ</h2>

          {FAQS.map((item, idx) => {
            const i = idx + 1
            const open = !!faqOpen[i]
            return (
              <div className="launch-faq-item" key={i}>
                <button className="launch-faq-q" onClick={() => toggleFaq(i)} style={{ color: palette.text }}>
                  <span>{item.q}</span>
                  <svg className="launch-faq-chevron" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round" style={{ color: palette.textSubtle, transform: open ? 'rotate(180deg)' : 'rotate(0deg)' }}><polyline points="6 9 12 15 18 9" /></svg>
                </button>
                <div style={{ display: 'grid', gridTemplateRows: open ? '1fr' : '0fr', transition: 'grid-template-rows 0.5s cubic-bezier(0.16,1,0.3,1)' }}>
                  <div style={{ overflow: 'hidden' }}>
                    <p className="launch-faq-a" style={{ color: palette.textSubtle, opacity: open ? 1 : 0, transition: `opacity 0.35s ease ${open ? '0.15s' : '0s'}` }}>{item.a}</p>
                  </div>
                </div>
              </div>
            )
          })}
        </div>
      </div>

      {/* ================= FOOTER ================= */}
      <div className="launch-section-pad" style={{ width: '100%', background: palette.bgFooter, transition: 'background 0.3s ease', padding: '48px 48px 32px', boxSizing: 'border-box', display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 24 }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
          <img src="/launch/atlas-logo-icon.png" alt="ATLAS" style={{ width: 28, height: 28, objectFit: 'contain' }} />
          <span style={{ fontFamily: "'SF-Intellivised', -apple-system, sans-serif", fontSize: 16, letterSpacing: 6, color: palette.text, textTransform: 'uppercase' }}>ATLAS</span>
        </div>

        <div style={{ display: 'flex', alignItems: 'center', gap: 14 }}>
          <a href="mailto:interlinked.digital@gmail.com" aria-label="Email InterLinked" className="launch-btn" style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', width: 36, height: 36, borderRadius: '50%', border: `1px solid ${palette.border}`, color: palette.textSubtle }}>
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><rect x="2" y="4" width="20" height="16" rx="2" /><path d="m22 7-8.97 5.7a1.94 1.94 0 0 1-2.06 0L2 7" /></svg>
          </a>
          <a href="https://www.instagram.com/interlinked.___" aria-label="InterLinked on Instagram" target="_blank" rel="noopener" className="launch-btn" style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', width: 36, height: 36, borderRadius: '50%', border: `1px solid ${palette.border}`, color: palette.textSubtle }}>
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><rect x="2" y="2" width="20" height="20" rx="5" /><path d="M16 11.37A4 4 0 1 1 12.63 8 4 4 0 0 1 16 11.37z" /><line x1="17.5" y1="6.5" x2="17.5" y2="6.5" /></svg>
          </a>
        </div>

        <div style={{ display: 'flex', gap: 28, fontSize: 13, fontWeight: 500, flexWrap: 'wrap', justifyContent: 'center' }}>
          <a href="https://www.interlinked.digital" className="launch-btn" style={{ color: palette.textSubtle }}>InterLinked Digital</a>
          <a href="https://www.interlinked.digital/atlas/terms" className="launch-btn" style={{ color: palette.textSubtle }}>Terms of Service</a>
          <a href="https://www.interlinked.digital/atlas/privacy" className="launch-btn" style={{ color: palette.textSubtle }}>Privacy</a>
          <button onClick={() => setSupportOpen(true)} className="launch-btn" style={{ color: palette.textSubtle, cursor: 'pointer', background: 'none', border: 'none', font: 'inherit' }}>Support</button>
        </div>
        <div style={{ fontSize: 11, color: palette.textMuted }}>© 2026 InterLinked Digital. All rights reserved.</div>
      </div>

      {/* Support modal */}
      {supportOpen && (
        <div style={{ position: 'fixed', inset: 0, background: 'rgba(0,0,0,0.5)', display: 'flex', alignItems: 'center', justifyContent: 'center', zIndex: 100 }} onClick={() => setSupportOpen(false)}>
          <div style={{ width: 420, background: '#141416', borderRadius: 16, padding: 28, boxSizing: 'border-box', border: '1px solid #26262A', boxShadow: '0 40px 80px rgba(0,0,0,0.5)' }} onClick={e => e.stopPropagation()}>
            <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 18 }}>
              <div style={{ fontSize: 18, fontWeight: 700, color: '#F2F2F0' }}>Contact Support</div>
              <span onClick={() => setSupportOpen(false)} style={{ cursor: 'pointer', color: '#8A8A96', fontSize: 20, lineHeight: 1 }}>×</span>
            </div>
            <div style={{ fontSize: 12, color: '#8A8A96', marginBottom: 6, fontWeight: 600 }}>ISSUE TYPE</div>
            <select style={{ width: '100%', background: '#0E0E10', border: '1px solid #2A2A2E', borderRadius: 8, padding: '10px 12px', color: '#D6D6DA', fontSize: 13, marginBottom: 14, boxSizing: 'border-box' }}>
              <option>Installation Issue</option>
              <option>Billing Question</option>
              <option>Account Access</option>
              <option>General</option>
            </select>
            <div style={{ fontSize: 12, color: '#8A8A96', marginBottom: 6, fontWeight: 600 }}>MESSAGE</div>
            <textarea placeholder="How can we help?" style={{ width: '100%', height: 100, background: '#0E0E10', border: '1px solid #2A2A2E', borderRadius: 8, padding: '10px 12px', color: '#D6D6DA', fontSize: 13, boxSizing: 'border-box', resize: 'none', fontFamily: 'inherit' }} />
            <button style={{ marginTop: 16, width: '100%', background: '#3ECFB2', color: '#06211D', fontWeight: 800, fontSize: 14, padding: 12, borderRadius: 8, border: 'none', cursor: 'pointer' }}>Send Message</button>
            <div style={{ marginTop: 12, fontSize: 11, color: '#5A5A62', textAlign: 'center' }}>Or email us directly at <span style={{ color: '#8A8A96' }}>interlinked.digital@gmail.com</span></div>
          </div>
        </div>
      )}
    </main>
  )
}
