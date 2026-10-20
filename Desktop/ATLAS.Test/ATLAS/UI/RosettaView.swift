import SwiftUI

// RosettaView shows after a plugin install on Apple Silicon Macs.
// Lets user enable Rosetta per-DAW with one tap.
// Only shown when ATLAS detects Apple Silicon.

struct RosettaView: View {
    @ObservedObject var logger: Logger
    let onDismiss: () -> Void
    @ObservedObject private var langMgr = LanguageManager.shared

    @State private var daws: [DAWInfo] = []
    @State private var scanning = true
    @State private var applying = false
    @State private var showNoThanks = false
    @State private var selectedIDs: Set<UUID> = []
    @State private var done = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {

            // Header
            HStack(spacing: 12) {
                Image(systemName: "cpu")
                    .font(.title2)
                    .foregroundColor(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L(.appleSiliconDetected))
                        .font(.headline)
                    Text(L(.enableRosettaQ))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(16)
            .background(Color.orange.opacity(0.08))
            .cornerRadius(10)

            if scanning {
                HStack(spacing: 10) {
                    ProgressView().scaleEffect(0.8)
                    Text(L(.scanningDAWs))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 4)
            } else if daws.isEmpty {
                Text(L(.noDAWsFound))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 4)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L(.selectDAWsRosetta))
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 4)

                    ForEach(daws) { daw in
                        DAWRowView(
                            daw: daw,
                            isSelected: selectedIDs.contains(daw.id)
                        ) {
                            if selectedIDs.contains(daw.id) {
                                selectedIDs.remove(daw.id)
                            } else {
                                selectedIDs.insert(daw.id)
                            }
                        }
                    }
                }
            }

            if done {
                Label(L(.rosettaEnabledMsg),
                      systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(.green)
                    .padding(10)
                    .background(Color.green.opacity(0.08))
                    .cornerRadius(8)
            }

            // Action buttons
            HStack(spacing: 12) {
                Button(L(.noThanks)) {
                    showNoThanks = true
                }
                .buttonStyle(.bordered)

                Spacer()

                if !daws.isEmpty && !done {
                    Button(applying ? L(.applying) : L(.enableRosettaAction)) {
                        applyRosetta()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedIDs.isEmpty || applying)
                }

                if done {
                    Button(L(.done)) { onDismiss() }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(20)
        .background(Color.secondary.opacity(0.04))
        .cornerRadius(12)
        .alert("No problem!", isPresented: $showNoThanks) {
            Button("Got it", role: .cancel) { onDismiss() }
        } message: {
            Text("If plugins fail to load, appear in demo mode, or show errors in your DAW, enabling Rosetta may be required. You can always run ATLAS again to enable it later.")
        }
        .onAppear {
            // Only show on Apple Silicon
            guard RosettaEngine.isAppleSilicon else {
                onDismiss()
                return
            }
            Task {
                let found = RosettaEngine.scanForDAWs()
                await MainActor.run {
                    daws = found
                    // Pre-select DAWs that don't already have Rosetta enabled
                    selectedIDs = Set(found.filter { !$0.isRosettaEnabled }.map { $0.id })
                    scanning = false
                }
            }
        }
    }

    private func applyRosetta() {
        guard let password = KeychainManager.loadPassword() else { return }
        applying = true

        Task {
            // Install Rosetta if needed
            if !RosettaEngine.isRosettaInstalled {
                logger.log("Rosetta 2 not installed — installing...")
                let installed = await RosettaEngine.installRosetta(logger: logger)
                if !installed {
                    await MainActor.run { applying = false }
                    return
                }
            }

            // Enable for selected DAWs
            for daw in daws where selectedIDs.contains(daw.id) {
                _ = await RosettaEngine.enableRosetta(
                    appPath: daw.bundlePath,
                    password: password,
                    logger: logger
                )
            }

            await MainActor.run {
                applying = false
                done = true
            }
        }
    }
}

struct DAWRowView: View {
    let daw: DAWInfo
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: daw.icon)
                    .foregroundColor(.secondary)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(daw.name)
                        .font(.subheadline)
                        .foregroundColor(.primary)
                    Text(URL(fileURLWithPath: daw.bundlePath).lastPathComponent)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if daw.isRosettaEnabled {
                    Text(L(.alreadyEnabled))
                        .font(.caption2)
                        .foregroundColor(.green)
                } else {
                    Image(systemName: isSelected
                          ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(isSelected ? .accentColor : .secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected && !daw.isRosettaEnabled
                       ? Color.accentColor.opacity(0.08) : Color.clear)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .disabled(daw.isRosettaEnabled)
    }
}
