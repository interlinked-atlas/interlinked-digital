import SwiftUI

// MARK: - Shared wrapper for sheet identity
struct WrappedEntry: Identifiable {
    let id = UUID()
    let dict: [String: Any]
}

// MARK: - Local install record parsed from log filename + content

struct LocalInstallRecord: Identifiable {
    let id = UUID()
    let productName: String
    let fileName: String
    let date: Date
    let logPath: String
}

// MARK: - Main Viewer

struct TitanMemoryViewer: View {
    @Environment(\.dismiss) private var dismiss
    @State private var localInstalls: [LocalInstallRecord] = []
    @State private var confirmedEntries: [[String: Any]] = []
    @State private var userFeedback: [[String: Any]] = []
    @State private var loading = true
    @State private var selected: WrappedEntry? = nil
    @State private var tab: Tab = .installed

    enum Tab { case installed, confirmed, feedback }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Image(systemName: "brain.head.profile")
                            .foregroundColor(Color(hex: "#3ECFB2"))
                        Text("TITAN MEMORY™")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(Color.atlasLabel)
                    }
                    Text("Successful installs · Confirmed patterns · User feedback")
                        .font(.system(size: 11))
                        .foregroundColor(Color.atlasSubtitle)
                }
                Spacer()
                Button { Task { await reload() } } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12))
                        .foregroundColor(Color(hex: "#3ECFB2"))
                }
                .buttonStyle(.plain)
                .padding(.trailing, 8)
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(Color.atlasSubtitle.opacity(0.5))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)

            // Tabs
            HStack(spacing: 0) {
                tabButton("Installed", count: localInstalls.count, active: tab == .installed) { tab = .installed }
                tabButton("Confirmed", count: confirmedEntries.count, active: tab == .confirmed) { tab = .confirmed }
                tabButton("Feedback", count: userFeedback.count, active: tab == .feedback) { tab = .feedback }
            }
            .padding(.horizontal, 16).padding(.bottom, 8)

            Divider()

            if loading {
                Spacer()
                ProgressView().tint(Color(hex: "#3ECFB2"))
                Spacer()
            } else if tab == .installed {
                installedList
            } else if tab == .confirmed {
                confirmedList
            } else {
                feedbackList
            }
        }
        .frame(width: 500, height: 560)
        .background(Color.atlasDeepBG)
        .task { await reload() }
        .sheet(item: $selected) { e in
            TitanMemoryDetailView(entry: e.dict)
        }
    }

    // MARK: - Installed list (local log files)

    @ViewBuilder
    private var installedList: some View {
        if localInstalls.isEmpty {
            emptyState(icon: "checkmark.circle", message: "No successful installs found", sub: "Successfully installed products will appear here.")
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(localInstalls.enumerated()), id: \.element.id) { i, record in
                        installedRow(record)
                        if i < localInstalls.count - 1 { Divider().padding(.leading, 56) }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func installedRow(_ record: LocalInstallRecord) -> some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(hex: "#3ECFB2").opacity(0.10))
                    .frame(width: 32, height: 32)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(Color(hex: "#3ECFB2"))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(record.productName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color.atlasLabel)
                HStack(spacing: 5) {
                    Text("mac")
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Color(hex: "#7090B8").opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                        .foregroundColor(Color(hex: "#7090B8"))
                    Text(record.fileName)
                        .font(.system(size: 10))
                        .foregroundColor(Color.atlasSubtitle)
                        .lineLimit(1)
                    Text("·").foregroundColor(Color.atlasSubtitle.opacity(0.4)).font(.system(size: 10))
                    Text(formatDate(record.date))
                        .font(.system(size: 10))
                        .foregroundColor(Color.atlasSubtitle)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    // MARK: - Confirmed list

    @ViewBuilder
    private var confirmedList: some View {
        if confirmedEntries.isEmpty {
            emptyState(icon: "checkmark.seal", message: "No confirmed patterns yet", sub: "Confirm installs via Feedback → Yes in ATLAS Library.")
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(confirmedEntries.indices, id: \.self) { i in
                        let entry = confirmedEntries[i]
                        confirmedRow(entry)
                        if i < confirmedEntries.count - 1 { Divider().padding(.leading, 56) }
                    }
                }
            }
        }
    }

    // MARK: - Feedback list

    @ViewBuilder
    private var feedbackList: some View {
        if userFeedback.isEmpty {
            emptyState(icon: "text.bubble", message: "No user feedback yet", sub: "Failure reports from users will appear here.")
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(userFeedback.indices, id: \.self) { i in
                        let entry = userFeedback[i]
                        feedbackRow(entry)
                        if i < userFeedback.count - 1 { Divider().padding(.leading, 56) }
                    }
                }
            }
        }
    }

    // MARK: - Row views

    @ViewBuilder
    private func confirmedRow(_ entry: [String: Any]) -> some View {
        Button { selected = WrappedEntry(dict: entry) } label: {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(hex: "#3ECFB2").opacity(0.12))
                        .frame(width: 32, height: 32)
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 14))
                        .foregroundColor(Color(hex: "#3ECFB2"))
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry["product_name"] as? String ?? "Unknown")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color.atlasLabel)
                    HStack(spacing: 5) {
                        Text(entry["platform"] as? String ?? "mac")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Color(hex: "#7090B8").opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                            .foregroundColor(Color(hex: "#7090B8"))
                        Text(entry["file_name"] as? String ?? "")
                            .font(.system(size: 10))
                            .foregroundColor(Color.atlasSubtitle)
                            .lineLimit(1)
                        Text("·")
                            .foregroundColor(Color.atlasSubtitle.opacity(0.4)).font(.system(size: 10))
                        Text(shortDate(entry["confirmed_at"] as? String))
                            .font(.system(size: 10))
                            .foregroundColor(Color.atlasSubtitle)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10))
                    .foregroundColor(Color.atlasSubtitle.opacity(0.4))
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func feedbackRow(_ entry: [String: Any]) -> some View {
        Button { selected = WrappedEntry(dict: entry) } label: {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(hex: "#E05555").opacity(0.12))
                        .frame(width: 32, height: 32)
                    Image(systemName: "exclamationmark.bubble.fill")
                        .font(.system(size: 13))
                        .foregroundColor(Color(hex: "#E05555"))
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry["app_name"] as? String ?? entry["filename"] as? String ?? "Unknown")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color.atlasLabel)
                    HStack(spacing: 5) {
                        Text(entry["device_name"] as? String ?? "Unknown device")
                            .font(.system(size: 10))
                            .foregroundColor(Color.atlasSubtitle)
                            .lineLimit(1)
                        Text("·")
                            .foregroundColor(Color.atlasSubtitle.opacity(0.4)).font(.system(size: 10))
                        Text(shortDate(entry["installed_at"] as? String))
                            .font(.system(size: 10))
                            .foregroundColor(Color.atlasSubtitle)
                    }
                    if let content = entry["content"] as? String {
                        Text(content)
                            .font(.system(size: 10))
                            .foregroundColor(Color.atlasSubtitle.opacity(0.8))
                            .lineLimit(2)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10))
                    .foregroundColor(Color.atlasSubtitle.opacity(0.4))
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Tab button

    @ViewBuilder
    private func tabButton(_ label: String, count: Int, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(label)
                    .font(.system(size: 11, weight: active ? .semibold : .regular))
                Text("\(count)")
                    .font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(active ? Color(hex: "#3ECFB2").opacity(0.15) : Color.atlasElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .foregroundColor(active ? Color(hex: "#3ECFB2") : Color.atlasSubtitle)
            }
            .foregroundColor(active ? Color.atlasLabel : Color.atlasSubtitle)
            .padding(.vertical, 6).padding(.horizontal, 10)
            .background(active ? Color.atlasElevated : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Empty state

    @ViewBuilder
    private func emptyState(icon: String, message: String, sub: String) -> some View {
        Spacer()
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 28))
                .foregroundColor(Color.atlasSubtitle.opacity(0.3))
            Text(message)
                .font(.system(size: 12))
                .foregroundColor(Color.atlasSubtitle.opacity(0.5))
            Text(sub)
                .font(.system(size: 11))
                .foregroundColor(Color.atlasSubtitle.opacity(0.4))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        Spacer()
    }

    // MARK: - Data loading

    private func reload() async {
        loading = true
        async let titan    = TitanMemory.shared.fetchAllEntries()
        async let feedback = fetchUserFeedback()
        async let local    = loadLocalInstalls()
        confirmedEntries = await titan
        userFeedback     = await feedback
        localInstalls    = await local
        loading = false
    }

    private func loadLocalInstalls() async -> [LocalInstallRecord] {
        let logsDir = NSHomeDirectory() + "/Library/Logs/ATLAS/Installed"
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: logsDir) else { return [] }

        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd_HH-mm-ss"

        var records: [LocalInstallRecord] = []
        for file in files.sorted().reversed() {
            guard file.hasSuffix(".log") else { continue }
            // Filename: Install_2026-07-25_19-04-13_magic.CURVE-1.0.2-Installer.pkg.log
            let base = file
                .replacingOccurrences(of: "Install_", with: "")
                .replacingOccurrences(of: ".log", with: "")
            // First 19 chars = "2026-07-25_19-04-13"
            guard base.count > 20 else { continue }
            let dateStr  = String(base.prefix(19))
            let fileName = String(base.dropFirst(20))
            let date     = df.date(from: dateStr) ?? Date()
            let productName = cleanProductName(fileName)
            records.append(LocalInstallRecord(
                productName: productName,
                fileName:    fileName,
                date:        date,
                logPath:     "\(logsDir)/\(file)"
            ))
        }
        return records
    }

    private func cleanProductName(_ raw: String) -> String {
        // "magic.CURVE-1.0.2-Installer.pkg" → "magic.CURVE"
        // "Xfer_Records_Serum_v2_0_23_macOS_VR.iso" → "Xfer Records Serum"
        var name = raw
        // Strip known suffixes
        for suffix in ["-Installer.pkg", ".pkg", ".dmg", ".iso", ".zip", ".app"] {
            if name.lowercased().hasSuffix(suffix.lowercased()) {
                name = String(name.dropLast(suffix.count))
                break
            }
        }
        // Strip version patterns like "-1.0.2", "_v2_0_23", "_macOS", "_VR", "_U2B" etc.
        let versionPattern = try? NSRegularExpression(
            pattern: "[-_ ][vV]?\\d+[\\d._-]*.*$|[-_ ](macOS|OSX|Mac|VR|U2B|FLARE|Installer|Setup|Install).*$",
            options: [.caseInsensitive])
        let range = NSRange(name.startIndex..., in: name)
        if let m = versionPattern?.rangeOfFirstMatch(in: name, range: range),
           let swiftRange = Range(m, in: name) {
            name = String(name[name.startIndex..<swiftRange.lowerBound])
        }
        // Replace underscores/dashes with spaces, trim
        return name
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
        return f.string(from: date)
    }

    private func fetchUserFeedback() async -> [[String: Any]] {
        guard let token = AuthManager.shared.session?.accessToken,
              let url = URL(string: "https://www.interlinked.digital/api/atlas/admin-data") else { return [] }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let logs = json["logs"] as? [[String: Any]] else { return [] }
        return logs.filter { ($0["log_type"] as? String) == "install-failure-feedback" }
    }

    private func shortDate(_ iso: String?) -> String {
        guard let iso else { return "" }
        var f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let d = f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) else { return iso }
        let out = DateFormatter(); out.dateFormat = "MMM d, yyyy"
        return out.string(from: d)
    }
}

// MARK: - Detail view

struct TitanMemoryDetailView: View {
    let entry: [String: Any]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry["product_name"] as? String ?? entry["app_name"] as? String ?? "Unknown")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(Color.atlasLabel)
                    Text(entry["file_name"] as? String ?? entry["filename"] as? String ?? "")
                        .font(.system(size: 11))
                        .foregroundColor(Color.atlasSubtitle)
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(Color.atlasSubtitle.opacity(0.5))
                }
                .buttonStyle(.plain)
            }
            .padding(16)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let steps = entry["steps"] as? [[String: Any]], !steps.isEmpty {
                        detailSection("Install Steps") {
                            ForEach(steps.indices, id: \.self) { i in
                                let s = steps[i]
                                HStack(alignment: .top, spacing: 8) {
                                    Text("\(i + 1)")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundColor(Color(hex: "#3ECFB2"))
                                        .frame(width: 16, height: 16)
                                        .background(Color(hex: "#3ECFB2").opacity(0.12))
                                        .clipShape(Circle())
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(s["file"] as? String ?? s["type"] as? String ?? "")
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundColor(Color.atlasLabel)
                                        if let note = s["note"] as? String, !note.isEmpty {
                                            Text(note).font(.system(size: 10)).foregroundColor(Color.atlasSubtitle)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    if let hosts = entry["hosts_entries"] as? [String], !hosts.isEmpty {
                        detailSection("Hosts Entries") {
                            ForEach(hosts, id: \.self) { h in
                                Text(h).font(.system(size: 10, design: .monospaced)).foregroundColor(Color(hex: "#F0A030"))
                            }
                        }
                    }

                    if let content = entry["content"] as? String, !content.isEmpty {
                        detailSection("User Report") {
                            Text(content).font(.system(size: 11)).foregroundColor(Color.atlasLabel)
                        }
                    }

                    if let log = entry["install_log"] as? String, !log.isEmpty {
                        detailSection("Install Log") {
                            Text(log)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(Color.atlasSubtitle)
                                .lineLimit(20)
                        }
                    }

                    detailSection("Meta") {
                        if let v = entry["confirmed_by"] as? String { metaRow("Confirmed by", v) }
                        if let v = entry["device_name"]  as? String { metaRow("Device", v) }
                        if let v = entry["platform"]     as? String { metaRow("Platform", v) }
                        let dateStr = entry["confirmed_at"] as? String ?? entry["installed_at"] as? String ?? ""
                        if !dateStr.isEmpty { metaRow("Date", dateStr) }
                    }
                }
                .padding(16)
            }
        }
        .frame(width: 460, height: 500)
        .background(Color.atlasDeepBG)
    }

    @ViewBuilder
    private func detailSection<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .black)).tracking(1)
                .foregroundColor(Color(hex: "#3ECFB2").opacity(0.7))
            VStack(alignment: .leading, spacing: 4) { content() }
                .padding(10)
                .background(Color.atlasElevated)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
    }

    @ViewBuilder
    private func metaRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(Color.atlasSubtitle)
                .frame(width: 90, alignment: .leading)
            Text(value).font(.system(size: 10)).foregroundColor(Color.atlasLabel)
            Spacer()
        }
    }
}
