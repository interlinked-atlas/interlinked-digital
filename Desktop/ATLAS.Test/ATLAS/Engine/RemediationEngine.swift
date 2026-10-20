import Foundation

// RemediationEngine tries to fix installation failures automatically.
// It detects what went wrong and applies the appropriate fix,
// then signals the caller to retry the installation.
//
// Remediation is always logged and always requires the stored password.
// ATLAS never silently modifies system security settings.

enum RemediationAction: String {
    case removeQuarantine    = "Remove quarantine flag"
    case codesign            = "Apply ad-hoc codesign"
    case disableGatekeeper   = "Temporarily bypass Gatekeeper"
    case fixPermissions      = "Fix file permissions"
    case none                = "No remediation available"
}

struct RemediationResult {
    let action: RemediationAction
    let success: Bool
    let detail: String
}

struct RemediationEngine {

    // Main entry point — called after a failed install.
    // Detects the failure type and applies the right fix.
    static func remediate(
        url: URL,
        failureReason: String,
        logger: Logger
    ) async -> RemediationResult {

        await logger.log("--- Remediation started ---")
        await logger.log("Analyzing failure: \(failureReason)")

        // Detect what kind of failure we're dealing with
        let failure = detectFailureType(url: url, reason: failureReason)
        await logger.log("Detected failure type: \(failure)")

        switch failure {
        case "quarantine":
            return await removeQuarantine(url: url, logger: logger)
        case "unsigned":
            return await applyCodesign(url: url, logger: logger)
        case "gatekeeper":
            return await bypassGatekeeper(url: url, logger: logger)
        case "permissions":
            return await fixPermissions(url: url, logger: logger)
        default:
            await logger.log("No automatic remediation available for this failure")
            return RemediationResult(
                action: .none,
                success: false,
                detail: "Could not automatically fix: \(failureReason)"
            )
        }
    }

    // MARK: - Failure Detection

    private static func detectFailureType(url: URL, reason: String) -> String {
        let lower = reason.lowercased()

        // Check quarantine flag on the file
        let xattrResult = runProcess(
            path: "/usr/bin/xattr",
            arguments: ["-l", url.path]
        )
        if xattrResult.output.contains("com.apple.quarantine") {
            return "quarantine"
        }

        // Check if it's a Gatekeeper block
        let spctlResult = runProcess(
            path: "/usr/sbin/spctl",
            arguments: ["--assess", "--type", "execute", url.path]
        )
        if !spctlResult.success {
            // Check if it's unsigned vs Gatekeeper policy
            let codesignResult = runProcess(
                path: "/usr/bin/codesign",
                arguments: ["-v", url.path]
            )
            if codesignResult.output.contains("not signed") ||
               codesignResult.output.contains("no signature") {
                return "unsigned"
            }
            return "gatekeeper"
        }

        if lower.contains("permission") || lower.contains("operation not permitted") {
            return "permissions"
        }

        return "unknown"
    }

    // MARK: - Remediation Actions

    // Removes the quarantine extended attribute from the file.
    // This is the most common fix for downloaded installers.
    private static func removeQuarantine(url: URL, logger: Logger) async -> RemediationResult {
        await logger.log("Removing quarantine flag from \(url.lastPathComponent)...")

        guard let password = KeychainManager.loadPassword() else {
            return RemediationResult(action: .removeQuarantine, success: false,
                                   detail: "No password stored in Keychain.")
        }

        let result = runProcessWithPassword(
            password: password,
            arguments: ["/usr/bin/xattr", "-rd", "com.apple.quarantine", url.path]
        )

        if result.success {
            await logger.log("✓ Quarantine flag removed")
            return RemediationResult(action: .removeQuarantine, success: true,
                                   detail: "Quarantine flag removed successfully.")
        } else {
            await logger.log("✗ Could not remove quarantine: \(result.output)")
            return RemediationResult(action: .removeQuarantine, success: false,
                                   detail: result.output)
        }
    }

    // Applies an ad-hoc codesign to unsigned binaries.
    // This does NOT add a real certificate — it just satisfies
    // macOS's requirement that executables be signed.
    private static func applyCodesign(url: URL, logger: Logger) async -> RemediationResult {
        await logger.log("Applying ad-hoc codesign to \(url.lastPathComponent)...")

        guard let password = KeychainManager.loadPassword() else {
            return RemediationResult(action: .codesign, success: false,
                                   detail: "No password stored in Keychain.")
        }

        // First remove quarantine, then codesign
        _ = runProcessWithPassword(
            password: password,
            arguments: ["/usr/bin/xattr", "-rd", "com.apple.quarantine", url.path]
        )

        let result = runProcessWithPassword(
            password: password,
            arguments: ["/usr/bin/codesign", "--force", "--deep", "--sign", "-", url.path]
        )

        if result.success {
            await logger.log("✓ Ad-hoc codesign applied")
            return RemediationResult(action: .codesign, success: true,
                                   detail: "Ad-hoc codesign applied successfully.")
        } else {
            await logger.log("✗ Codesign failed: \(result.output)")
            return RemediationResult(action: .codesign, success: false,
                                   detail: result.output)
        }
    }

    // Bypasses Gatekeeper for this specific file only.
    // Uses spctl to add an exception — does NOT disable Gatekeeper globally.
    private static func bypassGatekeeper(url: URL, logger: Logger) async -> RemediationResult {
        await logger.log("Bypassing Gatekeeper for \(url.lastPathComponent)...")
        await logger.log("Note: this adds a file-specific exception only.")

        guard let password = KeychainManager.loadPassword() else {
            return RemediationResult(action: .disableGatekeeper, success: false,
                                   detail: "No password stored in Keychain.")
        }

        // Remove quarantine first
        _ = runProcessWithPassword(
            password: password,
            arguments: ["/usr/bin/xattr", "-rd", "com.apple.quarantine", url.path]
        )

        // Apply ad-hoc signature
        let codesignResult = runProcessWithPassword(
            password: password,
            arguments: ["/usr/bin/codesign", "--force", "--deep", "--sign", "-", url.path]
        )

        if codesignResult.success {
            await logger.log("✓ Gatekeeper bypass applied")
            return RemediationResult(action: .disableGatekeeper, success: true,
                                   detail: "File-specific Gatekeeper exception applied.")
        } else {
            await logger.log("✗ Gatekeeper bypass failed: \(codesignResult.output)")
            return RemediationResult(action: .disableGatekeeper, success: false,
                                   detail: codesignResult.output)
        }
    }

    // Fixes file permissions using chmod
    private static func fixPermissions(url: URL, logger: Logger) async -> RemediationResult {
        await logger.log("Fixing permissions for \(url.lastPathComponent)...")

        guard let password = KeychainManager.loadPassword() else {
            return RemediationResult(action: .fixPermissions, success: false,
                                   detail: "No password stored in Keychain.")
        }

        let result = runProcessWithPassword(
            password: password,
            arguments: ["/bin/chmod", "-R", "755", url.path]
        )

        if result.success {
            await logger.log("✓ Permissions fixed")
            return RemediationResult(action: .fixPermissions, success: true,
                                   detail: "File permissions corrected.")
        } else {
            await logger.log("✗ Could not fix permissions: \(result.output)")
            return RemediationResult(action: .fixPermissions, success: false,
                                   detail: result.output)
        }
    }

    // MARK: - Process Helpers

    private static func runProcessWithPassword(
        password: String,
        arguments: [String]
    ) -> (success: Bool, output: String) {
        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        process.arguments = ["-S"] + arguments
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = outputPipe
        do {
            try process.run()
            let passwordData = (password + "\n").data(using: .utf8)!
            inputPipe.fileHandleForWriting.write(passwordData)
            inputPipe.fileHandleForWriting.closeFile()
            process.waitUntilExit()
        } catch {
            return (false, error.localizedDescription)
        }
        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        return (process.terminationStatus == 0, output)
    }

    private static func runProcess(
        path: String,
        arguments: [String]
    ) -> (success: Bool, output: String) {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return (false, error.localizedDescription)
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        return (process.terminationStatus == 0, output)
    }
}
