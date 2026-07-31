import Foundation

// ATLASFailureReporter — uploads install failure data to Supabase after every failed install.
// This feeds the admin dashboard so patterns can be fixed without a rebuild.
// Fire-and-forget: failure to upload never affects the user experience.

struct ATLASFailureReporter {

    // Called after any install that results in .failure
    static func report(
        productName:     String,
        sourceURL:       URL,
        failureReason:   String,
        failureStep:     String?  = nil,
        failureType:     String?  = nil,
        stepsAttempted:  [String] = [],
        errorOutput:     String?  = nil,
        installLog:      String?  = nil,
        planSource:      String   = ""
    ) {
        guard UserDefaults.standard.bool(forKey: "ATLAS.privacyConsentGiven"),
              let session = KeychainManager.loadSession(), !session.isExpired else { return }

        let macOS = ProcessInfo.processInfo.operatingSystemVersionString

        Task.detached {
            await upload(
                accessToken:    session.accessToken,
                productName:    productName,
                sourceFilename: sourceURL.lastPathComponent,
                failureReason:  failureReason,
                failureStep:    failureStep   ?? classifyStep(from: failureReason),
                failureType:    failureType   ?? classifyType(from: failureReason),
                stepsAttempted: stepsAttempted,
                errorOutput:    errorOutput,
                installLog:     installLog,
                deviceName:     deviceFriendlyName(),
                hardwareUUID:   atlasHardwareUUID(),
                macosVersion:   macOS,
                planSource:     planSource
            )
        }
    }

    // MARK: - Auto-classify failure type from reason string

    static func classifyType(from reason: String) -> String {
        let lower = reason.lowercased()
        if lower.contains("titan verify")  { return "verify" }
        if lower.contains("demo mode")     { return "demo" }
        if lower.contains("pkg") || lower.contains("receipt") { return "pkg" }
        if lower.contains("script") || lower.contains("bash") || lower.contains("sh:") { return "script" }
        if lower.contains("binary") || lower.contains("exec") { return "binary" }
        if lower.contains("cancelled")     { return "cancelled" }
        if lower.contains("confidence")    { return "scan" }
        return "unknown"
    }

    static func classifyStep(from reason: String) -> String {
        let lower = reason.lowercased()
        if lower.contains("receipt")  { return "PKG receipt missing" }
        if lower.contains("files on disk") { return "Files not found on disk" }
        if lower.contains("app launch") { return "App failed to launch" }
        if lower.contains("auval") || lower.contains("au (") { return "Audio Unit validation" }
        if lower.contains("mach-o")    { return "Plugin binary invalid" }
        if lower.contains("script")    { return "Script execution" }
        if lower.contains("pkg")       { return "PKG installation" }
        if lower.contains("confidence") { return "Pre-install scan" }
        return "Unknown step"
    }

    // MARK: - Upload

    private static func upload(
        accessToken:    String,
        productName:    String,
        sourceFilename: String,
        failureReason:  String,
        failureStep:    String,
        failureType:    String,
        stepsAttempted: [String],
        errorOutput:    String?,
        installLog:     String?,
        deviceName:     String,
        hardwareUUID:   String,
        macosVersion:   String,
        planSource:     String
    ) async {
        guard let url = URL(string: "https://www.interlinked.digital/api/atlas/failures") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 12

        var body: [String: Any] = [
            "product_name":    productName,
            "source_filename": sourceFilename,
            "failure_reason":  failureReason,
            "failure_step":    failureStep,
            "failure_type":    failureType,
            "steps_attempted": stepsAttempted,
            "device_name":     deviceName,
            "hardware_uuid":   hardwareUUID,
            "macos_version":   macosVersion,
            "plan_source":     planSource,
        ]
        if let err = errorOutput  { body["error_output"] = err }
        if let log = installLog   { body["install_log"]  = log }

        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        _ = try? await URLSession.shared.data(for: req)
    }
}
