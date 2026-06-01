import type { Metadata } from "next"

export const metadata: Metadata = {
  title: "InterLinked — ATLAS",
  description: "ATLAS by InterLinked — Smart installation platform for macOS",
}

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body style={{ margin: 0, padding: 0, background: "#0D0F1A" }}>
        {children}
      </body>
    </html>
  )
}
