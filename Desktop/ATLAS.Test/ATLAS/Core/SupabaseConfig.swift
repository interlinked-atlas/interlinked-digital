import Foundation

/// Paste your Supabase credentials here.
/// Found in: supabase.com → your project → Project Settings → API
enum SupabaseConfig {
    static let projectURL = "https://bmbmzytnpsntgzmutikp.supabase.co"
    static let anonKey    = "sb_publishable_5bSFk89-GwX9CUfIDjpK8g_52ZWa2Fa"

    // Subscription checkout — routes through the website for a single checkout path
    static let stripeCheckoutURL = "https://www.interlinked.digital/atlas/checkout?plan=atlas"
}
