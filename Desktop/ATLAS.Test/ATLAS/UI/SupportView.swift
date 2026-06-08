import SwiftUI
import AppKit

struct SupportView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var auth = AuthManager.shared

    @State private var issueType   = "Install Failed"
    @State private var message     = ""
    @State private var selectedLog: LocalLog? = nil
    @State private var recentLogs: [LocalLog] = []
    @State private var submitting  = false
    @State private var submitted   = false
    @State private var errorMsg    = ""

    private let issueTypes = [
        "Install Failed", "Uninstall Issue", "App Not Opening",
        "Subscription Issue", "Performance Issue", "Feature Request", "Other"
    ]

    struct LocalLog: Identifiable {
        let id = UUID()
        let filename: String
        let type: String
        let content: String
        let date: Date
    }

    // MARK: - Sub-views (broken out to satisfy type-checker)

    var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("GET SUPPORT")
                    .font(.system(size: 9, weight: .bold)).tracking(2.5)
                    .foregroundColor(Color(hex: "#353860"))
                Text("We'll reply within 24 hours")
                    .font(.system(size: 12))
                    .foregroundColor(Color(hex: "#6B7399"))
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Color(hex: "#6B7399"))
                    .frame(width: 24, height: 24)
                    .background(Color(hex: "#1E2132"))
                    .cornerRadius(6)
            }
            .buttonStyle(.plain)
        }
        .padding(20)
    }

    var successView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44))
                .foregroundColor(Color(hex: "#3ECFB2"))
            Text("Message sent")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(Color(hex: "#F0F2FF"))
            Text("We'll reply to \(auth.userEmail) within 24 hours.")
                .font(.system(size: 12))
                .foregroundColor(Color(hex: "#6B7399"))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }

    var formView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {

                // Issue type
                VStack(alignment: .leading, spacing: 6) {
                    Text("ISSUE TYPE")
                        .font(.system(size: 9, weight: .bold)).tracking(2)
                        .foregroundColor(Color(hex: "#353860"))
                    Picker("Issue", selection: $issueType) {
                        ForEach(issueTypes, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.menu)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Color(hex: "#0A0D1C"))
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(hex: "#1E2132"), lineWidth: 1))
                }

                // Message
                VStack(alignment: .leading, spacing: 6) {
                    Text("DESCRIBE YOUR ISSUE")
                        .font(.system(size: 9, weight: .bold)).tracking(2)
                        .foregroundColor(Color(hex: "#353860"))
                    TextEditor(text: $message)
                        .font(.system(size: 12))
                        .foregroundColor(Color(hex: "#D0D8F0"))
                        .frame(minHeight: 90, maxHeight: 140)
                        .padding(10)
                        .background(Color(hex: "#0A0D1C"))
                        .cornerRadius(8)
                        .overlay(RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(hex: "#1E2132"), lineWidth: 1))
                }

                // Recent failed/crashed logs
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

    var logAttachSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ATTACH A LOG (OPTIONAL)")
                .font(.system(size: 9, weight: .bold)).tracking(2)
                .foregroundColor(Color(hex: "#353860"))
            ForEach(recentLogs) { log in
                Button {
                    selectedLog = selectedLog?.id == log.id ? nil : log
                } label: {
                    HStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(selectedLog?.id == log.id
                                      ? Color(hex: "#3ECFB2").opacity(0.15)
                                      : Color(hex: "#0A0D1C"))
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
                                .foregroundColor(Color(hex: "#A0A8C8"))
                                .lineLimit(1)
                            Text(log.type.uppercased())
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(log.type == "failed" ? Color(hex: "#E05555") : Color(hex: "#F0A030"))
                        }
                        Spacer()
                    }
                    .padding(10)
                    .background(Color(hex: "#0A0D1C"))
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8)
                        .stroke(selectedLog?.id == log.id
                                ? Color(hex: "#3ECFB2").opacity(0.4)
                                : Color(hex: "#1E2132"), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }

    var submitButton: some View {
        Button {
            Task { await submit() }
        } label: {
            HStack(spacing: 6) {
                if submitting {
                    ProgressView().scaleEffect(0.7).frame(width: 14, height: 14)
                }
                Text(submitting ? "Sending…" : "Send Support Request")
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundColor(canSubmit ? Color(hex: "#08090E") : Color(hex: "#6B7399"))
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

    var body: some View {
        VStack(spacing: 0) {
            headerView
            Rectangle().fill(Color(hex: "#1E2132")).frame(height: 1)
            if submitted {
                successView
            } else {
                formView
            }
        }
        .frame(width: 420, height: 560)
        .background(Color(hex: "#0A0D1C"))
        .cornerRadius(16)
        .onAppear { loadRecentLogs() }
    }

    var canSubmit: Bool { message.trimmingCharacters(in: .whitespacesAndNewlines).count >= 10 }

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
            "issue_type": issueType,
            "message": message,
            "device_name": deviceFriendlyName()
        ]
        if let log = selectedLog {
            body["attached_log_id"] = log.id.uuidString
            body["attached_log_content"] = log.content
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
            (InstallLogger.crashLogsDir, "crashed")
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
    }
}
