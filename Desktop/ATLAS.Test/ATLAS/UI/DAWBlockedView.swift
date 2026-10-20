import SwiftUI

/// Shown when the DAW gate identifies a blocked DAW installer during scanning.
/// Used by both the TITAN path (via .dawBlocked phase) and the normal scan path
/// (via ScanResultView branching on ScanResult.blockedDAWName).
struct DAWBlockedView: View {
    let dawName: String
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 0)

            Image(systemName: "circle.slash")
                .font(.system(size: 36, weight: .light))
                .foregroundColor(Color(hex: "#E05555"))

            VStack(spacing: 8) {
                Text("Unable to Install \(dawName)")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Color(hex: "#C8D0F0"))
                    .multilineTextAlignment(.center)

                Text("\(dawName) cannot be installed with ATLAS.")
                    .font(.system(size: 12))
                    .foregroundColor(Color(hex: "#8A92BC"))
                    .multilineTextAlignment(.center)

                Text("ATLAS does not support installing this DAW. Drop a plugin, sample library, or compatible installer instead.")
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "#5A6080"))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.top, 2)
            }

            Button(action: onBack) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Return Home")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundColor(Color(hex: "#C8D0F0"))
                .padding(.horizontal, 24)
                .padding(.vertical, 9)
                .background(Color(hex: "#1A1D2E"))
                .cornerRadius(9)
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(Color(hex: "#2E3150"), lineWidth: 0.75)
                )
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}
