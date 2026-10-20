import SwiftUI
import AppKit

// Animated star icon for the menu bar
struct MenuBarIcon: View {
    @State private var pulse = false

    var body: some View {
        Image(systemName: "sparkle")
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(Color(hex: "#3ECFB2"))
            .scaleEffect(pulse ? 1.15 : 1.0)
            .animation(
                .easeInOut(duration: 1.2).repeatForever(autoreverses: true),
                value: pulse)
            .onAppear { pulse = true }
    }
}

// Menu bar dropdown content
struct MenuBarContent: View {
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "sparkle")
                    .foregroundColor(Color(hex: "#3ECFB2"))
                Text("ATLAS")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color(hex: "#F0F2FF"))
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()
                .background(Color(hex: "#1E2132"))

            Button("Open ATLAS") {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.windows.first?.makeKeyAndOrderFront(nil)
            }
            .buttonStyle(MenuBarButtonStyle())

            Button("View Logs") {
                InstallLogger.openLogsInFinder()
            }
            .buttonStyle(MenuBarButtonStyle())

            Divider()
                .background(Color(hex: "#1E2132"))

            Button("Quit ATLAS") {
                NSApp.terminate(nil)
            }
            .buttonStyle(MenuBarButtonStyle())
        }
        .frame(width: 200)
        .background(Color(hex: "#0A0D1C"))
    }
}

struct MenuBarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13))
            .foregroundColor(Color(hex: "#F0F2FF"))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(configuration.isPressed
                ? Color(hex: "#1E2132")
                : Color.clear)
    }
}

// Hex color helper
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17,
                           (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16,
                           int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF,
                           int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
