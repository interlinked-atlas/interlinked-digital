import SwiftUI

struct LibraryDashboardView: View {
    @ObservedObject var store: HistoryStore
    @ObservedObject var logger: Logger
    var onClose: (() -> Void)? = nil
    let onRollback: (InstallRecord) -> Void
    let onRestore: (InstallRecord) -> Void
    let onBatchRollback: ([InstallRecord]) -> Void
    var onStartRecovery: ((AtlasKit) -> Void)? = nil

    @StateObject private var viewModel: LibraryDashboardViewModel
    @StateObject private var cleanerEngine = ATLASCleanerEngine()
    @StateObject private var kitEngine = RecoveryKitEngine()

    @State private var showClearConfirm = false
    @State private var showCleaner = false
    @State private var showQuickScan = false
    @State private var showUpgradeForCleaner = false
    @State private var showInstalledProducts = false   // collapsed by default
    @State private var showRecoveryKit = false         // collapsed by default
    @State private var productSearchText = ""

    init(store: HistoryStore,
         logger: Logger,
         onClose: (() -> Void)? = nil,
         onRollback: @escaping (InstallRecord) -> Void,
         onRestore: @escaping (InstallRecord) -> Void,
         onBatchRollback: @escaping ([InstallRecord]) -> Void,
         onStartRecovery: ((AtlasKit) -> Void)? = nil) {
        self.store = store
        self.logger = logger
        self.onClose = onClose
        self.onRollback = onRollback
        self.onRestore = onRestore
        self.onBatchRollback = onBatchRollback
        self.onStartRecovery = onStartRecovery
        _viewModel = StateObject(wrappedValue: LibraryDashboardViewModel(store: store))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
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
                Text("ATLAS Library")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color.atlasLabel)
                Spacer()
                if !store.records.isEmpty {
                    Button("Clear All") { showClearConfirm = true }
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Color(hex: "#E05555").opacity(0.85))
                        .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)

            Rectangle().fill(Color.atlasSeparator).frame(height: 1)

            // Scrollable dashboard
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    LibraryOverviewSection(viewModel: viewModel)

                    // Collapsible Installed Products accordion — collapsed by default
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                            showInstalledProducts.toggle()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "square.stack.3d.down.right.fill")
                                .font(.system(size: 9))
                                .foregroundColor(Color.atlasSubtitle.opacity(0.55))
                            Text(installedProductsHeaderText)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(Color.atlasSubtitle.opacity(0.75))
                            Spacer()
                            Image(systemName: showInstalledProducts ? "chevron.up" : "chevron.down")
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundColor(Color.atlasSubtitle.opacity(0.4))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                    }
                    .buttonStyle(.plain)
                    .background(Color.atlasDeepBG)

                    if showInstalledProducts {
                        if !store.records.isEmpty {
                            productSearchField
                        }
                        InstalledProductsSection(
                            store: store, logger: logger,
                            scrollable: false,
                            externalSearch: $productSearchText,
                            onRollback: onRollback,
                            onRestore: onRestore,
                            onBatchRollback: onBatchRollback
                        )
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    sectionLabel("STORAGE")
                    ATLASStorageSectionView(
                        store: store,
                        engine: cleanerEngine,
                        onReviewCleaner: { showCleaner = true },
                        onUpgradeCleaner: { showUpgradeForCleaner = true },
                        onQuickScan: { showQuickScan = true }
                    )

                    // Collapsible Recovery Kit accordion — collapsed by default
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                            showRecoveryKit.toggle()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "lifepreserver")
                                .font(.system(size: 9))
                                .foregroundColor(Color.atlasSubtitle.opacity(0.55))
                            Text("RECOVERY KIT")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(Color.atlasSubtitle.opacity(0.75))
                            Spacer()
                            Image(systemName: showRecoveryKit ? "chevron.up" : "chevron.down")
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundColor(Color.atlasSubtitle.opacity(0.4))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                    }
                    .buttonStyle(.plain)
                    .background(Color.atlasDeepBG)
                    .tourAnchor("recoveryKitSection")

                    if showRecoveryKit {
                        RecoveryKitView(engine: kitEngine, store: store, onStartRecovery: onStartRecovery)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            }
        }
        .frame(width: 320)
        .background(Color.atlasSessionHeader)
        .alert("Clear ATLAS Library?", isPresented: $showClearConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Clear All", role: .destructive) { store.clearAll() }
        } message: {
            Text("All \(store.records.count) install records will be moved to Archive. Installed files are not affected. You can Un-Archive any record at any time.")
        }
        .sheet(isPresented: $showCleaner, onDismiss: {
            Task { await cleanerEngine.scan(store: store) }
        }) {
            ATLASCleanerView(engine: cleanerEngine, store: store)
        }
        .sheet(isPresented: $showQuickScan) {
            QuickScanView(store: store)
        }
        .onChange(of: showInstalledProducts) { open in
            if !open { productSearchText = "" }
        }
        .alert("ATLAS CLEANER™ — Pro Feature", isPresented: $showUpgradeForCleaner) {
            Button("Upgrade to Pro") {
                NSWorkspace.shared.open(URL(string: "https://interlinked.digital/account")!)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("ATLAS CLEANER™ is available on the Pro plan. Visit interlinked.digital/account and sign in with the email you use in the ATLAS app.")
        }
    }

    private var installedProductsHeaderText: String {
        let count = store.records.count
        if count == 0 { return "Products" }
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        let dateStr = store.records.first.map { f.string(from: $0.date) } ?? ""
        return "Products · \(count) · \(dateStr)"
    }

    private var productSearchField: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(Color.atlasSubtitle.opacity(0.6))
            TextField("Search for Software…", text: $productSearchText)
                .font(.system(size: 11))
                .foregroundColor(Color.atlasLabel)
                .textFieldStyle(.plain)
            if !productSearchText.isEmpty {
                Button { productSearchText = "" } label: {
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
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 9, weight: .semibold))
            .foregroundColor(Color.atlasSubtitle.opacity(0.5))
            .padding(.horizontal, 12)
            .padding(.top, 14)
            .padding(.bottom, 6)
    }

}
