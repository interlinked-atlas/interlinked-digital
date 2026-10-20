import Foundation

// ArchiveExtractor — extracts RAR, 7z, and multi-part archives (.001/.002/…).
// Uses the best available tool: unar (The Unarchiver CLI) → unrar → 7z → error.
// unar handles virtually everything and is the preferred tool.

struct ArchiveExtractor {

    struct ExtractionResult {
        let success: Bool
        let error: String?
    }

    // MARK: - Tool detection

    static var unarPath: String? {
        let candidates = [
            "/usr/local/bin/unar",
            "/opt/homebrew/bin/unar",
            "/usr/bin/unar",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static var unrarPath: String? {
        let candidates = [
            "/usr/local/bin/unrar",
            "/opt/homebrew/bin/unrar",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static var sevenZipPath: String? {
        let candidates = [
            "/usr/local/bin/7z",
            "/opt/homebrew/bin/7z",
            "/usr/local/bin/7za",
            "/opt/homebrew/bin/7za",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static var hasAnyTool: Bool { unarPath != nil || unrarPath != nil || sevenZipPath != nil }

    /// Installs unar via Homebrew (installs Homebrew first if needed).
    /// Returns nil on success, error string on failure.
    @discardableResult
    static func installUnar(logger: Logger) async -> String? {
        await logger.log("unar not found — attempting to install via Homebrew…")

        // Ensure Homebrew is present
        let brewPath: String
        if FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/brew") {
            brewPath = "/opt/homebrew/bin/brew"
        } else if FileManager.default.isExecutableFile(atPath: "/usr/local/bin/brew") {
            brewPath = "/usr/local/bin/brew"
        } else {
            await logger.log("  Homebrew not found — installing Homebrew first…")
            let installScript = "/bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
            let r = shell(installScript)
            if !FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/brew") &&
               !FileManager.default.isExecutableFile(atPath: "/usr/local/bin/brew") {
                return "Could not install Homebrew: \(r.suffix(200))"
            }
            brewPath = FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/brew")
                ? "/opt/homebrew/bin/brew" : "/usr/local/bin/brew"
        }

        await logger.log("  Installing unar via \(brewPath)…")
        let result = shell("\(brewPath) install unar 2>&1")
        if unarPath != nil {
            await logger.log("  ✓ unar installed successfully")
            return nil
        }
        return "Failed to install unar: \(result.suffix(200))"
    }

    // MARK: - Entry point

    static func extract(url: URL, to destination: String) -> ExtractionResult {
        let ext = url.pathExtension.lowercased()

        // unar handles RAR, 7z, multi-part, and most others natively
        if let unar = unarPath {
            return runTool(path: unar, arguments: ["-o", destination, "-f", url.path])
        }

        // unrar for .rar and .001 multi-part
        if ["rar","001"].contains(ext), let unrar = unrarPath {
            return runTool(path: unrar, arguments: ["x", "-o+", url.path, destination + "/"])
        }

        // 7z as final fallback
        if let sz = sevenZipPath {
            return runTool(path: sz, arguments: ["x", url.path, "-o\(destination)", "-y"])
        }

        // No tool available — guide user
        return ExtractionResult(
            success: false,
            error: "Cannot extract \(ext.uppercased()) files. Install The Unarchiver (free on Mac App Store) or run: brew install unar")
    }

    // MARK: - Password-protected RAR

    static func extractWithPassword(url: URL, to destination: String, password: String) -> Bool {
        let esc = { (s: String) -> String in "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        if let unar = unarPath {
            let r = shell("\(esc(unar)) -o \(esc(destination)) -f -p \(esc(password)) \(esc(url.path)) 2>&1")
            return !r.lowercased().contains("error") && !r.lowercased().contains("failed")
        }
        if let unrar = unrarPath {
            let r = shell("\(esc(unrar)) x -p\(esc(password)) \(esc(url.path)) \(esc(destination + "/")) 2>&1")
            return !r.lowercased().contains("wrong password") && !r.lowercased().contains("crc failed")
        }
        return false
    }

    // MARK: - Helpers

    private static func runTool(path: String, arguments: [String]) -> ExtractionResult {
        let p = Process()
        p.launchPath = path
        p.arguments  = arguments
        let pipe = Pipe()
        p.standardOutput = pipe; p.standardError = pipe
        do { try p.run() } catch { return ExtractionResult(success: false, error: error.localizedDescription) }
        p.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let success = p.terminationStatus == 0
        return ExtractionResult(success: success, error: success ? nil : String(out.suffix(300)))
    }

    @discardableResult
    private static func shell(_ cmd: String) -> String {
        let p = Process()
        p.launchPath = "/bin/bash"; p.arguments = ["-c", cmd]
        let pipe = Pipe()
        p.standardOutput = pipe; p.standardError = pipe
        try? p.run(); p.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }
}
