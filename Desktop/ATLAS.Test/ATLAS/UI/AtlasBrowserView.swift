import SwiftUI

/// "ATLAS Browser" — a Netflix-style catalog of third-party software ATLAS
/// doesn't host. Users browse/search, tap a card to see details, then
/// "Download Now" opens the vendor's own page in the default browser; ATLAS
/// never serves the actual files. Platform filtering is hardcoded to Mac
/// here — the Windows app applies the identical rule against the same
/// endpoint (see AtlasBrowserService.appliesToThisPlatform).
/// Bumped by BrowserWindowController each time the window is shown, so
/// AtlasBrowserView's .task(id:) below re-fetches maintenance mode + the
/// catalog on every open instead of just once. Needed because Browser
/// moved to its own persistent NSWindow in v1.7.9 — the SwiftUI view is
/// now created once and reused for the app's whole session, so a plain
/// .task { } (which only fires once per view identity) would otherwise
/// leave underMaintenance/the catalog stuck at whatever they were on
/// first open, even after an admin flips maintenance back off.
final class AtlasBrowserReloadSignal: ObservableObject {
    @Published var token = 0
}

struct AtlasBrowserView: View {
    var onClose: (() -> Void)? = nil
    @ObservedObject var reloadSignal: AtlasBrowserReloadSignal = AtlasBrowserReloadSignal()

    @State private var allItems: [AtlasCatalogItem] = []
    @State private var isLoading = true
    @State private var loadFailed = false
    // Backed by BrowserMaintenanceManager's live poll (see its comment),
    // not a one-shot fetch in load() below — so an admin toggle takes
    // effect within seconds even while this window is already open,
    // not just on the next time Browser is opened.
    @ObservedObject private var maintenanceManager = BrowserMaintenanceManager.shared
    private var underMaintenance: Bool { maintenanceManager.isUnderMaintenance }
    @State private var searchText = ""
    @State private var hoveredID: String? = nil
    @State private var selectedItem: AtlasCatalogItem? = nil
    @State private var showAvailableNowOnly = false
    @State private var showAllProducts = false
    @State private var selectedCategory: String? = nil   // nil = All
    @State private var selectedBrand: String? = nil      // nil = All
    @State private var sortOption: SortOption = .relevance
    @ObservedObject private var downloadLimit = BrowserDownloadLimitManager.shared
    @State private var checkingLimitAgain = false
    @AppStorage("ATLAS.browserCardSize") private var cardSizeRaw: String = BrowserCardSize.medium.rawValue

    private var cardSizeOption: BrowserCardSize {
        BrowserCardSize(rawValue: cardSizeRaw) ?? .medium
    }

    enum BrowserCardSize: String, CaseIterable, Identifiable {
        case small = "Small"
        case medium = "Medium"
        case large = "Large"
        case extraLarge = "Extra Large"
        var id: String { rawValue }

        /// Multiplier applied to the card's base 136pt tile (image + text) —
        /// scales pictures and text together so the two stay proportional.
        var scale: CGFloat {
            switch self {
            case .small: return 0.8
            case .medium: return 1.0
            case .large: return 1.25
            case .extraLarge: return 1.5
            }
        }

        var icon: String {
            switch self {
            case .small: return "textformat.size.smaller"
            case .medium: return "textformat.size"
            case .large: return "textformat.size.larger"
            case .extraLarge: return "textformat.size.larger"
            }
        }

        /// Localized label — rawValue stays the stable English identifier
        /// persisted via @AppStorage, unaffected by the user's language.
        var displayName: String {
            switch self {
            case .small:      return L(.browserCardSizeSmall)
            case .medium:     return L(.browserCardSizeMedium)
            case .large:      return L(.browserCardSizeLarge)
            case .extraLarge: return L(.browserCardSizeExtraLarge)
            }
        }
    }

    enum SortOption: String, CaseIterable, Identifiable {
        case relevance = "Default"
        case newlyAdded = "Newly Added"
        case az = "Name: A–Z"
        case za = "Name: Z–A"
        case sizeSmall = "Size: Small → Large"
        case sizeLarge = "Size: Large → Small"
        var id: String { rawValue }

        /// Localized label — rawValue stays the stable English identifier
        /// (used only as `Identifiable`'s id, never persisted or compared
        /// against server data), while this drives everything shown on screen.
        var displayName: String {
            switch self {
            case .relevance:  return L(.browserSortDefault)
            case .newlyAdded: return L(.browserSortNewlyAdded)
            case .az:         return L(.browserSortAZ)
            case .za:         return L(.browserSortZA)
            case .sizeSmall:  return L(.browserSortSizeSmall)
            case .sizeLarge:  return L(.browserSortSizeLarge)
            }
        }
    }

    private static let categoryOrder = ["daw", "app", "plugin", "bundle", "sample_kit", "expansion_pack"]

    /// Parses free-text sizes like "2.4 GB" into megabytes for sorting.
    /// Returns nil when the size is missing/unparsable, so those items
    /// always sink to the end of a size sort regardless of direction.
    private static func sizeInMB(_ raw: String?) -> Double? {
        guard let raw, let match = raw.range(of: #"([0-9]+(\.[0-9]+)?)\s*(KB|MB|GB|TB)"#, options: [.regularExpression, .caseInsensitive]) else { return nil }
        let text = String(raw[match])
        let numberPart = text.prefix { $0.isNumber || $0 == "." }
        guard let value = Double(numberPart) else { return nil }
        let unit = text.uppercased().suffix(2)
        switch unit {
        case "KB": return value / 1024
        case "MB": return value
        case "GB": return value * 1024
        case "TB": return value * 1024 * 1024
        default: return value
        }
    }

    private func sorted(_ items: [AtlasCatalogItem]) -> [AtlasCatalogItem] {
        switch sortOption {
        case .relevance:
            return items
        case .newlyAdded:
            return items.sorted { (lhs, rhs) in
                switch (lhs.createdDate, rhs.createdDate) {
                case let (l?, r?): return l > r
                case (nil, _?):    return false
                case (_?, nil):    return true
                case (nil, nil):   return false
                }
            }
        case .az:
            return items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .za:
            return items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedDescending }
        case .sizeSmall:
            return items.sorted { (Self.sizeInMB($0.fileSize) ?? .infinity) < (Self.sizeInMB($1.fileSize) ?? .infinity) }
        case .sizeLarge:
            return items.sorted { (Self.sizeInMB($0.fileSize) ?? -1) > (Self.sizeInMB($1.fileSize) ?? -1) }
        }
    }

    private var macItems: [AtlasCatalogItem] {
        allItems.filter { $0.appliesToThisPlatform }
    }

    private var allBrands: [String] {
        Array(Set(macItems.compactMap { $0.brand })).sorted()
    }

    private var filteredItems: [AtlasCatalogItem] {
        var items = macItems
        if showAvailableNowOnly {
            items = items.filter { $0.isReadyForDownload }
        }
        if !showAllProducts {
            items = items.filter { !$0.isIncompatible }
        }
        if let category = selectedCategory {
            items = items.filter { $0.category == category }
        }
        if let brand = selectedBrand {
            items = items.filter { $0.brand == brand }
        }
        let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return items }
        return items.filter {
            $0.name.lowercased().contains(q) || ($0.brand?.lowercased().contains(q) ?? false)
        }
    }

    private var groupedByCategory: [(category: String, items: [AtlasCatalogItem])] {
        let grouped = Dictionary(grouping: filteredItems, by: \.category)
        return Self.categoryOrder.compactMap { cat in
            guard let items = grouped[cat], !items.isEmpty else { return nil }
            return (cat, items)
        }
    }

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 0) {
                header
                if !isLoading && !underMaintenance && !downloadLimit.isLocked {
                    searchField
                    categoryTabs
                    if !allBrands.isEmpty {
                        brandTabs
                    }
                }

                if isLoading {
                    Spacer()
                    ProgressView().controlSize(.small)
                    Spacer()
                } else if underMaintenance {
                    Spacer()
                    VStack(spacing: 10) {
                        Image(systemName: "wrench.and.screwdriver.fill")
                            .font(.system(size: 28))
                            .foregroundColor(Color.atlasAccent.opacity(0.8))
                        Text(L(.browserUpgradingTitle))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Color.atlasLabel)
                        Text(L(.browserUpgradingBody))
                            .font(.system(size: 12))
                            .foregroundColor(Color.atlasSubtitle)
                    }
                    // The enclosing VStack is alignment: .leading, so without
                    // this the message sits pinned to the left edge instead
                    // of centered in the window.
                    .frame(maxWidth: .infinity)
                    Spacer()
                } else if downloadLimit.isLocked {
                    browserLockedZone
                } else if loadFailed {
                    Spacer()
                    VStack(spacing: 8) {
                        Text(L(.browserLoadFailedTitle))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(Color.atlasLabel)
                        Text(L(.browserLoadFailedBody))
                            .font(.system(size: 11))
                            .foregroundColor(Color.atlasSubtitle)
                        Button(L(.retry)) { Task { await load() } }
                            .buttonStyle(.plain)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Color.atlasAccent)
                    }
                    Spacer()
                } else if filteredItems.isEmpty {
                    Spacer()
                    Text(searchText.isEmpty ? L(.browserNoResultsDefault) : String(format: L(.browserNoResultsSearchFmt), searchText))
                        .font(.system(size: 12))
                        .foregroundColor(Color.atlasSubtitle)
                    Spacer()
                } else {
                    ScrollView(.vertical, showsIndicators: true) {
                        VStack(alignment: .leading, spacing: 28) {
                            if selectedCategory != nil || selectedBrand != nil {
                                // A specific category/brand is already the heading context —
                                // show one flat, prominent grid instead of re-grouping.
                                categorySection(title: filterSummaryTitle, items: sorted(filteredItems))
                            } else {
                                ForEach(groupedByCategory, id: \.category) { group in
                                    categorySection(title: group.items.first!.categoryLabel, items: sorted(group.items))
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.trailing, 6)
                        .padding(.bottom, 20)
                    }
                }
            }
            .frame(width: 860, height: 620)
            .background(
                LinearGradient(
                    colors: [Color.atlasDeepBG, Color.atlasPanelBG],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            if !isLoading && !underMaintenance && !downloadLimit.isLocked && !loadFailed && selectedItem == nil {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        cardSizeControl
                    }
                }
                .padding(16)
            }

            if let item = selectedItem {
                AtlasBrowserDetailView(item: item) {
                    withAnimation(.easeOut(duration: 0.18)) { selectedItem = nil }
                }
                .frame(width: 860, height: 620)
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .frame(width: 860, height: 620)
        .clipShape(RoundedRectangle(cornerRadius: ATLASRadius.lg, style: .continuous))
        .task(id: reloadSignal.token) { await load() }
        // Covers the admin flipping maintenance OFF while this window is
        // already open and showing the "being upgraded" screen — the live
        // poll above flips underMaintenance immediately, but the catalog
        // itself was never fetched (load() returned early while
        // maintenance was on), so fetch it now instead of showing an
        // empty grid.
        .onChange(of: maintenanceManager.isUnderMaintenance) { nowUnderMaintenance in
            guard !nowUnderMaintenance, allItems.isEmpty, !isLoading else { return }
            Task { await load() }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: ATLASRadius.sm, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.atlasAccent, Color.atlasAccent.opacity(0.4)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 26, height: 26)
                Image(systemName: "square.grid.2x2.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.black.opacity(0.75))
            }
            Text(L(.browserTitle))
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Color.atlasLabel)
            Spacer()
            Button { onClose?() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color.atlasSubtitle)
                    .frame(width: 26, height: 26)
                    .background(Color.atlasElevated)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 10)
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color.atlasSubtitle.opacity(0.6))
                TextField(L(.browserSearchPlaceholder), text: $searchText)
                    .font(.system(size: 12))
                    .foregroundColor(Color.atlasLabel)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(Color.atlasSubtitle.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.atlasElevated.opacity(0.7))
            .clipShape(RoundedRectangle(cornerRadius: ATLASRadius.pill, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: ATLASRadius.pill, style: .continuous)
                    .strokeBorder(Color.atlasBorder.opacity(0.6), lineWidth: 1)
            )

            sortMenu
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 18)
    }

    private var sortMenu: some View {
        Menu {
            ForEach(SortOption.allCases) { option in
                Button {
                    sortOption = option
                } label: {
                    if sortOption == option {
                        Label(option.displayName, systemImage: "checkmark")
                    } else {
                        Text(option.displayName)
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 10, weight: .medium))
                Text(L(.browserSortBy))
                    .font(.system(size: 11.5, weight: .medium))
            }
            .foregroundColor(Color.atlasLabel)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.atlasElevated.opacity(0.7))
            .clipShape(RoundedRectangle(cornerRadius: ATLASRadius.pill, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: ATLASRadius.pill, style: .continuous)
                    .strokeBorder(Color.atlasBorder.opacity(0.6), lineWidth: 1)
            )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var filterSummaryTitle: String {
        if let brand = selectedBrand { return brand }
        if let category = selectedCategory {
            return AtlasCatalogItem.categoryLabel(for: category)
        }
        return L(.filterAll)
    }

    private var categoryTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                availableNowPill
                viewAllProductsPill
                categoryPill(label: L(.filterAll), isSelected: selectedCategory == nil) {
                    selectedCategory = nil
                }
                ForEach(Self.categoryOrder, id: \.self) { cat in
                    let count = macItems.filter { $0.category == cat }.count
                    if count > 0 {
                        categoryPill(label: AtlasCatalogItem.categoryLabel(for: cat), isSelected: selectedCategory == cat) {
                            selectedCategory = (selectedCategory == cat) ? nil : cat
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.bottom, 10)
    }

    /// Status filter, not a content category — toggles down to only
    /// products that actually have an active download link right now
    /// (same check the "Available Now" card badge and download button
    /// use: AtlasCatalogItem.isReadyForDownload).
    private var availableNowPill: some View {
        Button {
            showAvailableNowOnly.toggle()
        } label: {
            HStack(spacing: 5) {
                Circle()
                    .fill(showAvailableNowOnly ? .black : Color(hex: "#3ECFB2"))
                    .frame(width: 6, height: 6)
                Text(L(.browserAvailableNow))
                    .font(.system(size: 13, weight: showAvailableNowOnly ? .bold : .semibold))
            }
            .foregroundColor(showAvailableNowOnly ? .black : Color.atlasLabel)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                Group {
                    if showAvailableNowOnly {
                        LinearGradient(colors: [Color(hex: "#3ECFB2"), Color(hex: "#3ECFB2").opacity(0.75)], startPoint: .leading, endPoint: .trailing)
                    } else {
                        Color.atlasElevated.opacity(0.7)
                    }
                }
            )
            .clipShape(Capsule())
            .overlay(
                Capsule().strokeBorder(showAvailableNowOnly ? Color.clear : Color(hex: "#3ECFB2").opacity(0.4), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    /// By default Browser hides products that are flagged incompatible
    /// with this Mac (parsed from Specs — AtlasCompatibilityChecker). This
    /// pill is the escape hatch: when on, nothing is hidden on
    /// compatibility grounds, though the badges still show either way.
    private var viewAllProductsPill: some View {
        Button {
            showAllProducts.toggle()
        } label: {
            Text(L(.browserViewAllProducts))
                .font(.system(size: 13, weight: showAllProducts ? .bold : .semibold))
                .foregroundColor(showAllProducts ? .black : Color.atlasLabel)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    Group {
                        if showAllProducts {
                            LinearGradient(colors: [Color.atlasAccent, Color.atlasAccent.opacity(0.75)], startPoint: .leading, endPoint: .trailing)
                        } else {
                            Color.atlasElevated.opacity(0.7)
                        }
                    }
                )
                .clipShape(Capsule())
                .overlay(
                    Capsule().strokeBorder(showAllProducts ? Color.clear : Color.atlasBorder.opacity(0.6), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func categoryPill(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: isSelected ? .bold : .semibold))
                .foregroundColor(isSelected ? .black : Color.atlasLabel)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    Group {
                        if isSelected {
                            LinearGradient(colors: [Color.atlasAccent, Color.atlasAccent.opacity(0.75)], startPoint: .leading, endPoint: .trailing)
                        } else {
                            Color.atlasElevated.opacity(0.7)
                        }
                    }
                )
                .clipShape(Capsule())
                .overlay(
                    Capsule().strokeBorder(isSelected ? Color.clear : Color.atlasBorder.opacity(0.6), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private var brandTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Text(L(.browserBrandLabel))
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(Color.atlasSubtitle.opacity(0.6))
                    .tracking(1.2)
                    .padding(.trailing, 2)
                brandChip(label: L(.filterAll), isSelected: selectedBrand == nil) { selectedBrand = nil }
                ForEach(allBrands, id: \.self) { brand in
                    brandChip(label: brand, isSelected: selectedBrand == brand) {
                        selectedBrand = (selectedBrand == brand) ? nil : brand
                    }
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.bottom, 16)
    }

    @ViewBuilder
    private func brandChip(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundColor(isSelected ? Color.atlasAccent : Color.atlasSubtitle)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(isSelected ? Color.atlasAccent.opacity(0.15) : Color.clear)
                .clipShape(Capsule())
                .overlay(
                    Capsule().strokeBorder(isSelected ? Color.atlasAccent.opacity(0.5) : Color.atlasBorder.opacity(0.5), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    /// Bottom-right floating control — lets users bump the catalog's
    /// picture/text size up or down without affecting the detail popup
    /// (which is already a fixed, readable size). Persisted via
    /// @AppStorage so the choice survives relaunch.
    private var cardSizeControl: some View {
        Menu {
            ForEach(BrowserCardSize.allCases) { option in
                Button {
                    cardSizeRaw = option.rawValue
                } label: {
                    if cardSizeOption == option {
                        Label(option.displayName, systemImage: "checkmark")
                    } else {
                        Text(option.displayName)
                    }
                }
            }
        } label: {
            Image(systemName: cardSizeOption.icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Color.atlasLabel)
                .frame(width: 34, height: 34)
                .background(Color.atlasElevated.opacity(0.95))
                .clipShape(Circle())
                .overlay(
                    Circle().strokeBorder(Color.atlasBorder.opacity(0.7), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    @ViewBuilder
    private func categorySection(title: String, items: [AtlasCatalogItem]) -> some View {
        let tile = 136 * cardSizeOption.scale
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(Color.atlasSubtitle.opacity(0.75))
                .tracking(1.4)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: tile, maximum: tile), spacing: 16)], alignment: .leading, spacing: 20) {
                ForEach(items) { item in
                    catalogCard(item, tile: tile)
                }
            }
        }
    }

    @ViewBuilder
    private func catalogCard(_ item: AtlasCatalogItem, tile: CGFloat) -> some View {
        let isHovered = hoveredID == item.id
        let scale = cardSizeOption.scale
        Button {
            withAnimation(.easeOut(duration: 0.18)) { selectedItem = item }
        } label: {
            VStack(alignment: .leading, spacing: 7) {
                ZStack {
                    RoundedRectangle(cornerRadius: ATLASRadius.md, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.atlasElevated, Color.atlasDeepBG],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    if let urlString = item.imageUrl, let url = URL(string: urlString) {
                        AsyncImage(url: url) { phase in
                            if let image = phase.image {
                                image.resizable().aspectRatio(contentMode: .fill)
                            } else {
                                Image(systemName: "square.dashed")
                                    .foregroundColor(Color.atlasTertiary)
                            }
                        }
                        // .fill mode intentionally overflows its proposed size
                        // to cover the frame without distorting aspect ratio —
                        // without a frame+clip pinned right here, that overflow
                        // could render over the badge layers below. Pinning it
                        // here keeps the image strictly inside the card so the
                        // badges (added after it, further down this ZStack)
                        // reliably stay on top.
                        .frame(width: tile, height: tile)
                        .clipped()
                    } else {
                        Image(systemName: "square.dashed")
                            .foregroundColor(Color.atlasTertiary)
                            .frame(width: tile, height: tile)
                    }

                    LinearGradient(
                        colors: [.clear, Color.black.opacity(isHovered ? 0.25 : 0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )

                    if item.isReadyForDownload {
                        VStack {
                            Spacer()
                            HStack(spacing: 3) {
                                Circle()
                                    .fill(Color(hex: "#3ECFB2"))
                                    .frame(width: 5, height: 5)
                                Text(L(.browserAvailableNow))
                                    .font(.system(size: 8.5, weight: .semibold))
                                    .foregroundColor(.white)
                                    .shadow(color: .black.opacity(0.8), radius: 1.5, y: 0.5)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.75)
                            )
                            .shadow(color: Color(hex: "#3ECFB2").opacity(0.45), radius: 4, y: 1)
                            .padding(.bottom, 6)
                        }
                        .zIndex(2)
                    } else {
                        VStack {
                            Spacer()
                            Text(L(.browserAvailableSoon))
                                .font(.system(size: 8.5, weight: .semibold))
                                .foregroundColor(.white)
                                .shadow(color: .black.opacity(0.8), radius: 1.5, y: 0.5)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.75)
                                )
                                .shadow(color: Color(hex: "#F0A030").opacity(0.4), radius: 4, y: 1)
                                .padding(.bottom, 6)
                        }
                        .zIndex(2)
                    }

                    if item.isNew {
                        VStack {
                            HStack {
                                Text(L(.browserNewBadge))
                                    .font(.system(size: 8, weight: .bold))
                                    .tracking(0.5)
                                    .foregroundColor(.black)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(Color.atlasAccent)
                                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                                    .shadow(color: Color.atlasAccent.opacity(0.6), radius: 5, y: 1)
                                Spacer()
                            }
                            Spacer()
                        }
                        .padding(6)
                        .zIndex(2)
                    }

                    if item.isIncompatible {
                        VStack {
                            HStack {
                                Spacer()
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundColor(.black)
                                    .padding(5)
                                    .background(Color(hex: "#F0A030"))
                                    .clipShape(Circle())
                                    .shadow(color: Color(hex: "#F0A030").opacity(0.6), radius: 5, y: 1)
                            }
                            Spacer()
                        }
                        .padding(6)
                        .zIndex(2)
                    }
                }
                .frame(width: tile, height: tile)
                .clipShape(RoundedRectangle(cornerRadius: ATLASRadius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: ATLASRadius.md, style: .continuous)
                        .strokeBorder(isHovered ? Color.atlasAccent.opacity(0.7) : Color.atlasBorder, lineWidth: isHovered ? 1.5 : 1)
                )
                .shadow(color: .black.opacity(isHovered ? 0.35 : 0), radius: isHovered ? 14 : 0, y: isHovered ? 8 : 0)
                .scaleEffect(isHovered ? 1.045 : 1.0)

                Text(item.name)
                    .font(.system(size: 11.5 * scale, weight: .medium))
                    .foregroundColor(Color.atlasLabel)
                    .lineLimit(1)
                if let brand = item.brand {
                    Text(brand)
                        .font(.system(size: 9.5 * scale))
                        .foregroundColor(Color.atlasSubtitle)
                        .lineLimit(1)
                }
            }
            .frame(width: tile, alignment: .leading)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                hoveredID = hovering ? item.id : (hoveredID == item.id ? nil : hoveredID)
            }
        }
    }

    private func load() async {
        isLoading = true
        loadFailed = false
        async let maintenanceRefresh: Void = maintenanceManager.refreshNow()
        async let limitRefresh: Void = downloadLimit.refreshUsage()
        await maintenanceRefresh
        await limitRefresh
        if underMaintenance {
            isLoading = false
            return
        }
        let items = await AtlasBrowserService.fetchCatalog()
        if items.isEmpty {
            loadFailed = true
        } else {
            allItems = items
        }
        isLoading = false
    }

    /// Replaces the whole grid once the user hits Browser's own 25/month
    /// download cap — same countdown-lockdown idiom as ContentView's
    /// monthlyLimitLockedZone for the regular install limit, just scoped
    /// to Browser's independent counter.
    private var browserLockedZone: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let t = downloadLimit.timeUntilReset
            let days = Int(t) / 86400
            let hh = (Int(t) % 86400) / 3600
            let mm = (Int(t) % 3600) / 60
            let ss = Int(t) % 60
            let countdown = days > 0
                ? String(format: "%dd %02d:%02d:%02d", days, hh, mm, ss)
                : String(format: "%02d:%02d:%02d", hh, mm, ss)

            VStack {
                Spacer()
                VStack(spacing: 14) {
                    Image(systemName: "lock.circle.fill")
                        .font(.system(size: 36))
                        .foregroundColor(Color(hex: "#F0A030"))

                    VStack(spacing: 4) {
                        Text(L(.browserLimitReachedTitle))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Color(hex: "#F0A030"))
                        Text(String(format: L(.browserLimitPerMonthFmt), downloadLimit.limit))
                            .font(.system(size: 11))
                            .foregroundColor(Color.atlasSubtitle)
                    }

                    HStack(spacing: 5) {
                        Image(systemName: "clock")
                            .font(.system(size: 11))
                            .foregroundColor(Color.atlasSubtitle)
                        Text(String(format: L(.browserRefillsInFmt), countdown))
                            .font(.system(size: 13, weight: .medium).monospacedDigit())
                            .foregroundColor(Color.atlasLabel)
                    }

                    Button {
                        checkingLimitAgain = true
                        Task {
                            await downloadLimit.refreshUsage()
                            checkingLimitAgain = false
                        }
                    } label: {
                        Text(checkingLimitAgain ? L(.browserChecking) : L(.browserCheckAgain))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Color.atlasLabel)
                            .padding(.horizontal, 16).padding(.vertical, 7)
                            .background(Color.atlasElevated)
                            .clipShape(RoundedRectangle(cornerRadius: ATLASRadius.sm, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: ATLASRadius.sm, style: .continuous)
                                    .strokeBorder(Color.atlasBorder, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(checkingLimitAgain)
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Once the countdown reaches zero, confirm with the server once
            // so the lock clears itself automatically — no relaunch, no
            // manual tap needed. isLocked flipping false removes this
            // whole view from the hierarchy, so this stops firing on its
            // own once that happens.
            .onChange(of: t <= 0) { hitZero in
                if hitZero { Task { await downloadLimit.refreshUsage() } }
            }
        }
    }
}

/// Detail overlay shown when a catalog card is tapped — description, size,
/// specs, and the "Download Now" external link. No prices anywhere.
private struct AtlasBrowserDetailView: View {
    let item: AtlasCatalogItem
    var onClose: () -> Void

    @State private var pendingIncompatibleLink: (link: AtlasCatalogLink, url: URL)? = nil

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .onTapGesture { onClose() }

            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .bottomLeading) {
                    ZStack {
                        if let urlString = item.imageUrl, let url = URL(string: urlString) {
                            AsyncImage(url: url) { phase in
                                if let image = phase.image {
                                    image.resizable().aspectRatio(contentMode: .fill)
                                } else {
                                    Color.atlasElevated
                                }
                            }
                        } else {
                            Color.atlasElevated
                        }
                    }
                    .frame(height: 180)
                    .clipped()

                    LinearGradient(
                        colors: [.clear, Color.atlasPanelBG.opacity(0.4), Color.atlasPanelBG],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 180)

                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.name)
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(.white)
                            if let brand = item.brand {
                                Text(brand)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.white.opacity(0.75))
                            }
                        }
                        Spacer()
                    }
                    .padding(20)
                }

                Button { onClose() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 26, height: 26)
                        .background(Color.black.opacity(0.35))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .padding(14)
                .offset(y: -180)
                .frame(maxWidth: .infinity, alignment: .trailing)

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 8) {
                            if item.isNew {
                                Text(L(.browserNewBadge))
                                    .font(.system(size: 10, weight: .bold))
                                    .tracking(0.5)
                                    .foregroundColor(.black)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(Color.atlasAccent)
                                    .clipShape(Capsule())
                                    .shadow(color: Color.atlasAccent.opacity(0.55), radius: 5, y: 1)
                            }

                            if item.isReadyForDownload {
                                HStack(spacing: 4) {
                                    Circle().fill(Color(hex: "#3ECFB2")).frame(width: 5, height: 5)
                                    Text(L(.browserAvailableNow))
                                        .font(.system(size: 10, weight: .semibold))
                                }
                                .foregroundColor(Color(hex: "#3ECFB2"))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color(hex: "#3ECFB2").opacity(0.15))
                                .clipShape(Capsule())
                                .shadow(color: Color(hex: "#3ECFB2").opacity(0.4), radius: 5, y: 1)
                            }

                            switch item.compatibility {
                            case .compatible:
                                HStack(spacing: 4) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 9))
                                    Text(L(.browserCompatible))
                                        .font(.system(size: 10, weight: .semibold))
                                }
                                .foregroundColor(Color(hex: "#3ECFB2"))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color(hex: "#3ECFB2").opacity(0.15))
                                .clipShape(Capsule())
                                .shadow(color: Color(hex: "#3ECFB2").opacity(0.4), radius: 5, y: 1)
                            case .incompatible:
                                HStack(spacing: 4) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.system(size: 9))
                                    Text(L(.browserIncompatible))
                                        .font(.system(size: 10, weight: .semibold))
                                }
                                .foregroundColor(Color(hex: "#F0A030"))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color(hex: "#F0A030").opacity(0.15))
                                .clipShape(Capsule())
                                .shadow(color: Color(hex: "#F0A030").opacity(0.45), radius: 5, y: 1)
                            case .unknown:
                                EmptyView()
                            }

                            Text(item.categoryLabel)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(Color.atlasAccent)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color.atlasAccent.opacity(0.15))
                                .clipShape(Capsule())

                            if let size = item.fileSize, !size.isEmpty {
                                Text(size)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(Color.atlasSubtitle)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(Color.atlasElevated)
                                    .clipShape(Capsule())
                            }

                            if let version = item.version, !version.isEmpty {
                                Text(String(format: L(.browserVersionFmt), version))
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(Color.atlasSubtitle)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(Color.atlasElevated)
                                    .clipShape(Capsule())
                            }
                        }

                        if let description = item.description, !description.isEmpty {
                            Text(description)
                                .font(.system(size: 12.5))
                                .foregroundColor(Color.atlasLabel)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            Text(L(.browserNoDescription))
                                .font(.system(size: 12))
                                .foregroundColor(Color.atlasSubtitle)
                        }

                        if !item.specLines.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(L(.browserSpecsHeader))
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(Color.atlasSubtitle.opacity(0.7))
                                    .tracking(1.2)
                                ForEach(item.specLines, id: \.self) { line in
                                    HStack(alignment: .top, spacing: 6) {
                                        Circle()
                                            .fill(Color.atlasAccent)
                                            .frame(width: 4, height: 4)
                                            .padding(.top, 5)
                                        Text(line)
                                            .font(.system(size: 12))
                                            .foregroundColor(Color.atlasSubtitle)
                                    }
                                }
                            }
                        }

                        downloadButtons
                            .padding(.top, 4)
                    }
                    .padding(20)
                }
            }
            .frame(width: 560, height: 520)
            .background(Color.atlasPanelBG)
            .clipShape(RoundedRectangle(cornerRadius: ATLASRadius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: ATLASRadius.lg, style: .continuous)
                    .strokeBorder(Color.atlasBorder, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.5), radius: 30, y: 12)
        }
        .confirmationDialog(
            L(.browserConfirmIncompatibleTitle),
            isPresented: Binding(
                get: { pendingIncompatibleLink != nil },
                set: { if !$0 { pendingIncompatibleLink = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(L(.browserDownloadAnyway)) {
                if let pending = pendingIncompatibleLink {
                    startDownload(link: pending.link, url: pending.url)
                }
                pendingIncompatibleLink = nil
            }
            Button(L(.cancel), role: .cancel) { pendingIncompatibleLink = nil }
        }
    }

    /// The actual download attempt — counts toward the 25/month cap and
    /// feeds the TITAN download watcher identically regardless of whether
    /// it was reached directly (compatible/unknown) or via the
    /// incompatible-download confirmation dialog above. Compatibility is a
    /// pre-flight warning only; it never changes what this does or what it
    /// counts as.
    private func startDownload(link: AtlasCatalogLink, url: URL) {
        Task {
            let result = await AtlasBrowserDownloadReporter.reportAndCheck(item: item, link: link)
            await MainActor.run {
                BrowserDownloadLimitManager.shared.apply(
                    used: result.used, limit: result.limit, nextResetRaw: result.nextReset
                )
                guard result.allowed else { return }
                NSWorkspace.shared.open(url)
                AtlasPendingDownloadsStore.shared.expect(
                    productName: item.name, brand: item.brand,
                    titanVerified: item.titanVerified ?? false
                )
            }
        }
    }

    @ViewBuilder
    private var downloadButtons: some View {
        let links = item.downloadLinks
        if !links.isEmpty {
            VStack(spacing: 8) {
                ForEach(links) { link in
                    if let url = URL(string: link.url) {
                        Button {
                            if item.isIncompatible {
                                pendingIncompatibleLink = (link, url)
                            } else {
                                startDownload(link: link, url: url)
                            }
                        } label: {
                            Text(links.count > 1 ? (link.label?.isEmpty == false ? link.label! : L(.browserDownloadLabel)) : L(.browserDownloadNow))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 11)
                                .background(
                                    LinearGradient(
                                        colors: [Color.atlasAccent, Color.atlasAccent.opacity(0.75)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .clipShape(RoundedRectangle(cornerRadius: ATLASRadius.sm, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        } else {
            Text(L(.browserAvailableSoon))
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color.atlasSubtitle)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(Color.atlasElevated)
                .clipShape(RoundedRectangle(cornerRadius: ATLASRadius.sm, style: .continuous))
        }
    }
}
