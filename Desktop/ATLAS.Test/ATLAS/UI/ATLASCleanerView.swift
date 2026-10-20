import SwiftUI

struct ATLASCleanerView: View {
    @ObservedObject var engine: ATLASCleanerEngine
    @ObservedObject var store: HistoryStore
    @ObservedObject private var history = CleanerHistoryStore.shared
    @ObservedObject private var langMgr = LanguageManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var scanInitiated      = false
    @State private var selectedIDs        = Set<UUID>()
    @State private var expandedCategories = Set<CleanerCategory>()
    @State private var showConfirm        = false
    @State private var showingHistory     = false
    @State private var animDot            = 0

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
                .background(Color.atlasSeparator)

            if showingHistory {
                historyView
            } else if engine.trashState == .trashing {
                trashingView
            } else if engine.trashState == .complete, !engine.trashResults.isEmpty {
                trashCompleteView
            } else if !scanInitiated {
                initialView
            } else if case .scanning = engine.scanState {
                scanningView
            } else if engine.items.isEmpty {
                emptyView
            } else {
                resultsView
            }
        }
        .frame(width: 460, height: 540)
        .background(Color.atlasSessionHeader)
        // Auto-select non-review items when scan completes
        .onChange(of: engine.scanState) { state in
            if case .complete = state {
                selectedIDs = Set(engine.items.filter { !$0.isReviewOnly }.map { $0.id })
                expandedCategories = Set(
                    CleanerCategory.allCases.filter { cat in
                        engine.items.contains { $0.category == cat }
                    }
                )
            }
        }
        // Dot animation while scanning
        .task(id: engine.isScanning) {
            guard engine.isScanning else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 450_000_000)
                animDot = (animDot + 1) % 3
            }
        }
        .alert("Move to Trash?", isPresented: $showConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Move \(selectedIDs.count) item\(selectedIDs.count == 1 ? "" : "s") to Trash",
                   role: .destructive) {
                Task { await engine.trash(selectedIDs: selectedIDs, store: store) }
            }
        } message: {
            Text("Selected items will be moved to the macOS Trash. Each item is re-verified immediately before removal. Items that no longer meet ATLAS Cleaner criteria are skipped automatically.")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color(hex: "#3ECFB2"))
            VStack(alignment: .leading, spacing: 0) {
                Text("ATLAS CLEANER™")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color.atlasLabel)
                Text(L(.quickClean))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(Color.atlasSubtitle.opacity(0.55))
            }
            Spacer()

            // Badge
            if case .complete = engine.scanState, !engine.items.isEmpty, !scanInitiated == false {
                let safe = engine.items.filter { !$0.isReviewOnly }.count
                let review = engine.items.filter { $0.isReviewOnly }.count
                if safe > 0 {
                    Text("\(safe) item\(safe == 1 ? "" : "s")")
                        .font(.system(size: 10))
                        .foregroundColor(Color.atlasSubtitle.opacity(0.6))
                }
                if review > 0 {
                    Text("· \(review) review")
                        .font(.system(size: 10))
                        .foregroundColor(Color.atlasSubtitle.opacity(0.4))
                }
            }

            Button {
                if showingHistory { showingHistory = false }
                else { dismiss() }
            } label: {
                Image(systemName: showingHistory ? "chevron.left" : "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Color.atlasSubtitle)
                    .frame(width: 20, height: 20)
                    .background(Color.atlasElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    // MARK: - Initial state

    private var initialView: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 18) {
                VStack(spacing: 6) {
                    Text(L(.scanSystemForClutter))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color.atlasLabel)
                        .multilineTextAlignment(.center)
                    Text(L(.itemsMovedToTrashNote))
                        .font(.system(size: 10))
                        .foregroundColor(Color.atlasSubtitle.opacity(0.6))
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 24)

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(initialCheckList, id: \.self) { label in
                        HStack(spacing: 8) {
                            Image(systemName: "circle")
                                .font(.system(size: 9))
                                .foregroundColor(Color.atlasSubtitle.opacity(0.3))
                            Text(label)
                                .font(.system(size: 11))
                                .foregroundColor(Color.atlasSubtitle.opacity(0.65))
                        }
                    }
                }
                .padding(.horizontal, 32)

                Button {
                    scanInitiated = true
                    Task { await engine.scan(store: store, deepScan: true) }
                } label: {
                    Text(L(.startScan))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color(hex: "#08090E"))
                        .padding(.horizontal, 28)
                        .padding(.vertical, 9)
                        .background(Color(hex: "#3ECFB2"))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            Spacer()

            historyLink
        }
    }

    private let initialCheckList = [
        "Duplicate plugins",
        "Redundant formats",
        "Duplicate installers",
        "Unused installers",
        "Incomplete downloads",
        "ATLAS storage",
    ]

    // MARK: - Scanning state

    private var scanningView: some View {
        VStack(spacing: 0) {
            // Animated header
            HStack(spacing: 6) {
                Text(L(.scanning))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color.atlasSubtitle.opacity(0.7))
                HStack(spacing: 3) {
                    ForEach(0..<3) { i in
                        Circle()
                            .fill(i <= animDot
                                  ? Color(hex: "#3ECFB2")
                                  : Color.atlasSubtitle.opacity(0.2))
                            .frame(width: 4, height: 4)
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: animDot)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 10)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    ForEach(CleanerCategory.allCases, id: \.self) { cat in
                        scanProgressRow(cat)
                        if cat != CleanerCategory.allCases.last {
                            Rectangle()
                                .fill(Color.atlasSeparator.opacity(0.4))
                                .frame(height: 1)
                                .padding(.leading, 36)
                        }
                    }
                }
                .padding(.bottom, 12)
            }
        }
    }

    @ViewBuilder
    private func scanProgressRow(_ category: CleanerCategory) -> some View {
        let state = engine.categoryProgress[category] ?? .pending
        HStack(spacing: 10) {
            ZStack {
                switch state {
                case .pending:
                    Image(systemName: "circle")
                        .font(.system(size: 11))
                        .foregroundColor(Color.atlasSubtitle.opacity(0.2))
                case .scanning:
                    ProgressView()
                        .scaleEffect(0.55)
                        .frame(width: 14, height: 14)
                case .complete(let n) where n == 0:
                    Image(systemName: "minus.circle")
                        .font(.system(size: 11))
                        .foregroundColor(Color.atlasSubtitle.opacity(0.3))
                case .complete:
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: "#3ECFB2"))
                case .error:
                    Image(systemName: "exclamationmark.circle")
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: "#F0A030"))
                }
            }
            .frame(width: 16)

            Text(categoryDisplayLabel(category))
                .font(.system(size: 11))
                .foregroundColor(categoryRowTextColor(state))

            Spacer()

            if case .complete(let n) = state, n > 0 {
                Text("\(n) item\(n == 1 ? "" : "s")")
                    .font(.system(size: 10))
                    .foregroundColor(Color(hex: "#3ECFB2"))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    private func categoryRowTextColor(_ state: CategoryScanState) -> Color {
        switch state {
        case .scanning: return Color.atlasLabel
        case .complete(let n) where n > 0: return Color.atlasLabel
        default: return Color.atlasSubtitle.opacity(0.45)
        }
    }

    // MARK: - Results state

    private var resultsView: some View {
        VStack(spacing: 0) {
            // Summary bar
            HStack {
                let safe   = engine.items.filter { !$0.isReviewOnly }.count
                let review = engine.items.filter { $0.isReviewOnly }.count
                if safe > 0 {
                    Text("\(safe) item\(safe == 1 ? "" : "s") can be safely cleaned")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color.atlasLabel)
                }
                if review > 0 {
                    if safe > 0 { Text("·")
                        .font(.system(size: 11))
                        .foregroundColor(Color.atlasSubtitle.opacity(0.4))
                    }
                    Text("\(review) for review")
                        .font(.system(size: 11))
                        .foregroundColor(Color.atlasSubtitle.opacity(0.6))
                }
                Spacer()
                if engine.totalReclaimableBytes > 0 {
                    Text(formattedSize(engine.totalReclaimableBytes))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color(hex: "#3ECFB2"))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)

            Rectangle().fill(Color.atlasSeparator.opacity(0.6)).frame(height: 1)

            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(CleanerCategory.allCases, id: \.self) { cat in
                        let catItems = engine.items.filter { $0.category == cat }
                        if !catItems.isEmpty {
                            categoryAccordion(category: cat, items: catItems)
                        }
                    }
                }
                .padding(.bottom, 8)
            }

            Rectangle().fill(Color.atlasSeparator).frame(height: 1)
            resultsFooter
        }
    }

    private func categoryAccordion(category: CleanerCategory, items: [CleanerItem]) -> some View {
        let isExpanded = expandedCategories.contains(category)
        let hasReview  = items.contains { $0.isReviewOnly }
        let selCount   = items.filter { selectedIDs.contains($0.id) }.count
        let totalCount = items.count
        let catBytes   = items.filter { !$0.isReviewOnly }.compactMap { $0.size }.reduce(0, +)

        return VStack(alignment: .leading, spacing: 0) {
            // Section header / accordion toggle
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    if expandedCategories.contains(category) { expandedCategories.remove(category) }
                    else { expandedCategories.insert(category) }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundColor(Color.atlasSubtitle.opacity(0.35))
                        .frame(width: 10)

                    Text(categoryDisplayLabel(category))
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(Color.atlasSubtitle.opacity(0.5))

                    Text("\(totalCount)")
                        .font(.system(size: 9))
                        .foregroundColor(Color.atlasSubtitle.opacity(0.4))

                    if hasReview {
                        Text("REVIEW")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundColor(Color(hex: "#F0A030"))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color(hex: "#F0A030").opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                    }

                    Spacer()

                    if selCount > 0 && !hasReview {
                        Text("\(selCount) selected")
                            .font(.system(size: 9))
                            .foregroundColor(Color.atlasSubtitle.opacity(0.4))
                    }
                    if catBytes > 0 {
                        Text(formattedSize(catBytes))
                            .font(.system(size: 9))
                            .foregroundColor(Color.atlasSubtitle.opacity(0.4))
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(spacing: 0) {
                    ForEach(items) { item in
                        itemRow(item)
                        if item.id != items.last?.id {
                            Rectangle()
                                .fill(Color.atlasSeparator.opacity(0.4))
                                .frame(height: 1)
                                .padding(.leading, 40)
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Rectangle().fill(Color.atlasSeparator.opacity(0.4)).frame(height: 1)
        }
    }

    private func itemRow(_ item: CleanerItem) -> some View {
        HStack(spacing: 10) {
            // Checkbox (review-only items show a lock icon instead)
            Button {
                guard !item.isReviewOnly else { return }
                if selectedIDs.contains(item.id) { selectedIDs.remove(item.id) }
                else { selectedIDs.insert(item.id) }
            } label: {
                if item.isReviewOnly {
                    Image(systemName: "eye")
                        .font(.system(size: 13))
                        .foregroundColor(Color(hex: "#F0A030").opacity(0.6))
                } else {
                    Image(systemName: selectedIDs.contains(item.id)
                          ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 13))
                        .foregroundColor(selectedIDs.contains(item.id)
                                         ? Color(hex: "#3ECFB2")
                                         : Color.atlasSubtitle.opacity(0.3))
                }
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(displayName(for: item))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color.atlasLabel)
                    .lineLimit(1)

                // Format pills for plugin categories
                if !item.formatExtensions.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(item.formatExtensions, id: \.self) { ext in
                            Text(ext.uppercased())
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundColor(Color.atlasSubtitle.opacity(0.6))
                                .padding(.horizontal, 4).padding(.vertical, 1)
                                .background(Color.atlasElevated)
                                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                        }
                    }
                }

                // "Kept" path indicator for duplicate items
                if let kp = item.keepPath {
                    Text("Kept: \(URL(fileURLWithPath: kp).deletingLastPathComponent().lastPathComponent)/…")
                        .font(.system(size: 9))
                        .foregroundColor(Color.atlasSubtitle.opacity(0.4))
                        .lineLimit(1)
                }

                Text(item.reason)
                    .font(.system(size: 10))
                    .foregroundColor(item.isReviewOnly
                                     ? Color(hex: "#F0A030").opacity(0.7)
                                     : Color.atlasSubtitle.opacity(0.5))
                    .lineLimit(2)
            }

            Spacer()

            if let size = item.size {
                Text(formattedSize(size))
                    .font(.system(size: 10))
                    .foregroundColor(Color.atlasSubtitle.opacity(0.4))
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(selectedIDs.contains(item.id) && !item.isReviewOnly
                    ? Color(hex: "#3ECFB2").opacity(0.05)
                    : Color.clear)
    }

    private var resultsFooter: some View {
        HStack(spacing: 8) {
            // Select / deselect all (only affects non-review items)
            let nonReview = engine.items.filter { !$0.isReviewOnly }
            let allSelected = !nonReview.isEmpty && nonReview.allSatisfy { selectedIDs.contains($0.id) }

            Button(allSelected ? L(.deselectAll) : L(.selectAll)) {
                if allSelected {
                    selectedIDs.subtract(nonReview.map { $0.id })
                } else {
                    selectedIDs.formUnion(nonReview.map { $0.id })
                }
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(Color.atlasSubtitle.opacity(0.6))
            .buttonStyle(.plain)
            .disabled(nonReview.isEmpty)

            Spacer()

            if !selectedIDs.isEmpty {
                let selectedSize = engine.items
                    .filter { selectedIDs.contains($0.id) && !$0.isReviewOnly }
                    .compactMap { $0.size }.reduce(0, +)
                if selectedSize > 0 {
                    Text(formattedSize(selectedSize))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Color(hex: "#3ECFB2"))
                }
            }

            Button {
                guard !selectedIDs.isEmpty else { return }
                showConfirm = true
            } label: {
                Text(selectedIDs.isEmpty
                     ? "Trash Selected"
                     : "Trash Selected (\(selectedIDs.count))")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(selectedIDs.isEmpty ? Color.atlasSubtitle.opacity(0.3) : .white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(selectedIDs.isEmpty
                                ? Color.atlasElevated
                                : Color(hex: "#E05555"))
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(selectedIDs.isEmpty)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    // MARK: - Trashing in-progress

    private var trashingView: some View {
        VStack(spacing: 14) {
            Spacer()
            ProgressView().scaleEffect(0.9)
            Text(L(.movingToTrash))
                .font(.system(size: 12))
                .foregroundColor(Color.atlasSubtitle.opacity(0.6))
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Trash complete

    private var trashCompleteView: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    trashSummaryRow
                    Rectangle().fill(Color.atlasSeparator.opacity(0.5)).frame(height: 1)
                        .padding(.vertical, 8)
                    ForEach(engine.trashResults.sorted { $0.key.uuidString < $1.key.uuidString }, id: \.key) { id, result in
                        let item = engine.items.first { $0.id == id }
                        trashResultRow(name: item.map { displayName(for: $0) } ?? id.uuidString.prefix(8) + "…",
                                       result: result)
                    }
                }
                .padding(.vertical, 10)
            }
            Rectangle().fill(Color.atlasSeparator).frame(height: 1)
            HStack {
                historyLink
                Spacer()
                Button(L(.done)) { dismiss() }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16).padding(.vertical, 7)
                    .background(Color(hex: "#3ECFB2"))
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
    }

    private var trashSummaryRow: some View {
        let s = engine.trashResults.values.filter { if case .success = $0 { return true }; return false }.count
        let sk = engine.trashResults.values.filter { if case .skipped = $0 { return true }; return false }.count
        let f = engine.trashResults.values.filter { if case .failed  = $0 { return true }; return false }.count

        return HStack(spacing: 14) {
            summaryChip(count: s,  label: "Moved to Trash", color: Color(hex: "#3ECFB2"))
            if sk > 0 { summaryChip(count: sk, label: "Skipped", color: Color.atlasSubtitle.opacity(0.5)) }
            if f  > 0 { summaryChip(count: f,  label: "Failed",  color: Color(hex: "#E05555")) }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 4)
    }

    private func summaryChip(count: Int, label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Text("\(count)").font(.system(size: 14, weight: .semibold, design: .rounded)).foregroundColor(color)
            Text(label).font(.system(size: 10)).foregroundColor(Color.atlasSubtitle.opacity(0.65))
        }
    }

    private func trashResultRow(name: some StringProtocol, result: TrashResult) -> some View {
        HStack(spacing: 10) {
            trashResultIcon(result)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color.atlasLabel).lineLimit(1)
                Text(trashResultDesc(result))
                    .font(.system(size: 10))
                    .foregroundColor(trashResultColor(result)).lineLimit(2)
            }
            Spacer()
        }
        .padding(.horizontal, 14).padding(.vertical, 7)
    }

    private func trashResultIcon(_ result: TrashResult) -> some View {
        let (name, color): (String, Color) = {
            switch result {
            case .success: return ("checkmark.circle.fill", Color(hex: "#3ECFB2"))
            case .skipped: return ("minus.circle.fill",     Color.atlasSubtitle.opacity(0.4))
            case .failed:  return ("xmark.circle.fill",     Color(hex: "#E05555"))
            }
        }()
        return Image(systemName: name).font(.system(size: 13)).foregroundColor(color)
    }

    private func trashResultDesc(_ result: TrashResult) -> String {
        switch result {
        case .success:          return "Moved to Trash"
        case .skipped(let m):   return "Skipped — \(m)"
        case .failed(let m):    return "Failed — \(m)"
        }
    }

    private func trashResultColor(_ result: TrashResult) -> Color {
        switch result {
        case .success: return Color(hex: "#3ECFB2").opacity(0.8)
        case .skipped: return Color.atlasSubtitle.opacity(0.5)
        case .failed:  return Color(hex: "#E05555").opacity(0.8)
        }
    }

    // MARK: - Empty state

    private var emptyView: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "checkmark.seal")
                .font(.system(size: 28, weight: .light))
                .foregroundColor(Color(hex: "#3ECFB2").opacity(0.7))
            Text(L(.noCleanupFound))
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Color.atlasLabel)
            Text(L(.systemIsClean))
                .font(.system(size: 10))
                .foregroundColor(Color.atlasSubtitle.opacity(0.5))
            Spacer()
            historyLink.padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Cleaner History

    private var historyView: some View {
        VStack(spacing: 0) {
            if history.sessions.isEmpty {
                VStack(spacing: 10) {
                    Spacer()
                    Image(systemName: "clock")
                        .font(.system(size: 24, weight: .light))
                        .foregroundColor(Color.atlasSubtitle.opacity(0.3))
                    Text(L(.noCleanerHistory))
                        .font(.system(size: 11))
                        .foregroundColor(Color.atlasSubtitle.opacity(0.5))
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(history.sessions) { session in
                            sessionRow(session)
                        }
                    }
                    .padding(.bottom, 12)
                }
            }
        }
    }

    private func sessionRow(_ session: CleanerSession) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Session header
            HStack {
                Text(sessionDateLabel(session.sessionDate))
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(Color.atlasSubtitle.opacity(0.45))
                Spacer()
            }
            .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 6)

            ForEach(session.entries) { entry in
                historyEntryRow(session: session, entry: entry)
                Rectangle()
                    .fill(Color.atlasSeparator.opacity(0.4)).frame(height: 1)
                    .padding(.leading, 14)
            }
        }
    }

    private func historyEntryRow(session: CleanerSession, entry: CleanerHistoryEntry) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color.atlasLabel).lineLimit(1)
                HStack(spacing: 4) {
                    Text(CleanerCategory(rawValue: entry.category).map { categoryDisplayLabel($0) } ?? entry.category)
                        .font(.system(size: 9))
                        .foregroundColor(Color.atlasSubtitle.opacity(0.45))
                    if let size = entry.size {
                        Text("·").font(.system(size: 9))
                            .foregroundColor(Color.atlasSubtitle.opacity(0.3))
                        Text(formattedSize(size)).font(.system(size: 9))
                            .foregroundColor(Color.atlasSubtitle.opacity(0.45))
                    }
                }
                if let recovered = entry.recoveredAt {
                    Text("Restored \(shortTime(recovered))")
                        .font(.system(size: 9))
                        .foregroundColor(Color(hex: "#3ECFB2").opacity(0.7))
                }
            }

            Spacer()

            if entry.recoveredAt == nil {
                HistoryRestoreButton(session: session, entry: entry)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "#3ECFB2").opacity(0.6))
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
    }

    // MARK: - History link (shared across views)

    private var historyLink: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) { showingHistory = true }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "clock")
                    .font(.system(size: 9))
                    .foregroundColor(Color.atlasSubtitle.opacity(0.4))
                Text(L(.cleanerHistory))
                    .font(.system(size: 10))
                    .foregroundColor(Color.atlasSubtitle.opacity(0.5))
                Image(systemName: "chevron.right")
                    .font(.system(size: 8))
                    .foregroundColor(Color.atlasSubtitle.opacity(0.3))
            }
        }
        .buttonStyle(.plain)
        .padding(.bottom, 2)
    }

    // MARK: - Helpers

    private func displayName(for item: CleanerItem) -> String {
        if let name = item.productName, !name.isEmpty { return name }
        return URL(fileURLWithPath: item.path).lastPathComponent
    }

    private func categoryDisplayLabel(_ category: CleanerCategory) -> String {
        switch category {
        case .orphanedDisabledStorage: return "ATLAS Storage"
        case .staleStagingEntry:       return "ATLAS Staging"
        case .expiredRollbackBackup:   return "Expired Backups"
        case .incompleteDownload:      return "Incomplete Downloads"
        case .unusedInstaller:         return "Unused Installers"
        case .duplicatePlugin:         return "Duplicate Plugins"
        case .redundantFormat:         return "Redundant Formats"
        case .duplicateInstaller:      return "Duplicate Installers"
        case .atlasInstallerArtifact:  return "ATLAS Installation Files"
        }
    }

    private func formattedSize(_ bytes: Int64) -> String {
        guard bytes > 0 else { return "—" }
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowedUnits = [.useGB, .useMB, .useKB]
        return f.string(fromByteCount: bytes)
    }

    private func sessionDateLabel(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "TODAY · \(shortTime(date))" }
        if cal.isDateInYesterday(date) { return "YESTERDAY · \(shortTime(date))" }
        let f = DateFormatter()
        f.dateFormat = "MMM d · h:mm a"
        return f.string(from: date).uppercased()
    }

    private func shortTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f.string(from: date)
    }
}

// MARK: - Restore button (separate view to hold async state cleanly)

private struct HistoryRestoreButton: View {
    let session: CleanerSession
    let entry: CleanerHistoryEntry

    @State private var restoring = false
    @State private var resultMsg: String? = nil

    var body: some View {
        if let msg = resultMsg {
            Text(msg)
                .font(.system(size: 9))
                .foregroundColor(Color.atlasSubtitle.opacity(0.45))
                .lineLimit(2)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 120)
        } else if restoring {
            ProgressView().scaleEffect(0.5).frame(width: 20, height: 20)
        } else {
            Button("Restore") {
                restoring = true
                Task {
                    let result = await CleanerHistoryStore.shared.restore(
                        sessionID: session.id, entryID: entry.id
                    )
                    await MainActor.run {
                        restoring = false
                        switch result {
                        case .success:
                            resultMsg = "Restored"
                        case .notInTrash(let path):
                            resultMsg = "No longer in Trash\n\(URL(fileURLWithPath: path).lastPathComponent)"
                        case .failed(let err):
                            resultMsg = "Failed: \(err)"
                        }
                    }
                }
            }
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(Color(hex: "#3ECFB2"))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Color(hex: "#3ECFB2").opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            .buttonStyle(.plain)
        }
    }
}
