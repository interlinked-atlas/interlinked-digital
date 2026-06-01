"use client"
import { useEffect } from "react"

export default function Home() {
  return (
    <main style={{
      minHeight: "100vh",
      background: "#0D0F1A",
      display: "flex",
      alignItems: "center",
      justifyContent: "center",
      fontFamily: "-apple-system, BlinkMacSystemFont, sans-serif",
      color: "#E8ECFF",
    }}>
      <div style={{ textAlign: "center", padding: "24px" }}>
        <h1 style={{ fontSize: "42px", fontWeight: 700, letterSpacing: "10px", margin: "0 0 8px" }}>
          ATLAS
        </h1>
        <p style={{ color: "#6B7399", fontSize: "14px", marginBottom: "32px" }}>
          Smart installation platform for macOS · by InterLinked
        </p>
        <a href="/atlas" style={{
          display: "inline-block",
          background: "linear-gradient(135deg, #3ECFB2, #2ABEAA)",
          color: "#0D0F1A",
          padding: "12px 28px",
          borderRadius: "10px",
          fontWeight: 700,
          fontSize: "14px",
          textDecoration: "none",
          letterSpacing: "0.3px",
        }}>
          Get Started — Create Account
        </a>
        <p style={{ color: "#3A3F60", fontSize: "11px", marginTop: "48px" }}>
          InterLinked© · All rights reserved
        </p>
      </div>
    </main>
  )
}
