import SwiftUI

struct RecoveryKitView: View {
    @ObservedObject var engine: RecoveryKitEngine
    @ObservedObject var store: HistoryStore
    var onStartRecovery: ((AtlasKit) -> Void)? = nil
    @ObservedObject private var auth = AuthManager.shared
    @ObservedObject private var langMgr = LanguageManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            exportRow
            Rectangle()
                .fill(Color.atlasSeparator.opacity(0.6))
                .frame(height: 1)
                .padding(.horizontal, 12)
            importRow
            if auth.isPro && auth.isSignedIn {
                Rectangle()
                    .fill(Color.atlasSeparator.opacity(0.6))
                    .frame(height: 1)
                    .padding(.horizontal, 12)
                cloudBackupSection
            }
            if engine.importState == .loaded, let kit = engine.importedKit {
                importedKitSummary(kit: kit)
            }
            if engine.importState == .hashMismatch {
                hashMismatchBanner
            }
            if case .failed(let msg) = engine.importState {
                errorBanner(msg)
            }
        }
        .padding(.bottom, 8)
        .onAppear {
            Task { await engine.loadCloudKitMetadata() }
        }
    }

    // MARK: - Export row

    private var exportRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "lifepreserver")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(auth.isPro ? Color(hex: "#3ECFB2") : Color.atlasSubtitle.opacity(0.4))
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text("ATLAS RECOVERY KIT™")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(auth.isPro ? Color.atlasLabel : Color.atlasSubtitle.opacity(0.6))
                    if !auth.isPro {
                        Text("PRO")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(Color(hex: "#3ECFB2"))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color(hex: "#3ECFB2").opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                    }
                }
                exportSubtitle
            }

            Spacer()
            exportButton
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var exportSubtitle: some View {
        switch engine.exportState {
        case .idle:
            Text(L(.portableSnapshot))
                .font(.system(size: 10))
                .foregroundColor(Color.atlasSubtitle.opacity(0.5))
        case .exporting:
            HStack(spacing: 4) {
                ProgressView().scaleEffect(0.5).frame(width: 10, height: 10)
                Text(L(.generating))
                    .font(.system(size: 10))
                    .foregroundColor(Color.atlasSubtitle.opacity(0.5))
            }
        case .complete(let date):
            Text("Last exported \(shortDate(date))")
                .font(.system(size: 10))
                .foregroundColor(Color(hex: "#3ECFB2"))
        case .failed:
            Text(L(.exportFailed))
                .font(.system(size: 10))
                .foregroundColor(Color(hex: "#E05555").opacity(0.8))
        }
    }

    @ViewBuilder
    private var exportButton: some View {
        if case .exporting = engine.exportState {
            EmptyView()
        } else if auth.isPro {
            Button(L(.generate)) {
                Task { await engine.export(store: store) }
            }
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color(hex: "#3ECFB2"))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .buttonStyle(.plain)
        } else {
            Button(L(.upgrade)) {
                NSWorkspace.shared.open(URL(string: "https://interlinked.digital/account")!)
            }
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(Color(hex: "#3ECFB2"))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color(hex: "#3ECFB2").opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .buttonStyle(.plain)
        }
    }

    // MARK: - Cloud backup section (Pro only, additive)

    private var cloudBackupSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "icloud.and.arrow.up")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color(hex: "#3ECFB2"))
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 1) {
                    Text(L(.cloudBackupLabel))
                        .font(.system(size: 11))
                        .foregroundColor(Color.atlasLabel.opacity(0.8))
                    cloudBackupSubtitle
                }

                Spacer()
                cloudBackupButtons
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            if case .error(let msg) = engine.cloudState {
                errorBanner(msg)
                    .padding(.top, 2)
            }

            Text("ATLAS stores your recovery plan, not your software installers.")
                .font(.system(size: 9))
                .foregroundColor(Color.atlasSubtitle.opacity(0.35))
                .padding(.horizontal, 12)
                .padding(.bottom, 4)
        }
    }

    @ViewBuilder
    private var cloudBackupSubtitle: some View {
        switch engine.cloudState {
        case .idle, .loading:
            HStack(spacing: 4) {
                ProgressView().scaleEffect(0.5).frame(width: 10, height: 10)
                Text(L(.checking))
                    .font(.system(size: 10))
                    .foregroundColor(Color.atlasSubtitle.opacity(0.45))
            }
        case .notFound:
            Text(L(.notBackedUp))
                .font(.system(size: 10))
                .foregroundColor(Color.atlasSubtitle.opacity(0.45))
        case .found:
            if let meta = engine.cloudMeta.first {
                VStack(alignment: .leading, spacing: 1) {
                    // Show recovery result if this specific backup was the one recovered
                    if let result = engine.lastRecoveryResult, result.kitId == meta.id {
                        switch result {
                        case .success:
                            Text("Recovered \(shortDate(meta.generatedAt)) ✓")
                                .font(.system(size: 10))
                                .foregroundColor(Color(hex: "#3ECFB2"))
                        case .withIssues:
                            Text("Recovery completed with issues")
                                .font(.system(size: 10))
                                .foregroundColor(Color(hex: "#F0A030"))
                        }
                    } else {
                        Text("Last backed up \(shortDate(meta.generatedAt))")
                            .font(.system(size: 10))
                            .foregroundColor(Color(hex: "#3ECFB2"))
                    }
                    if let name = meta.deviceName {
                        Text("\(meta.recordCount) items · \(name)")
                            .font(.system(size: 10))
                            .foregroundColor(Color.atlasSubtitle.opacity(0.5))
                    } else {
                        Text("\(meta.recordCount) items")
                            .font(.system(size: 10))
                            .foregroundColor(Color.atlasSubtitle.opacity(0.5))
                    }
                }
            } else {
                Text("Backed up")
                    .font(.system(size: 10))
                    .foregroundColor(Color(hex: "#3ECFB2"))
            }
        case .uploading:
            HStack(spacing: 4) {
                ProgressView().scaleEffect(0.5).frame(width: 10, height: 10)
                Text(L(.syncing))
                    .font(.system(size: 10))
                    .foregroundColor(Color.atlasSubtitle.opacity(0.5))
            }
        case .downloading:
            HStack(spacing: 4) {
                ProgressView().scaleEffect(0.5).frame(width: 10, height: 10)
                Text(L(.restoring))
                    .font(.system(size: 10))
                    .foregroundColor(Color.atlasSubtitle.opacity(0.5))
            }
        case .error:
            EmptyView()  // error banner below the row already shows the actual message
        }
    }

    @ViewBuilder
    private var cloudBackupButtons: some View {
        let busy = engine.cloudState == .uploading || engine.cloudState == .downloading
                   || engine.cloudState == .loading || engine.cloudState == .idle

        if busy {
            EmptyView()
        } else if engine.cloudState == .found {
            HStack(spacing: 6) {
                // Update requires a locally-generated kit this session to upload
                if engine.lastGeneratedKitFolderURL != nil {
                    Button(L(.update)) {
                        Task { await engine.uploadToCloud(store: store) }
                    }
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Color.atlasSubtitle.opacity(0.7))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.atlasElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .buttonStyle(.plain)
                }

                let currentMetaId = engine.cloudMeta.first?.id
                let recoveredThisBackup = engine.lastRecoveryResult.map { $0.kitId == currentMetaId } ?? false

                if case .success = engine.lastRecoveryResult, recoveredThisBackup {
                    // Full success — no recovery action needed
                    Text("Recovered ✓")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Color(hex: "#3ECFB2"))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                } else if case .withIssues = engine.lastRecoveryResult, recoveredThisBackup {
                    // Completed with issues — retry the same already-downloaded kit (no re-download)
                    if let kit = engine.importedKit {
                        Button("Try Recovery Again") {
                            onStartRecovery?(kit)
                        }
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color(hex: "#F0A030"))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .buttonStyle(.plain)
                    }
                } else {
                    Button(L(.recover)) {
                        if let kitId = engine.cloudMeta.first?.id {
                            Task { await engine.downloadFromCloud(kitId: kitId) }
                        }
                    }
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color(hex: "#3ECFB2"))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .buttonStyle(.plain)
                }
            }
        } else if engine.lastGeneratedKitFolderURL != nil {
            // .notFound or .error — only show retry when there's a local kit to upload
            if case .error = engine.cloudState {
                Button(L(.retryCloudBackup)) {
                    Task { await engine.uploadToCloud(store: store) }
                }
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color(hex: "#3ECFB2"))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .buttonStyle(.plain)
            } else {
                Button(L(.backUp)) {
                    Task { await engine.uploadToCloud(store: store) }
                }
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color(hex: "#3ECFB2"))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Import row

    private var importRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.down.doc")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Color.atlasSubtitle.opacity(0.5))
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text(L(.loadRecoveryKit))
                    .font(.system(size: 11))
                    .foregroundColor(Color.atlasLabel.opacity(0.8))
                importSubtitle
            }

            Spacer()
            importButton
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var importSubtitle: some View {
        switch engine.importState {
        case .idle:
            Text(L(.openKitFile))
                .font(.system(size: 10))
                .foregroundColor(Color.atlasSubtitle.opacity(0.45))
        case .importing:
            HStack(spacing: 4) {
                ProgressView().scaleEffect(0.5).frame(width: 10, height: 10)
                Text(L(.loading))
                    .font(.system(size: 10))
                    .foregroundColor(Color.atlasSubtitle.opacity(0.5))
            }
        case .loaded:
            Text(L(.kitLoaded))
                .font(.system(size: 10))
                .foregroundColor(Color(hex: "#3ECFB2"))
        case .hashMismatch:
            Text(L(.fileRejected))
                .font(.system(size: 10))
                .foregroundColor(Color(hex: "#E05555").opacity(0.8))
        case .failed:
            Text(L(.couldNotLoad))
                .font(.system(size: 10))
                .foregroundColor(Color(hex: "#E05555").opacity(0.8))
        }
    }

    @ViewBuilder
    private var importButton: some View {
        if case .importing = engine.importState {
            EmptyView()
        } else {
            Button(engine.importState == .loaded ? L(.replace) : L(.open)) {
                Task { await engine.importKit() }
            }
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(Color.atlasSubtitle.opacity(0.7))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.atlasElevated)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .buttonStyle(.plain)
        }
    }

    // MARK: - Imported kit summary

    private func importedKitSummary(kit: AtlasKit) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if engine.isCrossMacKit {
                crossMacBanner
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("ATLAS \(kit.atlasVersion)  ·  \(shortDate(kit.exportedAt))")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Color.atlasSubtitle.opacity(0.7))
                    Spacer()
                }

                HStack(spacing: 12) {
                    kitStat(label: L(.queueStatusInstalled), value: "\(kit.records.count)")
                    kitStat(label: L(.archived), value: "\(kit.archivedRecords.count)")
                }

                if !kit.records.isEmpty {
                    Text(L(.products) + ": " + kit.records.prefix(3).map { $0.fileName }.joined(separator: ", ")
                         + (kit.records.count > 3 ? " +\(kit.records.count - 3) more" : ""))
                        .font(.system(size: 10))
                        .foregroundColor(Color.atlasSubtitle.opacity(0.55))
                        .lineLimit(2)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.atlasElevated.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .padding(.horizontal, 12)

            // Recovery Mode entry point — gated via extracted pure function (testable without AuthManager)
            if RecoveryModeEngine.canStartRecovery(isPro: auth.isPro) {
                // Show result state if this specific downloaded backup was already recovered
                let alreadyRecovered = engine.downloadedKitId != nil
                    && engine.lastRecoveryResult?.kitId == engine.downloadedKitId

                if alreadyRecovered, let result = engine.lastRecoveryResult {
                    switch result {
                    case .success:
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 10))
                                .foregroundColor(Color(hex: "#3ECFB2"))
                            Text("Recovery Complete ✓")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(Color(hex: "#3ECFB2"))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color(hex: "#3ECFB2").opacity(0.10))
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .padding(.horizontal, 12)

                    case .withIssues:
                        VStack(spacing: 6) {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle")
                                    .font(.system(size: 10))
                                    .foregroundColor(Color(hex: "#F0A030"))
                                Text("Recovery Completed with Issues")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(Color(hex: "#F0A030"))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(Color(hex: "#F0A030").opacity(0.10))
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

                            Button {
                                onStartRecovery?(kit)
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                        .font(.system(size: 10, weight: .semibold))
                                    Text("Try Recovery Again")
                                        .font(.system(size: 10, weight: .bold))
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(Color(hex: "#F0A030"))
                                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 12)
                    }
                } else {
                    Button {
                        onStartRecovery?(kit)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 10, weight: .semibold))
                            Text(L(.beginRecovery))
                                .font(.system(size: 10, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color(hex: "#3ECFB2"))
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 12)
                    .tourAnchor("recoveryModeButton")
                }
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 9))
                        .foregroundColor(Color(hex: "#3ECFB2"))
                    Text(L(.recoveryModeProNote))
                        .font(.system(size: 10))
                        .foregroundColor(Color.atlasSubtitle.opacity(0.6))
                    Button(L(.upgrade)) {
                        NSWorkspace.shared.open(URL(string: "https://interlinked.digital/account")!)
                    }
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Color(hex: "#3ECFB2"))
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
        }
    }

    private func kitStat(label: String, value: String) -> some View {
        HStack(spacing: 3) {
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(Color.atlasLabel)
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(Color.atlasSubtitle.opacity(0.55))
        }
    }

    // MARK: - Cross-Mac banner (persistent, non-dismissable)

    private var crossMacBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "info.circle")
                .font(.system(size: 10))
                .foregroundColor(Color(hex: "#3ECFB2"))
            Text(L(.crossMacKitNote))
                .font(.system(size: 10))
                .foregroundColor(Color.atlasSubtitle.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(hex: "#3ECFB2").opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .padding(.horizontal, 12)
    }

    // MARK: - Hash mismatch banner (hard rejection)

    private var hashMismatchBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10))
                .foregroundColor(Color(hex: "#E05555"))
            Text(L(.hashMismatchNote))
                .font(.system(size: 10))
                .foregroundColor(Color(hex: "#E05555").opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(hex: "#E05555").opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .padding(.horizontal, 12)
    }

    private func errorBanner(_ msg: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 10))
                .foregroundColor(Color(hex: "#E05555"))
            Text(msg)
                .font(.system(size: 10))
                .foregroundColor(Color(hex: "#E05555").opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(hex: "#E05555").opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .padding(.horizontal, 12)
    }

    // MARK: - Helpers

    private func shortDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: date)
    }
}
