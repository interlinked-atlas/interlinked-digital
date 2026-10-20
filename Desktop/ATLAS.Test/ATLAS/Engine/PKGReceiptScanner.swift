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

    // Returns all receipts involved in this installation transaction.
    //
    // A receipt is attributed to this transaction if:
    //   A. It is new — appeared in `after` but not in `before` (after − before), OR
    //   B. It pre-existed but its on-disk plist/bom was rewritten during the install window.
    //      macOS always rewrites the plist and bom when a PKG component is (re)installed,
    //      even for pre-existing receipt IDs. The modification timestamp is therefore a
    //      reliable signal that the installer touched that receipt during this transaction.
    //
    // The window is [since − 5s, now] to give slow installers a 5-second grace period.
    // Both new and updated receipts must pass the timestamp test — this prevents
    // background processes (e.g. Toontrack Product Manager, Acrobat updater) from being
    // attributed merely because they ran while ATLAS was waiting for the installer.
    //
    // Attribution boundary: only receipts that macOS wrote to /var/db/receipts during
    // this transaction window. Receipts with timestamps outside the window are excluded
    // regardless of their name or vendor.
    static func findNewReceipts(before: Set<String>, since: Date) -> [String] {
        let after = snapshotReceipts()
        let receiptDir = "/private/var/db/receipts"
        let grace = since.addingTimeInterval(-5)  // 5s grace for slow installers

        // Receipts whose plist/bom timestamp falls within the transaction window.
        // Applies to both genuinely new receipts (after − before) and pre-existing
        // receipts that the installer updated (before ∩ after, with fresh timestamps).
        let allCandidates = after  // scan every post-install receipt against the time window
        return allCandidates.filter { id in
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

    // General-purpose receipt attribution for multi-component/distribution PKG installs.
    //
    // ATTRIBUTION BOUNDARY: Only receipts in (after − before) can be attributed to this
    // transaction. A receipt that existed in the before snapshot is NEVER claimed by this
    // installation, regardless of whether its ID matches the installer name.
    //
    // Algorithm:
    //   1. Poll pkgutil --pkgs every 500 ms, computing (after − before) at each poll.
    //   2. Stop when the set is unchanged for 2 consecutive polls (~1 s stable), or after
    //      a 15-second hard cap — whichever comes first.
    //   3. Take one final snapshot after the stable window to catch any receipt written
    //      during the last polling interval.
    //   4. allNewReceipts = finalAfter − before  (the complete attribution boundary)
    //   5. Apply name-based matching ONLY within allNewReceipts — never against the full
    //      receipt database — so pre-existing receipts cannot be claimed.
    //   6. Return stability-confirmed ∪ name-matched, both constrained to allNewReceipts.
    //
    // Note: the 1-second stability window is a practical heuristic, not a mathematical
    // guarantee that macOS has finished registering every possible component receipt.
    // The (after − before) boundary is the critical safety invariant.
    static func captureNewReceipts(before: Set<String>, installerName: String) -> [String] {
        let deadline      = Date().addingTimeInterval(15.0)
        var lastSet       = Set<String>()
        var stableCount   = 0
        let stableRequired = 2   // 2 consecutive unchanged polls ≈ 1 second

        while Date() < deadline {
            Thread.sleep(forTimeInterval: 0.5)
            let current = Set(snapshotReceipts()).subtracting(before)
            if current == lastSet {
                stableCount += 1
                if stableCount >= stableRequired { break }
            } else {
                lastSet       = current
                stableCount   = 0
            }
        }

        // Final snapshot — catches receipts written during the last polling interval.
        let allNewReceipts = Set(snapshotReceipts()).subtracting(before)

        // Name-based supplement: intersect with allNewReceipts so we can never claim
        // a receipt that already existed before this installation.
        let nameMatched = Set(findReceiptsByName(installerName)).intersection(allNewReceipts)

        // allNewReceipts (final snapshot) is the complete attribution boundary.
        // Using it — rather than lastSet — captures receipts that registered
        // after the stability window closed (e.g. installer helpers that write
        // receipts asynchronously after the main process exits).
        return Array(allNewReceipts.union(nameMatched)).sorted()
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
