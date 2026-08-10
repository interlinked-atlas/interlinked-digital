import Foundation

struct PKGReceiptScanner {

    // System receipt prefixes we never touch
    private static let systemPrefixes = [
        "com.apple.",
        "com.microsoft.",
        "org.webkit.",
        "com.adobe.acrobat"
    ]

    static func snapshotReceipts() -> Set<String> {
        let result = runProcess(path: "/usr/sbin/pkgutil", arguments: ["--pkgs"])
        return Set(result.output
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .filter { id in !systemPrefixes.contains { id.hasPrefix($0) } }
        )
    }

    // Only returns receipts whose on-disk plist/bom was written AFTER `since`.
    // This filters out receipts updated by background processes (e.g. Toontrack
    // Product Manager) that happened to run during the install window.
    static func findNewReceipts(before: Set<String>, since: Date) -> [String] {
        let after = snapshotReceipts()
        let candidates = Array(after.subtracting(before))
        let receiptDir = "/private/var/db/receipts"
        let grace = since.addingTimeInterval(-5)  // 5s grace for slow installers
        return candidates.filter { id in
            for suffix in [".plist", ".bom"] {
                let p = "\(receiptDir)/\(id)\(suffix)"
                if let attrs = try? FileManager.default.attributesOfItem(atPath: p),
                   let mod = attrs[.modificationDate] as? Date,
                   mod >= grace { return true }
            }
            return false
        }.sorted()
    }

    // Match by name — filters system receipts and uses
    // only meaningful keywords from the installer filename
    static func findReceiptsByName(_ name: String) -> [String] {
        let all = snapshotReceipts()

        // Extract meaningful words (5+ chars, skip common words and ATLAS's own name)
        let skipWords = ["audio", "plugin", "installer", "setup",
                        "install", "macos", "universal", "moria",
                        "crack", "patch",
                        // Never use ATLAS's own name as a receipt search keyword —
                        // would match digital.interlinked.atlas.* and trash the app itself.
                        "atlas", "interlinked", "titan", "digital"]
        let keywords = name
            .replacingOccurrences(of: ".pkg", with: "")
            .replacingOccurrences(of: ".dmg", with: "")
            .replacingOccurrences(of: ".iso", with: "")
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .components(separatedBy: .whitespaces)
            .map { $0.lowercased() }
            .filter { $0.count >= 5 && !skipWords.contains($0) }

        guard !keywords.isEmpty else { return [] }

        return all.filter { receipt in
            // Token-boundary match: split receipt ID on component delimiters and
            // require the keyword to exactly equal one segment. Prevents "final"
            // from matching "com.finalmix.*" because "finalmix" ≠ "final".
            let segments = Set(receipt.lowercased()
                .components(separatedBy: CharacterSet(charactersIn: "._-"))
                .filter { !$0.isEmpty })
            return keywords.contains { segments.contains($0) }
        }.sorted()
    }

    static func files(forReceipt receiptID: String) -> [String] {
        let result = runProcess(
            path: "/usr/sbin/pkgutil",
            arguments: ["--files", receiptID]
        )
        guard result.success else { return [] }
        return result.output
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { $0.hasPrefix("/") ? $0 : "/\($0)" }
    }

    static func installLocation(forReceipt receiptID: String) -> String {
        let result = runProcess(
            path: "/usr/sbin/pkgutil",
            arguments: ["--pkg-info", receiptID]
        )
        for line in result.output.components(separatedBy: "\n") {
            if line.contains("location:") {
                let parts = line.components(separatedBy: ":")
                if parts.count >= 2 {
                    return parts[1].trimmingCharacters(in: .whitespaces)
                }
            }
        }
        return "/"
    }

    static func pkgName(forReceipt receiptID: String) -> String? {
        let result = runProcess(
            path: "/usr/sbin/pkgutil",
            arguments: ["--pkg-info", receiptID]
        )
        for line in result.output.components(separatedBy: "\n") {
            if line.hasPrefix("package-id:") {
                // e.g. "com.xfer.serum2.Presets" → last component "Presets"
                return receiptID.components(separatedBy: ".").last
            }
        }
        return nil
    }

    static func forgetReceipt(_ receiptID: String, password: String) -> Bool {
        runWithPassword(
            password: password,
            arguments: ["/usr/sbin/pkgutil", "--forget", receiptID]
        ).success
    }

    static func buildInstalledFiles(
        newReceipts: [String]
    ) -> [InstallRecord.InstalledFile] {
        var files: [InstallRecord.InstalledFile] = []
        var seen = Set<String>()

        for receiptID in newReceipts {
            let location = installLocation(forReceipt: receiptID)
            let paths = self.files(forReceipt: receiptID)

            for path in paths {
                let absolute: String
                if path.hasPrefix("/") {
                    absolute = path
                } else if location == "/" {
                    absolute = "/\(path)"
                } else {
                    absolute = "\(location)/\(path)"
                }

                guard !seen.contains(absolute) else { continue }
                seen.insert(absolute)

                var isDir: ObjCBool = false
                let exists = FileManager.default.fileExists(
                    atPath: absolute, isDirectory: &isDir)

                if exists && !isDir.boolValue {
                    files.append(InstallRecord.InstalledFile(
                        sourceName: URL(fileURLWithPath: absolute).lastPathComponent,
                        destinationPath: absolute
                    ))
                }
            }
        }
        return files
    }

    // MARK: - Helpers

    private static func runProcess(
        path: String, arguments: [String], timeout: TimeInterval = 15
    ) -> (success: Bool, output: String) {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe

        var outputData = Data()
        let sema = DispatchSemaphore(value: 0)

        do {
            try process.run()
            pipe.fileHandleForWriting.closeFile()
        } catch {
            return (false, error.localizedDescription)
        }

        DispatchQueue.global(qos: .utility).async {
            outputData = pipe.fileHandleForReading.readDataToEndOfFile()
            sema.signal()
        }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            process.terminate()
        }
        _ = sema.wait(timeout: .now() + 3)

        return (process.terminationStatus == 0, String(data: outputData, encoding: .utf8) ?? "")
    }

    // Timeout: 15s per sudo command. pkgutil --forget on a large receipt can be slow
    // but should never take longer than this. Prevents indefinite hangs on locked DB.
    private static func runWithPassword(
        password: String, arguments: [String], timeout: TimeInterval = 15
    ) -> (success: Bool, output: String) {
        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        process.arguments = ["-S"] + arguments
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        var outputData = Data()
        let sema = DispatchSemaphore(value: 0)

        do {
            try process.run()
            inputPipe.fileHandleForWriting.write((password + "\n").data(using: .utf8)!)
            inputPipe.fileHandleForWriting.closeFile()
            outputPipe.fileHandleForWriting.closeFile()
        } catch {
            return (false, error.localizedDescription)
        }

        DispatchQueue.global(qos: .utility).async {
            outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            sema.signal()
        }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            process.terminate()
        }
        _ = sema.wait(timeout: .now() + 3)

        return (process.terminationStatus == 0, String(data: outputData, encoding: .utf8) ?? "")
    }
}
