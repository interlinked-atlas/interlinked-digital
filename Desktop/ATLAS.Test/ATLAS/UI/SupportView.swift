import SwiftUI
import AppKit

struct SupportView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var auth       = AuthManager.shared
    @ObservedObject private var appearance = AppearanceManager.shared

    // Optional pre-selected product passed from the history row that was tapped.
    var preselectedRecord: InstallRecord? = nil
    // All install history so the product picker is fully populated.
    var allRecords: [InstallRecord] = []

    @State private var selectedProductID: UUID? = nil
    @State private var issueType   = "Install Failed"
    @State private var message     = ""
    @State private var selectedLog: LocalLog? = nil
    @State private var recentLogs: [LocalLog] = []
    @State private var submitting  = false
    @State private var submitted   = false
    @State private var errorMsg    = ""

    private let issueTypes = [
        "Install Failed", "Demo Mode Detected", "Uninstall Issue",
        "App Not Opening", "License Not Applied", "Subscription Issue",
        "Performance Issue", "Feature Request", "Other"
    ]

    struct LocalLog: Identifiable {
        let id = UUID()
        let filename: String
        let type: String
        let content: String
        let date: Date
    }

    // Deduplicated product list from history
    private var productList: [InstallRecord] {
        var seen = Set<String>()
        return allRecords.filter { seen.insert($0.fileName).inserted }
    }

    private var selectedProduct: InstallRecord? {
        guard let id = selectedProductID else { return nil }
        return allRecords.first { $0.id == id }
    }

    // MARK: - Body

    @Environment(\.colorScheme) private var colorScheme

    private var isDark: Bool { colorScheme == .dark }
    private var bgPrimary:   Color { isDark ? Color(hex: "#0A0D1C") : Color(NSColor.windowBackgroundColor) }
    private var bgSecondary: Color { isDark ? Color(hex: "#0D1020") : Color(NSColor.controlBackgroundColor) }
    private var border:      Color { isDark ? Color(hex: "#1E2132") : Color(NSColor.separatorColor).opacity(0.4) }
    private var labelColor:  Color { isDark ? Color(hex: "#9EA6B4") : Color(NSColor.secondaryLabelColor) }
    private var sectionColor:Color { isDark ? Color(hex: "#696E7C") : Color(NSColor.tertiaryLabelColor) }
    private var textPrimary: Color { isDark ? Color(hex: "#F0F2FF") : Color(NSColor.labelColor) }
    private var textBody:    Color { isDark ? Color(hex: "#D0D8F0") : Color(NSColor.labelColor) }

    var body: some View {
        VStack(spacing: 0) {
            headerView
            Rectangle().fill(border).frame(height: 1)
            if submitted {
                thankYouView
            } else {
                formView
            }
        }
        .frame(width: 440, height: 600)
        .background(bgPrimary)
        .cornerRadius(16)
        .preferredColorScheme(appearance.override)
        .onAppear {
            loadRecentLogs()
            if let pre = preselectedRecord {
                selectedProductID = pre.id
                // Pre-fill issue type based on record status
                switch pre.status {
                case .failure:     issueType = "Install Failed"
                case .uninstalled: issueType = "Uninstall Issue"
                case .success:     issueType = "App Not Opening"
                }
            } else if let first = allRecords.first {
                selectedProductID = first.id
            }
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text("GET SUPPORT")
                    .font(.system(size: 9, weight: .bold)).tracking(2.5)
                    .foregroundColor(sectionColor)
                Text("We'll reply within 24 hours")
                    .font(.system(size: 12))
                    .foregroundColor(labelColor)
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(labelColor)
                    .frame(width: 24, height: 24)
                    .background(bgSecondary)
                    .cornerRadius(6)
            }
            .buttonStyle(.plain)
        }
        .padding(20)
    }

    // MARK: - Form

    private var formView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {

                // Product picker
                sectionLabel("PRODUCT")
                productPickerSection

                // Issue type
                sectionLabel("ISSUE TYPE")
                Picker("Issue", selection: $issueType) {
                    ForEach(issueTypes, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.menu)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(bgSecondary)
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8)
                    .stroke(border, lineWidth: 1))

                // Message
                sectionLabel("DESCRIBE YOUR ISSUE")
                TextEditor(text: $message)
                    .font(.system(size: 12))
                    .foregroundColor(textBody)
                    .frame(minHeight: 90, maxHeight: 130)
                    .padding(10)
                    .background(bgSecondary)
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8)
                        .stroke(border, lineWidth: 1))
                    .background(bgSecondary)

                // Log attach
                if !recentLogs.isEmpty {
                    logAttachSection
                }

                if !errorMsg.isEmpty {
                    Text(errorMsg)
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: "#E05555"))
                }

                submitButton
            }
            .padding(20)
        }
    }

    // MARK: - Product picker

    private var productPickerSection: some View {
        VStack(spacing: 6) {
            if productList.isEmpty {
                Text("No install history found")
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "#696E7C"))
                    .padding(.vertical, 10)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(productList) { record in
                            productChip(record: record)
                        }
                    }
                    .padding(.horizontal, 1)
                    .padding(.vertical, 2)
                }
            }
        }
    }

    @ViewBuilder
    private func productChip(record: InstallRecord) -> some View {
        let isSelected = selectedProductID == record.id
        Button { selectedProductID = record.id } label: {
            HStack(spacing: 5) {
                Image(systemName: record.statusIcon)
                    .font(.system(size: 9))
                    .foregroundColor(chipStatusColor(record))
                Text(record.fileName)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(isSelected ? textPrimary : labelColor)
                    .lineLimit(1)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(isSelected ? Color(hex: "#3ECFB2").opacity(0.12) : bgSecondary)
            .cornerRadius(7)
            .overlay(RoundedRectangle(cornerRadius: 7)
                .strokeBorder(isSelected ? Color(hex: "#3ECFB2").opacity(0.6) : border,
                              lineWidth: isSelected ? 1.0 : 0.75))
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }

    private func chipStatusColor(_ record: InstallRecord) -> Color {
        switch record.status {
        case .success:     return Color(hex: "#2ECC8A")
        case .failure:     return Color(hex: "#E05555")
        case .uninstalled: return Color(hex: "#696E7C")
        }
    }

    // MARK: - Log attach

    private var logAttachSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("ATTACH A LOG (OPTIONAL)")
            ForEach(recentLogs) { log in
                Button { selectedLog = selectedLog?.id == log.id ? nil : log } label: {
                    HStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(selectedLog?.id == log.id
                                      ? Color(hex: "#3ECFB2").opacity(0.15) : Color(hex: "#0A0D1C"))
                                .frame(width: 18, height: 18)
                                .overlay(Circle().stroke(
                                    selectedLog?.id == log.id
                                        ? Color(hex: "#3ECFB2") : Color(hex: "#2E3350"),
                                    lineWidth: 1.5))
                            if selectedLog?.id == log.id {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(Color(hex: "#3ECFB2"))
                            }
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(log.filename)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(labelColor)
                                .lineLimit(1)
                            Text(log.type.uppercased())
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(log.type == "failed"
                                    ? Color(hex: "#E05555") : Color(hex: "#F0A030"))
                        }
                        Spacer()
                    }
                    .padding(10)
                    .background(bgSecondary)
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8)
                        .stroke(selectedLog?.id == log.id
                                ? Color(hex: "#3ECFB2").opacity(0.4) : border,
                                lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Submit button

    private var submitButton: some View {
        Button { Task { await submit() } } label: {
            HStack(spacing: 6) {
                if submitting {
                    ProgressView().scaleEffect(0.7).frame(width: 14, height: 14)
                }
                Text(submitting ? "Sending…" : "Send Support Request")
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundColor(canSubmit ? Color(hex: "#08090E") : Color(hex: "#696E7C"))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(canSubmit ? Color(hex: "#3ECFB2") : Color(hex: "#141A30"))
            .cornerRadius(9)
            .overlay(RoundedRectangle(cornerRadius: 9)
                .stroke(canSubmit ? Color.clear : Color(hex: "#2E3350"), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(!canSubmit || submitting)
        .animation(.easeInOut(duration: 0.2), value: canSubmit)
    }

    // MARK: - Thank You screen

    private var thankYouView: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 20) {
                // Icon
                ZStack {
                    Circle()
                        .fill(Color(hex: "#3ECFB2").opacity(0.1))
                        .frame(width: 80, height: 80)
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 44))
                        .foregroundColor(Color(hex: "#3ECFB2"))
                }

                VStack(spacing: 8) {
                    Text("Thank You!")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(textPrimary)

                    Text("Your support request has been received.")
                        .font(.system(size: 13))
                        .foregroundColor(labelColor)
                        .multilineTextAlignment(.center)

                    Text("Our support team will be with you shortly.\nWe'll reply to \(auth.userEmail) within 24 hours.")
                        .font(.system(size: 12))
                        .foregroundColor(sectionColor)
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
                }

                // Product tag
                if let product = selectedProduct {
                    HStack(spacing: 6) {
                        Image(systemName: product.statusIcon)
                            .font(.system(size: 10))
                            .foregroundColor(chipStatusColor(product))
                        Text(product.fileName)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(labelColor)
                            .lineLimit(1)
                        Text("·")
                            .foregroundColor(sectionColor)
                        Text(issueType)
                            .font(.system(size: 11))
                            .foregroundColor(sectionColor)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(bgSecondary)
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8)
                        .stroke(border, lineWidth: 1))
                }
            }
            .padding(.horizontal, 32)

            Spacer()

            // Back to ATLAS button
            Button { dismiss() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Back to ATLAS")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundColor(Color(hex: "#08090E"))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(Color(hex: "#3ECFB2"))
                .cornerRadius(9)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .bold)).tracking(2)
            .foregroundColor(sectionColor)
    }

    var canSubmit: Bool {
        message.trimmingCharacters(in: .whitespacesAndNewlines).count >= 10
    }

    // MARK: - Submit

    private func submit() async {
        submitting = true; errorMsg = ""
        guard let s = KeychainManager.loadSession(), !s.isExpired else {
            errorMsg = "Session expired. Please sign in again."
            submitting = false; return
        }
        guard let url = URL(string: "https://www.interlinked.digital/api/atlas/support") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(s.accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = [
            "issue_type":   issueType,
            "message":      message,
            "device_name":  deviceFriendlyName(),
            "product_name": selectedProduct?.fileName ?? "Unknown",
            "product_status": selectedProduct?.status.rawValue ?? "",
            "product_date": selectedProduct.map { ISO8601DateFormatter().string(from: $0.date) } ?? ""
        ]
        if let log = selectedLog {
            body["attached_log_filename"] = log.filename
            body["attached_log_content"]  = log.content
        }
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        let (_, response) = (try? await URLSession.shared.data(for: req)) ?? (Data(), nil)
        let ok = (response as? HTTPURLResponse).map { (200...299).contains($0.statusCode) } ?? false
        await MainActor.run {
            submitting = false
            if ok { submitted = true } else { errorMsg = "Failed to send. Please try again." }
        }
    }

    private func loadRecentLogs() {
        var logs: [LocalLog] = []
        let dirs: [(URL, String)] = [
            (InstallLogger.failedLogsDir, "failed"),
            (InstallLogger.crashLogsDir,  "crashed")
        ]
        for (dir, type) in dirs {
            guard let items = try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: [.creationDateKey],
                options: [.skipsHiddenFiles]) else { continue }
            for item in items.prefix(5) {
                let date = (try? item.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
                let content = (try? String(contentsOf: item, encoding: .utf8)) ?? ""
                logs.append(LocalLog(filename: item.lastPathComponent, type: type,
                                     content: content, date: date))
            }
        }
        recentLogs = logs.sorted { $0.date > $1.date }.prefix(6).map { $0 }

        // Auto-select the log matching the pre-selected record if there is one
        if let pre = preselectedRecord {
            selectedLog = recentLogs.first {
                $0.filename.contains(pre.logFileName) ||
                pre.logFileName.contains($0.filename)
            }
        }
    }
}
