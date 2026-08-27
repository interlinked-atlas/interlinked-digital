import SwiftUI
import AppKit

// MARK: - Session grouping helper

private struct SessionGroup: Identifiable {
    let id: UUID
    let records: [InstallRecord]
    var isBatch: Bool { records.count > 1 }
    var date: Date { records.first?.date ?? Date() }

    var uninstallableRecords: [InstallRecord] {
        records.filter { $0.status == .success }
    }
}

// MARK: - Plugin format row model (derived from installedFiles at render time)

struct PluginFormatRow: Identifiable {
    let id = UUID()
    let label: String           // "AU", "VST3", "VST", "AAX"
    let formatKey: String       // "au", "vst3", "vst", "aax"
    let destinationPath: String // canonical installed path
}

private func pluginFormatLabel(for path: String) -> (label: String, key: String)? {
    switch URL(fileURLWithPath: path).pathExtension.lowercased() {
    case "component":  return ("AU",  "au")
    case "vst3":       return ("VST3","vst3")
    case "vst":        return ("VST", "vst")
    case "aaxplugin":  return ("AAX", "aax")
    default:           return nil
    }
}

private func pluginFormats(for record: InstallRecord) -> [PluginFormatRow] {
    var seen = Set<String>()
    return record.installedFiles.compactMap { file in
        guard let (label, key) = pluginFormatLabel(for: file.destinationPath),
              seen.insert(file.destinationPath).inserted else { return nil }
        return PluginFormatRow(label: label, formatKey: key, destinationPath: file.destinationPath)
    }
}

// MARK: - ATLAS Library Panel

struct HistoryPanelView: View {
    @ObservedObject var store: HistoryStore
    @ObservedObject var logger: Logger
    @ObservedObject private var langMgr = LanguageManager.shared
    var onClose: (() -> Void)? = nil
    let onRollback: (InstallRecord) -> Void
    let onRestore: (InstallRecord) -> Void
    let onBatchRollback: ([InstallRecord]) -> Void

    @State private var showClearConfirm = false

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── Header ────────────────────────────────────────────────
            HStack(spacing: 8) {
                Button { onClose?() } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color.atlasSubtitle)
                        .frame(width: 24, height: 24)
                        .background(Color.atlasElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
                .help("Close ATLAS Library")

                Text(L(.atlasLibrary))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color.atlasLabel)
                Spacer()
                if !store.records.isEmpty {
                    Button(L(.clearAll)) { showClearConfirm = true }
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Color(hex: "#E05555").opacity(0.85))
                        .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)

            Rectangle()
                .fill(Color.atlasSeparator)
                .frame(height: 1)

            InstalledProductsSection(
                store: store, logger: logger,
                scrollable: true,
                onRollback: onRollback,
                onRestore: onRestore,
                onBatchRollback: onBatchRollback
            )
        }
        .frame(width: 320)
        .background(Color.atlasSessionHeader)
        .alert(L(.clearAtlasLibraryTitle), isPresented: $showClearConfirm) {
            Button(L(.cancel), role: .cancel) {}
            Button(L(.clearAll), role: .destructive) { store.clearAll() }
        } message: {
            Text(String(format: L(.clearLibraryMsgFmt), store.records.count))
        }
    }
}

// MARK: - Installed Products Section

struct InstalledProductsSection: View {
    @ObservedObject var store: HistoryStore
    @ObservedObject var logger: Logger
    var scrollable: Bool = true
    var externalSearch: Binding<String> = .constant("")
    let onRollback: (InstallRecord) -> Void
    let onRestore: (InstallRecord) -> Void
    let onBatchRollback: ([InstallRecord]) -> Void

    @State private var rollbackTarget: InstallRecord? = nil
    @State private var showRollbackConfirm = false
    @State private var restoreTarget: InstallRecord? = nil
    @State private var showRestoreConfirm = false
    @State private var showRestoreUnavailable = false
    @State private var restoreUnavailableMsg = ""
    @State private var batchTarget: [InstallRecord] = []
    @State private var showBatchConfirm = false
    @State private var removeTarget: InstallRecord? = nil
    @State private var showRemoveConfirm = false
    @State private var supportTarget: InstallRecord? = nil
    @State private var showSupport = false
    @State private var feedbackTarget: InstallRecord? = nil
    @State private var showArchive = false
    @State private var showPermanentDeleteArchivesConfirm = false

    @State private var searchText = ""
    @State private var showFilters = false
    @State private var filterFormat = "All"
    @State private var filterStatus = "All"
    @State private var filterDate   = "All"
    @State private var filterEnableState = "All"

    private var activeSearchText: String {
        let ext = externalSearch.wrappedValue.trimmingCharacters(in: .whitespaces)
        return ext.isEmpty ? searchText.trimmingCharacters(in: .whitespaces) : ext
    }

    @ObservedObject private var auth = AuthManager.shared

    // MARK: - Session grouping

    private var sessionGroups: [SessionGroup] {
        rebuildSessionGroups(from: store.records)
    }

    private func rebuildSessionGroups(from records: [InstallRecord]) -> [SessionGroup] {
        var groups: [SessionGroup] = []
        var sessionIndex: [UUID: Int] = [:]
        for record in records {
            if let sid = record.sessionID {
                if let idx = sessionIndex[sid] {
                    groups[idx] = SessionGroup(id: groups[idx].id, records: groups[idx].records + [record])
                } else {
                    sessionIndex[sid] = groups.count
                    groups.append(SessionGroup(id: sid, records: [record]))
                }
            } else {
                groups.append(SessionGroup(id: record.id, records: [record]))
            }
        }
        return groups
    }

    // MARK: - Search + filter pipeline

    private var filteredGroups: [SessionGroup] {
        var records = store.records

        let q = activeSearchText.lowercased()
        if !q.isEmpty {
            records = records.filter { r in
                r.fileName.lowercased().contains(q) ||
                r.fileType.lowercased().contains(q) ||
                r.installedFiles.contains { $0.sourceName.lowercased().contains(q) } ||
                r.installedFiles.contains { $0.destinationPath.lowercased().contains(q) } ||
                r.pkgReceiptIDs.contains { $0.lowercased().contains(q) }
            }
        }

        if filterFormat != "All" {
            records = records.filter { r in
                pluginFormats(for: r).contains { $0.label == filterFormat } ||
                (filterFormat == "Software" && r.installedFiles.contains {
                    $0.destinationPath.hasPrefix("/Applications/") ||
                    URL(fileURLWithPath: $0.destinationPath).pathExtension.lowercased() == "app"
                })
            }
        }

        if filterStatus != "All" {
            records = records.filter { $0.status.rawValue == filterStatus }
        }

        if filterEnableState == "Has Disabled" {
            records = records.filter { ($0.disabledFormats?.isEmpty == false) }
        } else if filterEnableState == "Fully Enabled" {
            records = records.filter { $0.disabledFormats == nil || $0.disabledFormats!.isEmpty }
        }

        if filterDate != "All" {
            let cutoff: Date
            if filterDate == "7d" {
                cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
            } else {
                cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
            }
            records = records.filter { $0.date >= cutoff }
        }

        return rebuildSessionGroups(from: records)
    }

    private var activeFilterCount: Int {
        [filterFormat != "All", filterStatus != "All",
         filterDate != "All", filterEnableState != "All"].filter { $0 }.count
    }

    // MARK: - Body

    var body: some View {
        Group {
            if scrollable {
                scrollableContent
            } else {
                embeddedContent
            }
        }
        .alert(L(.removeFromLibraryTitle), isPresented: $showRemoveConfirm) {
            Button(L(.cancel), role: .cancel) {}
            Button(L(.remove), role: .destructive) {
                if let t = removeTarget { store.remove(id: t.id) }
            }
        } message: {
            if let record = removeTarget {
                Text(String(format: L(.removeRecordMsgFmt), record.fileName))
            }
        }
        .alert(L(.uninstallConfirmTitle), isPresented: $showRollbackConfirm) {
            Button(L(.cancel), role: .cancel) {}
            Button(L(.uninstall), role: .destructive) {
                if let t = rollbackTarget { onRollback(t) }
            }
        } message: {
            if let record = rollbackTarget {
                let detail = !record.pkgReceiptIDs.isEmpty
                    ? String(format: L(.receiptsAndFilesFmt), record.pkgReceiptIDs.count, record.installedFiles.count)
                    : String(format: L(.filesTrackedFmt), record.installedFiles.count)
                let disabledNote = (record.disabledFormats?.isEmpty == false)
                    ? String(format: L(.disabledFormatsNoteFmt), record.disabledFormats!.count)
                    : ""
                Text(String(format: L(.uninstallConfirmMsgFmt), detail, record.fileName, disabledNote))
            }
        }
        .alert(L(.recoverFilesTitle), isPresented: $showRestoreConfirm) {
            Button(L(.cancel), role: .cancel) {}
            Button(L(.recover)) {
                if let t = restoreTarget { onRestore(t) }
            }
        } message: {
            if let record = restoreTarget {
                Text(String(format: L(.recoverFilesMsgFmt), record.fileName))
            }
        }
        .alert(L(.recoveryNotAvailable), isPresented: $showRestoreUnavailable) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(restoreUnavailableMsg)
        }
        .alert(L(.uninstallSessionTitle), isPresented: $showBatchConfirm) {
            Button(L(.cancel), role: .cancel) {}
            Button(L(.uninstall), role: .destructive) {
                onBatchRollback(batchTarget)
                batchTarget = []
            }
        } message: {
            Text(String(format: L(.uninstallSessionMsgFmt), batchTarget.count))
        }
        .alert(L(.deleteArchivesTitle), isPresented: $showPermanentDeleteArchivesConfirm) {
            Button(L(.cancel), role: .cancel) {}
            Button(L(.deleteAllArchivesBtn), role: .destructive) {
                store.deleteAllArchivedRecords()
            }
        } message: {
            Text(L(.deleteArchivesMsg))
        }
        .sheet(isPresented: $showSupport) {
            SupportView(preselectedRecord: supportTarget, allRecords: store.records)
        }
        .sheet(item: $feedbackTarget) { record in
            HistoryFeedbackSheet(record: record, store: store)
        }
    }

    // MARK: - Scrollable layout (standalone panel — original HistoryPanelView behavior)

    private var scrollableContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            searchAndFiltersBar
            scrollableMainContent
        }
    }

    @ViewBuilder
    private var scrollableMainContent: some View {
        let groups = filteredGroups
        if store.records.isEmpty && store.archivedRecords.isEmpty {
            emptyLibraryView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if store.records.isEmpty {
            Spacer()
            if !store.archivedRecords.isEmpty { archiveSectionView }
        } else if groups.isEmpty {
            noResultsView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if !store.archivedRecords.isEmpty { archiveSectionView }
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    cardList(groups: groups)
                }
            }
            if !store.archivedRecords.isEmpty { archiveSectionView }
        }
    }

    // MARK: - Embedded layout (inside parent ScrollView — dashboard use)

    private var embeddedContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            searchAndFiltersBar
            embeddedMainContent
        }
    }

    @ViewBuilder
    private var embeddedMainContent: some View {
        let groups = filteredGroups
        if store.records.isEmpty && store.archivedRecords.isEmpty {
            emptyLibraryView
                .padding(.vertical, 24)
        } else if store.records.isEmpty {
            if !store.archivedRecords.isEmpty { archiveSectionView }
        } else if groups.isEmpty {
            noResultsView
                .padding(.vertical, 16)
            if !store.archivedRecords.isEmpty { archiveSectionView }
        } else {
            LazyVStack(spacing: 0) {
                cardList(groups: groups)
            }
            if !store.archivedRecords.isEmpty { archiveSectionView }
        }
    }

    // MARK: - Shared card list

    @ViewBuilder
    private func cardList(groups: [SessionGroup]) -> some View {
        ForEach(groups) { group in
            if group.isBatch {
                sessionHeaderView(group: group)
            }
            ForEach(group.records) { record in
                LibraryItemCard(
                    record: record,
                    store: store,
                    inSession: group.isBatch,
                    onRollback: {
                        rollbackTarget = record
                        showRollbackConfirm = true
                    },
                    onRestore: {
                        if let backupPath = record.rollbackBackupPath {
                            if let data = try? Data(contentsOf: URL(fileURLWithPath: backupPath)),
                               let trashRecords = try? JSONDecoder().decode([TrashRecord].self, from: data) {
                                let anyInTrash = trashRecords.contains {
                                    FileManager.default.fileExists(atPath: $0.trashPath)
                                }
                                if !anyInTrash {
                                    let names = trashRecords
                                        .map { URL(fileURLWithPath: $0.originalPath).lastPathComponent }
                                        .joined(separator: "\n")
                                    restoreUnavailableMsg = "The files uninstalled from \"\(record.fileName)\" were permanently deleted from Trash and can no longer be recovered.\n\n\(names)"
                                    showRestoreUnavailable = true
                                    return
                                }
                            } else {
                                restoreUnavailableMsg = "Recovery data for \"\(record.fileName)\" could not be found."
                                showRestoreUnavailable = true
                                return
                            }
                        }
                        restoreTarget = record
                        showRestoreConfirm = true
                    },
                    onRemove: {
                        removeTarget = record
                        showRemoveConfirm = true
                    },
                    onSupport: {
                        supportTarget = record
                        showSupport = true
                    },
                    onFeedback: {
                        feedbackTarget = record
                    }
                )
                Rectangle()
                    .fill(Color.atlasSeparator.opacity(0.6))
                    .frame(height: 1)
                    .padding(.leading, group.isBatch ? 28 : 0)
            }
        }
    }

    // MARK: - Search + Filters bar

    @ViewBuilder
    private var searchAndFiltersBar: some View {
        if !store.records.isEmpty {
            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    if scrollable {
                        HStack(spacing: 5) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(Color.atlasSubtitle.opacity(0.6))
                            TextField("Search ATLAS Library…", text: $searchText)
                                .font(.system(size: 11))
                                .foregroundColor(Color.atlasLabel)
                                .textFieldStyle(.plain)
                            if !searchText.isEmpty {
                                Button { searchText = "" } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 10))
                                        .foregroundColor(Color.atlasSubtitle.opacity(0.5))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 5)
                        .background(Color.atlasElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }

                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            showFilters.toggle()
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "line.3.horizontal.decrease")
                                .font(.system(size: 9, weight: .semibold))
                            Text(activeFilterCount > 0 ? "Filters · \(activeFilterCount)" : "Filters")
                                .font(.system(size: 10, weight: .medium))
                            }
                            .foregroundColor(activeFilterCount > 0 ? Color(hex: "#3ECFB2") : Color.atlasSubtitle)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 5)
                            .background(activeFilterCount > 0
                                ? Color(hex: "#3ECFB2").opacity(0.10)
                                : Color.atlasElevated)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)

                    // ── Filter strip ──────────────────────────────────────
                    if showFilters {
                        VStack(alignment: .leading, spacing: 6) {
                            filterRow(label: "Format", options: ["All","AU","VST","VST3","AAX","Software"],
                                      selection: $filterFormat)
                            filterRow(label: "Status", options: ["All","success","failure","uninstalled"],
                                      displayNames: ["All","Installed","Failed","Uninstalled"],
                                      selection: $filterStatus)
                            filterRow(label: "State",  options: ["All","Fully Enabled","Has Disabled"],
                                      selection: $filterEnableState)
                            filterRow(label: "Date",   options: ["All","7d","30d"],
                                      displayNames: ["All","Last 7 days","Last 30 days"],
                                      selection: $filterDate)
                            if activeFilterCount > 0 {
                                Button("Clear Filters") {
                                    filterFormat = "All"; filterStatus = "All"
                                    filterDate = "All"; filterEnableState = "All"
                                }
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(Color(hex: "#E05555").opacity(0.8))
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.bottom, 8)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    Rectangle()
                        .fill(Color.atlasSeparator)
                        .frame(height: 1)
                }
            }
    }

    // MARK: - Empty states

    private var emptyLibraryView: some View {
        VStack(spacing: 8) {
            Image(systemName: "books.vertical")
                .font(.system(size: 24))
                .foregroundColor(Color.atlasSubtitle.opacity(0.4))
            Text(L(.noInstallsYet))
                .font(.system(size: 11))
                .foregroundColor(Color.atlasSubtitle.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
    }

    private var noResultsView: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 20))
                .foregroundColor(Color.atlasSubtitle.opacity(0.4))
            Text(!activeSearchText.isEmpty
                 ? "No results for \"\(activeSearchText)\""
                 : "No items match these filters")
                .font(.system(size: 11))
                .foregroundColor(Color.atlasSubtitle.opacity(0.6))
                .multilineTextAlignment(.center)
            if !activeSearchText.isEmpty || activeFilterCount > 0 {
                Button("Clear") {
                    searchText = ""
                    externalSearch.wrappedValue = ""
                    filterFormat = "All"; filterStatus = "All"
                    filterDate = "All"; filterEnableState = "All"
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(Color(hex: "#3ECFB2"))
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Filter row helper

    @ViewBuilder
    private func filterRow(label: String, options: [String],
                           displayNames: [String]? = nil,
                           selection: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(Color.atlasSubtitle.opacity(0.6))
                .textCase(.uppercase)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(options.indices, id: \.self) { i in
                        let option = options[i]
                        let displayName = displayNames?[i] ?? option
                        let isSelected = selection.wrappedValue == option
                        Button { selection.wrappedValue = option } label: {
                            Text(displayName)
                                .font(.system(size: 9, weight: isSelected ? .semibold : .regular))
                                .foregroundColor(isSelected ? Color(hex: "#08090E") : Color.atlasSubtitle)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(isSelected ? Color(hex: "#3ECFB2") : Color.atlasElevated)
                                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Session header

    @ViewBuilder
    private func sessionHeaderView(group: SessionGroup) -> some View {
        let eligible = group.uninstallableRecords
        HStack(spacing: 6) {
            Image(systemName: "square.stack.3d.down.right.fill")
                .font(.system(size: 9))
                .foregroundColor(Color(hex: "#3ECFB2"))
            Text(String(format: L(.sessionFmt), group.records.count, shortDate(group.date)))
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(Color.atlasSubtitle)
            Spacer()
            if eligible.count >= 2 {
                Button {
                    batchTarget = eligible
                    showBatchConfirm = true
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "trash").font(.system(size: 8))
                        Text(L(.filterAll)).font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundColor(Color(hex: "#E05555"))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color(hex: "#E05555").opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(Color(hex: "#E05555").opacity(0.25), lineWidth: 0.75))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.atlasDeepBG)
    }

    private func shortDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: date)
    }

    // MARK: - Archive section

    @ViewBuilder
    private var archiveSectionView: some View {
        Rectangle()
            .fill(Color.atlasSeparator)
            .frame(height: 1)

        // Archive header row — expand/collapse + permanent delete
        HStack(spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    showArchive.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "archivebox")
                        .font(.system(size: 9))
                        .foregroundColor(Color.atlasSubtitle.opacity(0.6))
                    Text(String(format: L(.archiveLabelFmt), store.archivedRecords.count))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Color.atlasSubtitle.opacity(0.7))
                    Image(systemName: showArchive ? "chevron.up" : "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundColor(Color.atlasSubtitle.opacity(0.4))
                }
                .padding(.leading, 12)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)

            Spacer()

            // Permanently Delete Archives — distinct destructive action
            Button {
                showPermanentDeleteArchivesConfirm = true
            } label: {
                Text(L(.deleteAll))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(Color(hex: "#E05555").opacity(0.6))
            }
            .buttonStyle(.plain)
            .help("Permanently delete all archived records — Logs are not affected")
            .padding(.trailing, 12)
        }
        .background(Color.atlasDeepBG)

        if showArchive {
            ForEach(store.archivedRecords) { record in
                ArchiveItemCard(record: record, store: store, onRestore: { rec in
                    restoreTarget = rec
                    showRestoreConfirm = true
                })
                Rectangle()
                    .fill(Color.atlasSeparator.opacity(0.6))
                    .frame(height: 1)
            }
        }
    }
}

// MARK: - Library Item Card

struct LibraryItemCard: View {
    let record: InstallRecord
    @ObservedObject var store: HistoryStore
    @ObservedObject private var langMgr = LanguageManager.shared
    var inSession: Bool = false
    let onRollback: () -> Void
    let onRestore: () -> Void
    let onRemove: () -> Void
    var onSupport: (() -> Void)? = nil
    var onFeedback: (() -> Void)? = nil

    @State private var hovered = false
    @State private var isExpanded = false
    @State private var showUpgradeAlert = false
    @State private var lockedFeatureName = ""
    @State private var trashFilesExist: Bool? = nil
    // Enable/Disable state (Phase 8)
    @State private var isTogglingFormat = false
    @State private var toggleError: String? = nil
    @State private var showDisableConfirm = false
    @State private var pendingDisableRow: PluginFormatRow? = nil
    // Code-Sign state
    @State private var isSigningFormat: String? = nil    // formatKey of in-progress signing
    @State private var signSuccessFormat: String? = nil  // formatKey for transient ✓ Signed badge
    @State private var signError: String? = nil
    @State private var showSignError = false

    private var formats: [PluginFormatRow] { pluginFormats(for: record) }

    var canUninstall: Bool { record.status == .success }
    var canRestore: Bool {
        record.status == .uninstalled
            && record.rollbackBackupPath != nil
            && (trashFilesExist ?? true)
    }
    var permanentlyDeleted: Bool {
        record.status == .uninstalled && trashFilesExist == false
    }

    private var statusColor: Color {
        if record.demoDetected == true { return Color(hex: "#F0A030") }
        switch record.status {
        case .success:     return Color(hex: "#2ECC8A")
        case .failure:     return Color(hex: "#E05555")
        case .uninstalled: return Color.atlasSubtitle
        }
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ── Collapsed header ──────────────────────────────────────
            VStack(alignment: .leading, spacing: 5) {
                // Title row
                HStack(spacing: 7) {
                    Image(systemName: record.statusIcon)
                        .foregroundColor(statusColor)
                        .font(.system(size: 11))
                    Text(record.fileName)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color.atlasLabel)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    // Remove button
                    Button(action: onRemove) {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(Color.atlasSubtitle.opacity(hovered ? 0.8 : 0.4))
                    }
                    .buttonStyle(.plain)
                    .help("Remove from ATLAS Library")
                }

                // Meta row
                HStack(spacing: 4) {
                    Text(record.shortDate)
                        .font(.system(size: 10))
                        .foregroundColor(Color.atlasSubtitle)
                    Text("·")
                        .font(.system(size: 10))
                        .foregroundColor(Color.atlasSubtitle.opacity(0.5))
                    Text(record.shortTime)
                        .font(.system(size: 10))
                        .foregroundColor(Color.atlasSubtitle)
                    Spacer()
                    Text(record.fileType)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(Color.atlasSubtitle)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.atlasElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                }

                // Tracked files summary + format inline row + verify badge
                HStack(spacing: 0) {
                    if !record.pkgReceiptIDs.isEmpty {
                        Text(String(format: L(.receiptsAndFilesFmt), record.pkgReceiptIDs.count, record.installedFiles.count))
                            .font(.system(size: 10))
                            .foregroundColor(Color.atlasSubtitle.opacity(0.7))
                    } else if !record.installedFiles.isEmpty {
                        Text(String(format: L(.filesTrackedFmt), record.installedFiles.count))
                            .font(.system(size: 10))
                            .foregroundColor(Color.atlasSubtitle.opacity(0.7))
                    }
                    if !formats.isEmpty {
                        formatInlineRow
                    }
                    Spacer()
                    verifyBadge
                }

                // ── Action buttons ─────────────────────────────────
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        if canUninstall {
                            if Features.isPro {
                                compactButton(label: L(.uninstall), icon: "trash",
                                              color: Color(hex: "#E05555"), action: onRollback)
                            } else {
                                compactButton(label: L(.uninstall), icon: "lock.fill",
                                              color: Color(hex: "#E05555")) {
                                    lockedFeatureName = L(.uninstall)
                                    showUpgradeAlert = true
                                }
                            }
                        }
                        if canRestore {
                            if Features.isPro {
                                compactButton(label: L(.recover), icon: "arrow.uturn.backward",
                                              color: Color(hex: "#3ECFB2"), action: onRestore)
                            } else {
                                compactButton(label: L(.recover), icon: "lock.fill",
                                              color: Color(hex: "#3ECFB2")) {
                                    lockedFeatureName = L(.recover)
                                    showUpgradeAlert = true
                                }
                            }
                        }
                        if permanentlyDeleted {
                            HStack(spacing: 3) {
                                Image(systemName: "trash.slash")
                                    .font(.system(size: 7, weight: .semibold))
                                Text(L(.permanentlyDeleted))
                                    .font(.system(size: 8, weight: .medium))
                                    .lineLimit(1)
                            }
                            .foregroundColor(Color.atlasSubtitle.opacity(0.6))
                            .padding(.horizontal, 5).padding(.vertical, 3)
                            .background(Color.atlasElevated)
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                            .help("The files from this uninstall were removed from Trash and can no longer be recovered.")
                        }
                        Spacer()
                    }
                    HStack(spacing: 4) {
                        if record.status == .success {
                            if record.feedbackSubmittedAt != nil {
                                // Feedback already submitted
                                HStack(spacing: 3) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 8, weight: .semibold))
                                    Text(L(.feedbackReceived))
                                        .font(.system(size: 9, weight: .semibold))
                                }
                                .foregroundColor(Color(hex: "#3ECFB2").opacity(0.6))
                                .padding(.horizontal, 6).padding(.vertical, 3)
                                .background(Color(hex: "#3ECFB2").opacity(0.05))
                                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                            } else {
                                compactButton(label: L(.feedback), icon: "brain.head.profile",
                                              color: Color(hex: "#3ECFB2")) { onFeedback?() }
                            }
                        }
                        compactButton(label: L(.support), icon: "questionmark.circle",
                                      color: Color(hex: "#696E7C")) { onSupport?() }
                        // Formats ▾/▴ — collapsed by default; expands Enable/Disable/Sign panel
                        if !formats.isEmpty {
                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    isExpanded.toggle()
                                }
                            } label: {
                                HStack(spacing: 3) {
                                    Text(L(.formatsLabel))
                                        .font(.system(size: 9, weight: .semibold))
                                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                        .font(.system(size: 7, weight: .semibold))
                                }
                                .foregroundColor(isExpanded ? Color.atlasInfo : Color.atlasSubtitle.opacity(0.6))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(isExpanded
                                    ? Color.atlasInfo.opacity(0.10)
                                    : Color.atlasElevated)
                                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .strokeBorder(
                                        isExpanded ? Color.atlasInfo.opacity(0.25) : Color.clear,
                                        lineWidth: 0.75))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Plugin formats")
                            .accessibilityHint("Expand to show Enable, Disable, and Code-Sign controls for each format")
                            .help("Show format controls: Enable, Disable, Code-Sign")
                        }
                        Spacer()
                    }
                }
            }
            .padding(.horizontal, inSession ? 18 : 12)
            .padding(.vertical, 9)

            // ── Expanded section: format rows ─────────────────────────
            if isExpanded && !formats.isEmpty {
                Rectangle()
                    .fill(Color.atlasSeparator.opacity(0.4))
                    .frame(height: 1)
                    .padding(.leading, inSession ? 18 : 12)

                VStack(spacing: 0) {
                    ForEach(formats) { fmt in
                        formatRow(fmt)
                    }
                }
                .padding(.bottom, 6)
            }
        }
        .background(hovered ? Color.atlasHover : Color.clear)
        .onHover { hovered = $0 }
        .animation(.atlasHoverIn, value: hovered)
        .onAppear { checkTrashFiles() }
        // Error alert for Enable/Disable
        .alert("Error", isPresented: .init(
            get: { toggleError != nil },
            set: { if !$0 { toggleError = nil } }
        )) {
            Button("OK", role: .cancel) { toggleError = nil }
        } message: {
            Text(toggleError ?? "")
        }
        // Disable confirmation alert (Phase 8)
        .alert(String(format: L(.disableFmtConfirmTitleFmt), pendingDisableRow?.label ?? ""), isPresented: $showDisableConfirm) {
            Button(L(.cancel), role: .cancel) { pendingDisableRow = nil }
            Button(L(.disable), role: .destructive) {
                if let row = pendingDisableRow {
                    pendingDisableRow = nil
                    Task { await performDisable(row: row) }
                }
            }
        } message: {
            if let row = pendingDisableRow {
                Text(String(format: L(.disableFmtConfirmMsgFmt), record.fileName, row.label))
            }
        }
        // Code-Sign error alert
        .alert("Code-Sign Failed", isPresented: $showSignError) {
            Button("OK", role: .cancel) { signError = nil }
        } message: {
            Text(signError ?? "")
        }
        .alert(String(format: L(.proFeatureAlertTitleFmt), lockedFeatureName), isPresented: $showUpgradeAlert) {
            Button(L(.upgrade)) {
                NSWorkspace.shared.open(URL(string: "https://interlinked.digital/account")!)
            }
            Button(L(.cancel), role: .cancel) {}
        } message: {
            Text(String(format: L(.proFeatureAlertMsgFmt), lockedFeatureName))
        }
    }

    // MARK: - Format inline row (display-only — dot-separated format names, no toggle here)
    // Trigger for expand/collapse moved to the action row next to Support.

    @ViewBuilder
    private var formatInlineRow: some View {
        HStack(spacing: 0) {
            ForEach(formats) { fmt in
                let isDisabled = record.disabledFormats?.contains { $0.originalPath == fmt.destinationPath } ?? false
                Text(" · \(fmt.label)")
                    .font(.system(size: 10))
                    .foregroundColor(
                        isDisabled
                            ? Color.atlasSubtitle.opacity(0.35)
                            : Color.atlasInfo.opacity(0.75)   // informational → blue
                    )
            }
        }
    }

    // MARK: - Verify badge

    @ViewBuilder
    private var verifyBadge: some View {
        if record.demoDetected == true {
            HStack(spacing: 3) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 7, weight: .bold))
                Text("DEMO MODE")
                    .font(.system(size: 7, weight: .bold)).tracking(1)
            }
            .foregroundColor(Color(hex: "#F0A030"))
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(Color(hex: "#F0A030").opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(Color(hex: "#F0A030").opacity(0.3), lineWidth: 0.75))
        } else if record.titanVerified == true {
            HStack(spacing: 3) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 7, weight: .bold))
                Text("TITAN VERIFIED™")
                    .font(.system(size: 7, weight: .bold)).tracking(1)
            }
            .foregroundColor(Color(hex: "#3ECFB2"))
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(Color(hex: "#3ECFB2").opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(Color(hex: "#3ECFB2").opacity(0.25), lineWidth: 0.75))
        }
    }

    // MARK: - Format row (expanded)

    @ViewBuilder
    private func formatRow(_ fmt: PluginFormatRow) -> some View {
        let disabledEntry = record.disabledFormats?.first { $0.originalPath == fmt.destinationPath }
        let isDisabled = disabledEntry != nil

        HStack(spacing: 8) {
            // Format badge
            Text(fmt.label)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(isDisabled ? Color.atlasSubtitle.opacity(0.5) : Color(hex: "#3ECFB2"))
                .frame(width: 32, alignment: .leading)

            // Path / state
            if isDisabled {
                Text(L(.disabled))
                    .font(.system(size: 9))
                    .foregroundColor(Color.atlasSubtitle.opacity(0.6))
            } else {
                Text(URL(fileURLWithPath: fmt.destinationPath).lastPathComponent)
                    .font(.system(size: 9))
                    .foregroundColor(Color.atlasSubtitle.opacity(0.8))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            // Show in Finder button (Phase 7)
            Button {
                showInFinder(fmt: fmt, disabledEntry: disabledEntry)
            } label: {
                Image(systemName: "folder")
                    .font(.system(size: 9))
                    .foregroundColor(Color.atlasSubtitle.opacity(0.5))
            }
            .buttonStyle(.plain)
            .help("Show in Finder")
            .disabled(isTogglingFormat)

            // Enable/Disable button (Phase 8, Pro only)
            if record.status == .success {
                if Features.enableDisable {
                    if isTogglingFormat {
                        ProgressView()
                            .scaleEffect(0.5)
                            .frame(width: 40, height: 16)
                    } else if isDisabled {
                        compactButton(label: L(.enable), icon: "checkmark.circle",
                                      color: Color(hex: "#3ECFB2")) {
                            Task { await performEnable(entry: disabledEntry!, fmt: fmt) }
                        }
                        .disabled(isSigningFormat != nil)
                    } else {
                        compactButton(label: L(.disable), icon: "minus.circle",
                                      color: Color(hex: "#E05555")) {
                            pendingDisableRow = fmt
                            showDisableConfirm = true
                        }
                        .disabled(isSigningFormat != nil)
                    }
                } else {
                    // Standard user — show locked Pro badge
                    Button {
                        lockedFeatureName = L(.enable) + "/" + L(.disable)
                        showUpgradeAlert = true
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 7, weight: .semibold))
                            Text("PRO")
                                .font(.system(size: 7, weight: .bold))
                        }
                        .foregroundColor(Color.atlasSubtitle.opacity(0.5))
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Color.atlasElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }

            // Code-Sign button (Pro only)
            if record.status == .success {
                if Features.codeSign {
                    let signingThis    = isSigningFormat == fmt.formatKey
                    let successThis    = signSuccessFormat == fmt.formatKey
                    let otherSigning   = isSigningFormat != nil && isSigningFormat != fmt.formatKey

                    if signingThis {
                        HStack(spacing: 4) {
                            ProgressView()
                                .scaleEffect(0.5)
                                .frame(width: 12, height: 12)
                            Text(L(.signingLabel))
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(Color.atlasSubtitle.opacity(0.7))
                        }
                    } else if successThis {
                        HStack(spacing: 3) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 8, weight: .semibold))
                            Text(L(.signedLabel))
                                .font(.system(size: 9, weight: .semibold))
                        }
                        .foregroundColor(Color(hex: "#3ECFB2"))
                        .padding(.horizontal, 6).padding(.vertical, 3)
                    } else {
                        compactButton(label: L(.sign), icon: "pencil",
                                      color: Color(hex: "#3ECFB2")) {
                            Task { await performCodeSign(fmt: fmt) }
                        }
                        .disabled(isTogglingFormat || otherSigning)
                    }
                } else {
                    // Standard user — locked Pro badge for Code-Sign
                    Button {
                        lockedFeatureName = L(.sign)
                        showUpgradeAlert = true
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 7, weight: .semibold))
                            Text("PRO")
                                .font(.system(size: 7, weight: .bold))
                        }
                        .foregroundColor(Color.atlasSubtitle.opacity(0.5))
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Color.atlasElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, inSession ? 18 : 12)
        .padding(.vertical, 5)
        .background(Color.atlasDeepBG.opacity(0.5))
    }

    // MARK: - Show in Finder (Phase 7)

    private func showInFinder(fmt: PluginFormatRow, disabledEntry: DisabledFormatEntry?) {
        let targetPath: String
        if let entry = disabledEntry {
            targetPath = entry.disabledStoragePath
        } else {
            targetPath = fmt.destinationPath
        }
        guard FileManager.default.fileExists(atPath: targetPath) else {
            toggleError = "The file could not be found at its expected location:\n\(targetPath)"
            return
        }
        NSWorkspace.shared.selectFile(targetPath, inFileViewerRootedAtPath: "")
    }

    // MARK: - Enable / Disable (Phase 8)

    @MainActor
    private func performDisable(row: PluginFormatRow) async {
        guard Features.enableDisable else {
            lockedFeatureName = "Enable/Disable"
            showUpgradeAlert = true
            return
        }
        isTogglingFormat = true
        let result = await PluginToggleEngine.disable(
            destinationPath: row.destinationPath,
            formatKey: row.formatKey,
            record: record,
            allRecords: store.records
        )
        isTogglingFormat = false
        switch result {
        case .success(let entry):
            store.markFormatDisabled(id: record.id, entry: entry)
        case .failure(let err):
            toggleError = err.message
        }
    }

    @MainActor
    private func performEnable(entry: DisabledFormatEntry, fmt: PluginFormatRow) async {
        guard Features.enableDisable else {
            lockedFeatureName = "Enable/Disable"
            showUpgradeAlert = true
            return
        }
        isTogglingFormat = true
        let result = await PluginToggleEngine.enable(entry: entry, allRecords: store.records)
        isTogglingFormat = false
        switch result {
        case .success:
            store.markFormatEnabled(id: record.id, originalPath: entry.originalPath)
        case .failure(let err):
            toggleError = err.message
        }
    }

    // MARK: - Code-Sign

    @MainActor
    private func performCodeSign(fmt: PluginFormatRow) async {
        guard Features.codeSign else {
            lockedFeatureName = "Code-Sign"
            showUpgradeAlert = true
            return
        }
        // Determine physical location: disabled storage path or installed path
        let disabledEntry = record.disabledFormats?.first { $0.originalPath == fmt.destinationPath }
        let targetPath = disabledEntry?.disabledStoragePath ?? fmt.destinationPath

        isSigningFormat = fmt.formatKey
        let result = await PluginCodeSignEngine.sign(pluginPath: targetPath, record: record)
        isSigningFormat = nil

        switch result {
        case .success:
            signSuccessFormat = fmt.formatKey
            // Clear the success badge after ~2 seconds
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                await MainActor.run { signSuccessFormat = nil }
            }
        case .failure(let err):
            signError = err.message
            showSignError = true
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func compactButton(label: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 8, weight: .semibold))
                Text(label)
                    .font(.system(size: 9, weight: .semibold))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .foregroundColor(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(color.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(color.opacity(0.2), lineWidth: 0.75))
        }
        .buttonStyle(.plain)
    }

    private func checkTrashFiles() {
        guard record.status == .uninstalled,
              let backupPath = record.rollbackBackupPath else { return }
        DispatchQueue.global(qos: .utility).async {
            let exists: Bool
            if let data = try? Data(contentsOf: URL(fileURLWithPath: backupPath)),
               let records = try? JSONDecoder().decode([TrashRecord].self, from: data) {
                exists = records.contains { FileManager.default.fileExists(atPath: $0.trashPath) }
            } else {
                exists = false
            }
            DispatchQueue.main.async { trashFilesExist = exists }
        }
    }
}

// MARK: - Archive Item Card

private enum ArchiveFileStatus {
    case present   // files still at original location
    case inTrash   // files in Trash (recoverable)
    case missing   // files cannot be found
}

private struct ArchiveItemCard: View {
    let record: InstallRecord
    @ObservedObject var store: HistoryStore
    @ObservedObject private var langMgr = LanguageManager.shared
    let onRestore: (InstallRecord) -> Void

    @State private var fileStatus: ArchiveFileStatus? = nil
    @State private var showDeleteConfirm = false

    private var archivedDateStr: String {
        guard let d = record.archivedAt else { return "" }
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: d)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            // Title row
            HStack(spacing: 7) {
                Image(systemName: record.statusIcon)
                    .foregroundColor(Color.atlasSubtitle.opacity(0.4))
                    .font(.system(size: 11))
                Text(record.fileName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color.atlasLabel.opacity(0.55))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Text(record.fileType)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(Color.atlasSubtitle.opacity(0.45))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.atlasElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            }

            // Date + file status row
            HStack(spacing: 4) {
                Text(String(format: L(.installedOnFmt), record.shortDate))
                    .font(.system(size: 10))
                    .foregroundColor(Color.atlasSubtitle.opacity(0.5))
                if !archivedDateStr.isEmpty {
                    Text("·")
                        .font(.system(size: 10))
                        .foregroundColor(Color.atlasSubtitle.opacity(0.3))
                    Text(String(format: L(.archivedOnFmt), archivedDateStr))
                        .font(.system(size: 10))
                        .foregroundColor(Color.atlasSubtitle.opacity(0.5))
                }
                Spacer()
                if let status = fileStatus {
                    fileStatusBadge(status)
                }
            }

            // Actions
            HStack(spacing: 4) {
                Button {
                    store.unarchive(id: record.id)
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.uturn.up.circle")
                            .font(.system(size: 8, weight: .semibold))
                        Text(L(.unArchive))
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundColor(Color(hex: "#3ECFB2"))
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(Color(hex: "#3ECFB2").opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(Color(hex: "#3ECFB2").opacity(0.2), lineWidth: 0.75))
                }
                .buttonStyle(.plain)
                .help("Move back to active Library (does not reinstall files)")

                if fileStatus == .inTrash {
                    Button { onRestore(record) } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.uturn.backward")
                                .font(.system(size: 8, weight: .semibold))
                            Text(L(.recover))
                                .font(.system(size: 9, weight: .semibold))
                        }
                        .foregroundColor(Color(hex: "#3ECFB2"))
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(Color(hex: "#3ECFB2").opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .strokeBorder(Color(hex: "#3ECFB2").opacity(0.2), lineWidth: 0.75))
                    }
                    .buttonStyle(.plain)
                    .help("Restore files from Trash to their original locations")
                }

                Spacer()

                Button { showDeleteConfirm = true } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 9))
                        .foregroundColor(Color(hex: "#E05555").opacity(0.5))
                }
                .buttonStyle(.plain)
                .help("Permanently delete this archive record — no files are affected")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .onAppear { checkFileStatus() }
        .alert(L(.deleteArchiveTitle), isPresented: $showDeleteConfirm) {
            Button(L(.cancel), role: .cancel) {}
            Button(L(.deleteAll), role: .destructive) {
                store.deleteArchivedRecord(id: record.id)
            }
        } message: {
            Text(String(format: L(.deleteArchiveMsgFmt), record.fileName))
        }
    }

    @ViewBuilder
    private func fileStatusBadge(_ status: ArchiveFileStatus) -> some View {
        switch status {
        case .present:
            HStack(spacing: 3) {
                Image(systemName: "checkmark.circle").font(.system(size: 7, weight: .semibold))
                Text(L(.filesPresent)).font(.system(size: 8, weight: .medium))
            }
            .foregroundColor(Color(hex: "#2ECC8A").opacity(0.7))
        case .inTrash:
            HStack(spacing: 3) {
                Image(systemName: "trash").font(.system(size: 7, weight: .semibold))
                Text(L(.inTrash)).font(.system(size: 8, weight: .medium))
            }
            .foregroundColor(Color(hex: "#F0A030").opacity(0.8))
        case .missing:
            HStack(spacing: 3) {
                Image(systemName: "xmark.circle").font(.system(size: 7, weight: .semibold))
                Text(L(.filesGone)).font(.system(size: 8, weight: .medium))
            }
            .foregroundColor(Color.atlasSubtitle.opacity(0.45))
        }
    }

    private func checkFileStatus() {
        DispatchQueue.global(qos: .utility).async {
            let status = detectFileStatus()
            DispatchQueue.main.async { self.fileStatus = status }
        }
    }

    private func detectFileStatus() -> ArchiveFileStatus {
        let anyPresent = record.installedFiles.contains {
            FileManager.default.fileExists(atPath: $0.destinationPath)
        }
        if anyPresent { return .present }

        if let backupPath = record.rollbackBackupPath,
           let data = try? Data(contentsOf: URL(fileURLWithPath: backupPath)),
           let trashRecords = try? JSONDecoder().decode([TrashRecord].self, from: data) {
            if trashRecords.contains(where: { FileManager.default.fileExists(atPath: $0.trashPath) }) {
                return .inTrash
            }
        }

        return .missing
    }
}

// MARK: - Library Feedback Sheet

struct HistoryFeedbackSheet: View {
    let record: InstallRecord
    @ObservedObject var store: HistoryStore
    @Environment(\.dismiss) private var dismiss

    private var installLog: String { loadLog(for: record) ?? "" }

    private var productName: String {
        record.fileName
            .replacingOccurrences(of: ".zip",  with: "")
            .replacingOccurrences(of: ".dmg",  with: "")
            .replacingOccurrences(of: ".pkg",  with: "")
            .replacingOccurrences(of: ".rar",  with: "")
            .replacingOccurrences(of: ".iso",  with: "")
    }

    var body: some View {
        InstallFeedbackPrompt(
            productName: productName,
            steps: [],
            hostsEntries: record.addedHostsEntries ?? [],
            installLog: installLog,
            installRecord: record,
            historyStore: store,
            onDismiss: { dismiss() }
        )
        .frame(width: 360)
        .padding(20)
        .background(Color.atlasDeepBG)
    }

    private func loadLog(for record: InstallRecord) -> String? {
        let logsBase = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/ATLAS/Installed")
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let prefix = "Install_\(df.string(from: record.date))_"
        let escaped = record.fileName.replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "/", with: "_")
        let name = prefix + escaped + ".log"
        let path = logsBase.appendingPathComponent(name)
        return try? String(contentsOf: path, encoding: .utf8)
    }
}
