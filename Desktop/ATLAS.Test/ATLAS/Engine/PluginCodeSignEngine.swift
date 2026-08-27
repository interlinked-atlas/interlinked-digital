import Foundation

struct CodeSignError: Error {
    let message: String
    init(_ message: String) { self.message = message }
    var localizedDescription: String { message }
}

// PluginCodeSignEngine — ATLAS Library Code-Sign for plugin formats (Pro only).
// Performs ad-hoc codesign on installed or disabled plugin bundles tracked by ATLAS.
// Signing is performed at the plugin's current physical location; enabled/disabled
// state is never changed by this engine.
// Supported formats: .vst, .vst3, .component, .aaxplugin

struct PluginCodeSignEngine {

    private static let supportedExtensions: Set<String> = ["vst", "vst3", "component", "aaxplugin"]

    // MARK: - Sign

    static func sign(
        pluginPath: String,
        record: InstallRecord
    ) async -> Result<Void, CodeSignError> {

        // Pro gate (engine level — never rely on UI alone)
        guard Features.codeSign else {
            return .failure(CodeSignError("Code-Sign requires ATLAS Pro."))
        }

        // Extension must be a supported audio plugin format
        let ext = URL(fileURLWithPath: pluginPath).pathExtension.lowercased()
        guard supportedExtensions.contains(ext) else {
            return .failure(CodeSignError("Code-Sign is only supported for audio plugin bundles (.vst, .vst3, .component, .aaxplugin)."))
        }

        // Ownership: path must be tracked by this record (enabled or disabled state)
        let ownedByInstalled = record.installedFiles.contains { $0.destinationPath == pluginPath }
        let ownedByDisabled  = record.disabledFormats?.contains { $0.disabledStoragePath == pluginPath } == true
        guard ownedByInstalled || ownedByDisabled else {
            return .failure(CodeSignError("ATLAS cannot sign this plugin because it is not tracked by this install record."))
        }

        // Plugin must exist at the given path
        guard FileManager.default.fileExists(atPath: pluginPath) else {
            return .failure(CodeSignError("The plugin was not found at its expected location:\n\(pluginPath)"))
        }

        guard let password = KeychainManager.loadPassword() else {
            return .failure(CodeSignError("No admin password stored. Set your Mac password in ATLAS Settings."))
        }

        // Remove .DS_Store from the bundle root before signing.
        // Its presence causes codesign to report "unsealed contents present in the bundle root",
        // which fails strict codesign -v verification.
        let bundleRootDSStore = pluginPath + "/.DS_Store"
        if FileManager.default.fileExists(atPath: bundleRootDSStore) {
            _ = runWithPassword(password: password,
                               arguments: ["/bin/rm", "-f", bundleRootDSStore])
        }

        // Sign: sudo /usr/bin/codesign --force --deep --sign - <pluginPath>
        // Path is passed as a separate argument — no shell parsing, no quoting required.
        // Handles paths with spaces, apostrophes, and any other characters safely.
        let signResult = runWithPassword(
            password: password,
            arguments: ["/usr/bin/codesign", "--force", "--deep", "--sign", "-", pluginPath]
        )

        let signOutputLower = signResult.output.lowercased()
        let signOK = signResult.success
            || signOutputLower.contains("replacing existing signature")
            || signOutputLower.contains("unsealed contents")

        guard signOK else {
            return .failure(CodeSignError("Code signing failed:\n\(signResult.output)"))
        }

        // Post-sign verification: /usr/bin/codesign -v <pluginPath>
        // Read-only — no sudo required.
        let verifyResult = runProcess(
            path: "/usr/bin/codesign",
            arguments: ["-v", pluginPath]
        )
        guard verifyResult.success else {
            return .failure(CodeSignError(
                "Signing completed but verification failed:\n\(verifyResult.output)\n\n" +
                "The plugin may be in an inconsistent state. You can retry Code-Sign."
            ))
        }

        return .success(())
    }

    // MARK: - Process helpers

    // Privileged execution via sudo -S with password piped on stdin.
    // Arguments are an explicit [String] array — no shell involved.
    private static func runWithPassword(
        password: String,
        arguments: [String]
    ) -> (success: Bool, output: String) {
        let process = Process()
        let inputPipe  = Pipe()
        let outputPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        process.arguments     = ["-S"] + arguments
        process.standardInput  = inputPipe
        process.standardOutput = outputPipe
        process.standardError  = outputPipe
        do {
            try process.run()
            inputPipe.fileHandleForWriting.write((password + "\n").data(using: .utf8)!)
            inputPipe.fileHandleForWriting.closeFile()
            process.waitUntilExit()
        } catch {
            return (false, error.localizedDescription)
        }
        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        return (process.terminationStatus == 0, String(data: data, encoding: .utf8) ?? "")
    }

    // Non-privileged process execution — used for read-only codesign -v verification.
    private static func runProcess(
        path: String,
        arguments: [String]
    ) -> (success: Bool, output: String) {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments     = arguments
        process.standardOutput = pipe
        process.standardError  = pipe
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return (false, error.localizedDescription)
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return (process.terminationStatus == 0, String(data: data, encoding: .utf8) ?? "")
    }
}
