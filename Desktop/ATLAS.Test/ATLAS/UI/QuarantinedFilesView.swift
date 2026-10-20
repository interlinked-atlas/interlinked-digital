import SwiftUI
import AppKit

struct QuarantinedFilesView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var qm = QuarantineManager.shared

    @State private var pendingRestore: QuarantineRecord? = nil
    @State private var showRestoreConfirm = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var showAlert = false

    var body: some View {
        VStack(spacing: 0) {

            // ── Header ────────────────────────────────────────────────
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Color(hex: "#E05555"))
                    Text("Quarantined Files")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Color.atlasLabel)
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(Color.atlasSubtitle.opacity(0.7))
                }
                .buttonStyle(.plain)
                .help("Close")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

            Divider()
                .background(Color.atlasSeparator)

            if qm.records.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(qm.records.enumerated()), id: \.element.id) { idx, record in
                            if idx > 0 {
                                Divider()
                                    .background(Color.atlasSeparator)
                                    .padding(.leading, 16)
                            }
                            quarantineRow(record)
                        }
                    }
                    .atlasCard()
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 20)
                }
            }
        }
        .frame(width: 420, height: 480)
        .atlasBackground()
        .confirmationDialog(
            "Unquarantine \"\(pendingRestore?.fileName ?? "")\"?",
            isPresented: $showRestoreConfirm,
            titleVisibility: .visible
        ) {
            Button("Restore to Original Location", role: .destructive) {
                if let record = pendingRestore { performRestore(record) }
            }
            Button("Cancel", role: .cancel) { pendingRestore = nil }
        } message: {
            Text("This file was quarantined because TITAN VSCAN™ detected a threat. Restoring it will move it back to its original location. It will not be opened or executed automatically.")
        }
        .alert(alertTitle, isPresented: $showAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "lock.shield")
                .font(.system(size: 36, weight: .light))
                .foregroundColor(Color.atlasSubtitle.opacity(0.35))
            Text("No Quarantined Files")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Color.atlasLabel)
            Text("Files blocked by TITAN VSCAN™ will appear here.")
                .font(.system(size: 12))
                .foregroundColor(Color.atlasSubtitle)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
    }

    // MARK: - Record row

    @ViewBuilder
    private func quarantineRow(_ record: QuarantineRecord) -> some View {
        VStack(alignment: .leading, spacing: 10) {

            // File name + verdict badge
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "doc.badge.exclamationmark")
                    .font(.system(size: 20))
                    .foregroundColor(Color(hex: "#E05555"))
                    .frame(width: 28, alignment: .center)

                VStack(alignment: .leading, spacing: 3) {
                    Text(record.fileName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color.atlasLabel)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    if !record.threatNames.isEmpty {
                        Text(record.threatNames.joined(separator: ", "))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color(hex: "#E05555"))
                            .lineLimit(1)
                    }

                    if !record.threatTypes.isEmpty {
                        Text(record.threatTypes.joined(separator: " · "))
                            .font(.system(size: 10))
                            .foregroundColor(Color.atlasSubtitle)
                            .lineLimit(1)
                    }

                    Text("Quarantined \(record.quarantinedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.system(size: 10))
                        .foregroundColor(Color.atlasSubtitle)
                }

                Spacer()

                Text(record.verdict.uppercased())
                    .font(.system(size: 8, weight: .black))
                    .tracking(0.5)
                    .foregroundColor(Color(hex: "#E05555"))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color(hex: "#E05555").opacity(0.12))
                    .cornerRadius(4)
            }

            // Original path
            HStack(spacing: 4) {
                Image(systemName: "folder")
                    .font(.system(size: 10))
                    .foregroundColor(Color.atlasSubtitle.opacity(0.6))
                Text(record.originalPath)
                    .font(.system(size: 10).monospaced())
                    .foregroundColor(Color.atlasSubtitle)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            .padding(.leading, 38)

            // Action buttons
            HStack(spacing: 8) {
                Spacer()

                Button {
                    showInFinder(record)
                } label: {
                    Label("Show in Finder", systemImage: "folder")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color(hex: "#7090B8"))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color(hex: "#7090B8").opacity(0.10))
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .help("Reveal this file in Finder (does not restore or open it)")

                Button {
                    pendingRestore = record
                    showRestoreConfirm = true
                } label: {
                    Label("Unquarantine", systemImage: "arrow.uturn.backward")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color(hex: "#F0A030"))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color(hex: "#F0A030").opacity(0.10))
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .help("Restore this file to its original location")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    // MARK: - Actions

    private func showInFinder(_ record: QuarantineRecord) {
        let url = qm.quarantineFileURL(for: record)
        guard FileManager.default.fileExists(atPath: url.path) else {
            alertTitle = "File Not Found"
            alertMessage = "The quarantined file could not be located. It may have been moved or deleted outside of ATLAS."
            showAlert = true
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func performRestore(_ record: QuarantineRecord) {
        let fm = FileManager.default
        let src = qm.quarantineFileURL(for: record)
        let dest = URL(fileURLWithPath: record.originalPath)
        pendingRestore = nil

        // 1. Quarantined source must still exist on disk
        guard fm.fileExists(atPath: src.path) else {
            alertTitle = "File Not Found"
            alertMessage = "The quarantined file is no longer at its expected location:\n\(src.path)\n\nIt may have been moved or deleted outside of ATLAS."
            showAlert = true
            return
        }

        // 2. Never silently overwrite — destination must be clear
        if fm.fileExists(atPath: dest.path) {
            alertTitle = "Cannot Restore"
            alertMessage = "A file already exists at the original location:\n\n\(dest.path)\n\nRemove or rename the existing file, then try again. The quarantined copy has not been moved."
            showAlert = true
            return
        }

        // 3. Destination directory — create if it no longer exists
        let destDir = dest.deletingLastPathComponent()
        if !fm.fileExists(atPath: destDir.path) {
            do {
                try fm.createDirectory(at: destDir, withIntermediateDirectories: true)
            } catch {
                alertTitle = "Cannot Restore"
                alertMessage = "The original directory no longer exists and could not be recreated:\n\n\(destDir.path)\n\nError: \(error.localizedDescription)\n\nThe quarantined copy has not been moved."
                showAlert = true
                return
            }
        }

        // 4. Restore — QuarantineManager removes the record and saves manifest on success
        let ok = qm.restore(record: record)
        if !ok {
            alertTitle = "Restore Failed"
            alertMessage = "Could not move the file to:\n\n\(dest.path)\n\nCheck that ATLAS has Full Disk Access in System Settings → Privacy & Security. The quarantined copy has not been moved."
            showAlert = true
        }
        // On success: qm.records updates automatically via @Published → UI refreshes
    }
}
