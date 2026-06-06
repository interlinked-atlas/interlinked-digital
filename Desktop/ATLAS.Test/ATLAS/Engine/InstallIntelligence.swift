import Foundation

// InstallIntelligence reads installation instructions and
// determines the correct install order before anything runs.
//
// Priority order:
// 1. Parse instruction file if present — follow it explicitly
// 2. Use filename numbering (1. installer, 2. patch)
// 3. Use keyword detection (patch, license, activat, keygen)
// 4. Manager apps (Central, Manager, Hub, etc.) always run last, after PKGs
// 5. Always: standard installers before patches

struct InstallPlan {
    let instructions: ParsedInstructions?
    let orderedSteps: [InstallStep]
    let warnings: [String]
    let summary: String
}

struct InstallStep: Identifiable {
    let id = UUID()
    let url: URL
    let type: StepType
    let order: Int
    let note: String

    enum StepType {
        case installer       // standard .pkg / .mpkg
        case patch           // crack, keygen, license tool
        case plugin          // audio plugin bundle
        case app             // plain .app — copy to /Applications
        case managedInstall  // manager app that must be launched and automated
        case manual          // requires manual action
    }

    var label: String {
        switch type {
        case .installer:      return "Install"
        case .patch:          return "Apply patch"
        case .plugin:         return "Install plugin"
        case .app:            return "Copy app"
        case .managedInstall: return "Run installer"
        case .manual:         return "Manual step"
        }
    }

    var icon: String {
        switch type {
        case .installer:      return "shippingbox.fill"
        case .patch:          return "bandage.fill"
        case .plugin:         return "puzzlepiece.fill"
        case .app:            return "app.badge.fill"
        case .managedInstall: return "gearshape.fill"
        case .manual:         return "hand.point.right.fill"
        }
    }
}

struct ParsedInstructions {
    let rawText: String
    let sourceFileName: String
    let steps: [String]
    let mentionsPatch: Bool
    let mentionsOrder: Bool
    let mentionsRosetta: Bool
    let mentionsAdminRequired: Bool
    let customNotes: [String]
    let appToLaunch: String?
    let mentionsSelectAll: Bool
    let mentionsManagerApp: Bool

    // TITAN CORE™ executable steps
    let hostsEntries: [String]           // domains to add to /etc/hosts
    let terminalCommands: [String]       // shell commands to run
    let mentionsXcodeTools: Bool         // xcode-select --install needed
    let scriptsToRun: [String]           // script filenames mentioned
    let binariesToRun: [String]          // binary/tool filenames mentioned
    let detectedLanguage: String         // "en", "ru", etc.
}

struct InstallIntelligence {

    // MARK: - TITAN CORE™ scan: scripts, binaries, and complexity assessment

    struct TitanScanResult {
        let scripts: [URL]           // shell scripts
        let binaries: [URL]          // standalone executables (Mach-O)
        let hostsEntries: [String]   // domains extracted from scripts/instructions
        let needsXcodeTools: Bool
        let isComplex: Bool          // should TITAN Mission activate?
        let hasInstructions: Bool
    }

    static func titanScan(directory: String) -> TitanScanResult {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: URL(fileURLWithPath: directory),
            includingPropertiesForKeys: [.isExecutableKey],
            options: [.skipsHiddenFiles]) else {
            return TitanScanResult(scripts: [], binaries: [], hostsEntries: [],
                                   needsXcodeTools: false, isComplex: false, hasInstructions: false)
        }

        var scripts: [URL] = []
        var binaries: [URL] = []
        var hostsEntries: [String] = []
        let hasInstructions = findAndParseInstructions(in: directory) != nil

        for case let url as URL in enumerator {
            let name = url.lastPathComponent
            let ext  = url.pathExtension.lowercased()

            // Skip known-harmless types
            guard !["pkg", "mpkg", "app", "component", "vst3", "vst",
                    "aaxplugin", "dmg", "iso", "zip", "html", "htm",
                    "txt", "nfo", "rtf", "md", "pdf", "png", "jpg",
                    "icns", "webloc", "DS_Store"].contains(ext),
                  !name.hasPrefix("."),
                  !name.contains("__MACOSX") else { continue }

            // Read first bytes to classify
            guard let handle = try? FileHandle(forReadingFrom: url),
                  let header = try? handle.read(upToCount: 8) else { continue }
            try? handle.close()

            let bytes = [UInt8](header)

            // .command files are shell scripts macOS opens in Terminal — treat as scripts
            if ext == "command" {
                scripts.append(url)
                if let content = try? String(contentsOf: url, encoding: .utf8) {
                    hostsEntries.append(contentsOf: extractHostsFromScript(content))
                }
                continue
            }

            // Shebang → shell script
            if bytes.count >= 2 && bytes[0] == 0x23 && bytes[1] == 0x21 {
                scripts.append(url)
                // Extract hosts entries from the script
                if let content = try? String(contentsOf: url, encoding: .utf8) {
                    hostsEntries.append(contentsOf: extractHostsFromScript(content))
                }
                continue
            }

            // Mach-O magic (fat binary: 0xCAFEBABE, 64-bit: 0xCFFAEDFE / 0xFEEDFACF)
            if bytes.count >= 4 {
                let isMachO = (bytes[0] == 0xCA && bytes[1] == 0xFE && bytes[2] == 0xBA && bytes[3] == 0xBE) ||
                              (bytes[0] == 0xCF && bytes[1] == 0xFA && bytes[2] == 0xED && bytes[3] == 0xFE) ||
                              (bytes[0] == 0xFE && bytes[1] == 0xED && bytes[2] == 0xFA && bytes[3] == 0xCF)
                if isMachO {
                    binaries.append(url)
                    continue
                }
            }
        }

        // Extract hosts entries from the primary instruction file
        if let instr = findAndParseInstructions(in: directory) {
            hostsEntries.append(contentsOf: instr.hostsEntries)
        }

        // Belt-and-suspenders: scan ALL text/html files for "block" patterns.
        // This catches cases where a secondary file (e.g. HTML) holds the block list
        // but a higher-scoring file (e.g. NFO) was chosen as the primary instruction.
        hostsEntries.append(contentsOf: findAllHostsEntries(in: directory))

        let isComplex = !scripts.isEmpty || !binaries.isEmpty || !hostsEntries.isEmpty

        return TitanScanResult(
            scripts: scripts,
            binaries: binaries,
            hostsEntries: Array(Set(hostsEntries)),
            needsXcodeTools: findAndParseInstructions(in: directory)?.mentionsXcodeTools ?? false,
            isComplex: isComplex,
            hasInstructions: hasInstructions
        )
    }

    // Extracts `127.0.0.1 domain` lines from a shell script body
    private static func extractHostsFromScript(_ content: String) -> [String] {
        var domains: [String] = []
        // Pattern: echo '127.0.0.1 domain' >> /etc/hosts
        let patterns = [
            #"127\.0\.0\.1\s+([\w\.\-]+)"#,
            #"echo[^'\"]*['\"]127\.0\.0\.1\s+([\w\.\-]+)"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(content.startIndex..., in: content)
            for match in regex.matches(in: content, range: range) {
                if let r = Range(match.range(at: 1), in: content) {
                    let domain = String(content[r]).trimmingCharacters(in: .whitespaces)
                    if !domain.isEmpty { domains.append(domain) }
                }
            }
        }
        return domains
    }

    // Scans every text/HTML file in the directory for "block address" patterns and
    // returns all discovered domain names. Used as a belt-and-suspenders complement to
    // findAndParseInstructions so that block lists in secondary files are never missed.
    static func findAllHostsEntries(in directory: String) -> [String] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(atPath: directory) else { return [] }
        var domains: [String] = []

        for case let path as String in enumerator {
            guard !path.hasPrefix("._"), !path.contains("__MACOSX") else { continue }
            let url = URL(fileURLWithPath: directory).appendingPathComponent(path)
            let ext = url.pathExtension.lowercased()
            guard ["html", "htm", "txt", "nfo", "rtf", "md"].contains(ext) else { continue }

            // Skip files over 500 KB — real instruction files are small
            if let size = (try? fm.attributesOfItem(atPath: url.path))?[.size] as? Int64,
               size > 500_000 { continue }

            let text = readTextFile(url)
            guard !text.isEmpty else { continue }
            let lower = text.lowercased()

            // Only bother parsing if the file mentions "block" anywhere
            guard lower.contains("block") || lower.contains("127.0.0.1") ||
                  lower.contains("hosts") else { continue }

            let lines = text.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            domains.append(contentsOf: extractBlockContext(from: lower, lines: lines))
        }
        return Array(Set(domains))
    }

    // MARK: - Main entry point

    static func analyze(directory: String, files: [URL]) async -> InstallPlan {
        let instructions = findAndParseInstructions(in: directory)

        var classified = classifyFiles(files)

        // If instructions name a specific app to launch, promote it to managedInstall
        if let instr = instructions, let appHint = instr.appToLaunch {
            for i in classified.indices {
                if classified[i].type == .app {
                    let name = classified[i].url.deletingPathExtension()
                        .lastPathComponent.lowercased()
                    if name.contains(appHint.lowercased()) {
                        classified[i].type = .managedInstall
                        classified[i].note = "Instructions say to run this app"
                    }
                }
            }
        }

        let ordered = determineOrder(files: classified, instructions: instructions)

        var warnings: [String] = []
        if ordered.contains(where: { $0.type == .patch }) {
            warnings.append("Patch detected — will be applied after main installer.")
        }
        if ordered.contains(where: { $0.type == .managedInstall }) {
            warnings.append("Manager installer detected — ATLAS will launch and automate it.")
        }
        if let instr = instructions {
            if instr.mentionsRosetta {
                warnings.append("Instructions mention Rosetta — may be required on M1/M2 Macs.")
            }
            if instr.mentionsAdminRequired {
                warnings.append("Admin password required for this installation.")
            }
            if instr.mentionsSelectAll {
                warnings.append("Instructions say to select all products — ATLAS will automate this.")
            }
        }

        let installerCount = ordered.filter { $0.type == .installer      }.count
        let patchCount     = ordered.filter { $0.type == .patch          }.count
        let appCount       = ordered.filter { $0.type == .app            }.count
        let pluginCount    = ordered.filter { $0.type == .plugin         }.count
        let managerCount   = ordered.filter { $0.type == .managedInstall }.count

        var summaryParts: [String] = []
        if installerCount > 0 { summaryParts.append("\(installerCount) installer\(installerCount > 1 ? "s" : "")") }
        if appCount       > 0 { summaryParts.append("\(appCount) app\(appCount > 1 ? "s" : "")") }
        if pluginCount    > 0 { summaryParts.append("\(pluginCount) plugin\(pluginCount > 1 ? "s" : "")") }
        if managerCount   > 0 { summaryParts.append("\(managerCount) manager installer\(managerCount > 1 ? "s" : "")") }
        if patchCount     > 0 { summaryParts.append("\(patchCount) patch\(patchCount > 1 ? "es" : "")") }

        let summary = summaryParts.isEmpty
            ? "No installable content found"
            : "ATLAS will install: \(summaryParts.joined(separator: " → "))"

        return InstallPlan(instructions: instructions, orderedSteps: ordered,
                           warnings: warnings, summary: summary)
    }

    // MARK: - Instruction file detection

    // Scores a candidate instruction file. Returns -1 to disqualify.
    //
    // Rules:
    //  • Root-level files score highest (depth 0 = +100)
    //  • Files inside data/content/sample folders are disqualified
    //  • Strong instruction filenames (readme, nfo, "install guide") score higher
    //  • Files > 500KB are disqualified (real instructions are small)
    //  • Files deeper than 3 levels are disqualified
    private static func scoreInstruction(url: URL, rootDirectory: String) -> Int {
        let fm = FileManager.default
        let ext = url.pathExtension.lowercased()
        guard ["txt", "nfo", "rtf", "md", "htm", "html", "pdf"].contains(ext) else { return -1 }

        // Size check — instruction files are tiny
        if let size = (try? fm.attributesOfItem(atPath: url.path))?[.size] as? Int64,
           size > 500_000 { return -1 }

        // Compute relative path components
        let root = rootDirectory.hasSuffix("/") ? rootDirectory : rootDirectory + "/"
        let rel  = url.path.hasPrefix(root) ? String(url.path.dropFirst(root.count)) : url.path
        let components = rel.split(separator: "/").map(String.init)
        let depth = max(0, components.count - 1)

        // Hard depth limit
        if depth > 3 { return -1 }

        // Disqualify if any parent folder is a content/data folder
        let excludedFolders: Set<String> = [
            "data", "content", "samples", "presets", "resources", "library",
            "cache", "temp", "backup", "patches", "sounds", "media", "audio",
            "midi", "impulses", "wavetables", "reverbs", "instruments",
            "expansions", "licenses", "third_party", "redistributables",
            "documentation", "docs", "payload", "product", "extras",
            "bonus", "factory", "factory content", "factory presets", "ir"
        ]
        for component in components.dropLast() {
            if excludedFolders.contains(component.lowercased()) { return -1 }
        }

        // PDFs: detect presence but don't parse — just get a presence score
        if ext == "pdf" {
            let name = url.deletingPathExtension().lastPathComponent.lowercased()
            let pdScore = depth == 0 ? 50 : 20
            let hasKeyword = ["readme", "install", "guide", "manual", "instructions",
                              "how", "setup"].contains(where: { name.contains($0) })
            return hasKeyword ? pdScore + 20 : pdScore - 20
        }

        // Depth score
        let depthScore: Int
        switch depth {
        case 0:  depthScore = 100
        case 1:  depthScore = 55
        case 2:  depthScore = 15
        default: depthScore = 0
        }

        // Filename score
        let nameBase = url.deletingPathExtension().lastPathComponent.lowercased()
        var nameScore = 0

        // NFO files from scene releases often contain install steps, but structured
        // instruction files (HTML/TXT with "instruction" in name) should take priority.
        if ext == "nfo" { nameScore += 30 }

        let strong = ["readme", "read me", "read_me", "installation guide",
                      "install guide", "how to install", "howtoinstall",
                      "instructions", "installation instructions", "setup guide"]
        let moderate = ["install", "setup", "manual", "steps", "guide"]
        let weak     = ["note", "notes", "info", "read", "important"]

        if strong.contains(where: { nameBase == $0 || nameBase.contains($0) }) {
            nameScore += 80
        } else if moderate.contains(where: { nameBase.contains($0) }) {
            nameScore += 45
        } else if weak.contains(where: { nameBase.contains($0) }) {
            nameScore += 20
        }

        // Tiny penalty for very generic names at depth > 0
        if nameScore == 0 && depth > 0 { return -1 }

        return depthScore + nameScore
    }

    static func findAndParseInstructions(in directory: String) -> ParsedInstructions? {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(atPath: directory) else { return nil }

        var bestURL: URL? = nil
        var bestScore = -1
        var pdfCandidates: [URL] = []   // PDFs we know about but can't fully parse

        for case let path as String in enumerator {
            guard !path.hasPrefix(".__"), !path.contains("__MACOSX") else { continue }
            let url = URL(fileURLWithPath: directory).appendingPathComponent(path)
            guard !url.lastPathComponent.hasPrefix("._") else { continue }

            let ext = url.pathExtension.lowercased()

            // Track PDFs separately — mention in warnings but don't parse
            if ext == "pdf" {
                let score = scoreInstruction(url: url, rootDirectory: directory)
                if score > 0 { pdfCandidates.append(url) }
                continue
            }

            let score = scoreInstruction(url: url, rootDirectory: directory)
            if score > bestScore {
                bestScore = score
                bestURL = url
            }
        }

        // Require a minimum confidence to use the file
        guard bestScore >= 20, let fileURL = bestURL else {
            return nil
        }

        let text = readTextFile(fileURL)
        guard !text.isEmpty else { return nil }

        // Try to extract the English section from bilingual documents.
        // Many instruction files contain multiple languages — find the English portion.
        let englishText = extractEnglishSection(text) ?? text

        // Require at least 55% ASCII in the section we're going to parse
        let scalars = englishText.unicodeScalars
        if !scalars.isEmpty {
            let asciiRatio = Double(scalars.filter { $0.value < 128 }.count) / Double(scalars.count)
            if asciiRatio < 0.45 { return nil }
        }

        return parseInstructionText(englishText, fileURL: fileURL)
    }

    // Extracts the English-language section from a bilingual document.
    // Looks for common English section headers and returns the text that follows.
    private static func extractEnglishSection(_ text: String) -> String? {
        let englishHeaders = [
            "Installation Instruction",
            "Installation Instructions",
            "Install Instructions",
            "English Instructions",
            "Instructions (English)",
            "How to Install",
            "Installation Guide",
            "Setup Instructions",
            "INSTALLATION",
        ]
        let lines = text.components(separatedBy: .newlines)
        for (i, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            for header in englishHeaders {
                if trimmed.lowercased().contains(header.lowercased()) {
                    // Return everything from this line onward
                    let section = lines[i...].joined(separator: "\n")
                    // Only accept if there's meaningful content (> 200 chars)
                    if section.count > 200 { return section }
                }
            }
        }
        return nil
    }

    private static func readTextFile(_ url: URL) -> String {
        let ext = url.pathExtension.lowercased()

        if ext == "html" || ext == "htm" {
            if let raw = try? String(contentsOf: url, encoding: .utf8) {
                return raw.replacingOccurrences(of: "<[^>]+>", with: " ",
                                                options: .regularExpression)
            }
        }

        if ext == "rtf" {
            if let raw = try? String(contentsOf: url, encoding: .utf8) {
                return raw.replacingOccurrences(of: "\\\\[a-zA-Z]+\\d*\\s?", with: "",
                                                options: .regularExpression)
            }
        }

        // Plain text: .txt, .nfo, .md — try UTF-8 then Latin-1 (NFOs are often Latin-1)
        if let text = try? String(contentsOf: url, encoding: .utf8), !text.isEmpty {
            return text
        }
        return (try? String(contentsOf: url, encoding: .isoLatin1)) ?? ""
    }

    private static func parseInstructionText(
        _ text: String, fileURL: URL
    ) -> ParsedInstructions {
        let lower = text.lowercased()
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        // Extract numbered steps — English only
        var steps: [String] = []
        for line in lines {
            let isNumbered = line.first?.isNumber == true || line.lowercased().hasPrefix("step")
            guard isNumbered else { continue }
            let scalars = line.unicodeScalars
            let asciiRatio = scalars.isEmpty ? 1.0
                : Double(scalars.filter { $0.value < 128 }.count) / Double(scalars.count)
            guard asciiRatio >= 0.6 else { continue }
            // Skip very short lines that are just numbers
            guard line.count > 4 else { continue }
            steps.append(line)
        }

        let mentionsPatch = lower.contains("patch") || lower.contains("crack") ||
                            lower.contains("keygen") || lower.contains("license") ||
                            lower.contains("activat")

        let mentionsOrder = lower.contains("first") || lower.contains("then") ||
                            lower.contains("after") || lower.contains("before") ||
                            lower.contains("step 1") || lower.contains("1.")

        let mentionsRosetta  = lower.contains("rosetta") || lower.contains("intel") ||
                               lower.contains("x86")

        let mentionsAdmin    = lower.contains("admin") || lower.contains("sudo") ||
                               lower.contains("password") || lower.contains("administrator")

        let mentionsSelectAll = lower.contains("select all") || lower.contains("install all") ||
                                lower.contains("click all") || lower.contains("check all") ||
                                lower.contains("all plugins") || lower.contains("all products")

        // Detect manager app references
        let managerNames = ["waves central", "wavecentral", "ilok", "pace",
                            "native access", "ilocense", "activation manager",
                            "plugin manager", "license manager", "hub", "portal"]
        let mentionsManagerApp = managerNames.contains(where: { lower.contains($0) })

        // Detect specific app to launch from instruction text
        // Pattern: "open/run/launch/use [AppName]" — capture the app name
        let appToLaunch = detectAppToLaunch(in: lower)

        let noteKeywords = ["note:", "important:", "warning:", "caution:", "notice:", "tip:"]
        let customNotes = lines.filter { line in
            let l = line.lowercased()
            return noteKeywords.contains(where: { l.hasPrefix($0) }) || l.hasPrefix("!")
        }

        // TITAN CORE™: extract hosts entries from instruction text
        // Pattern: domain names near "block" keyword, or raw domain-like lines
        var hostsEntries: [String] = []
        let blockContext = extractBlockContext(from: lower, lines: lines)
        hostsEntries.append(contentsOf: blockContext)

        // TITAN CORE™: extract terminal commands (lines in code blocks or after "command:")
        let terminalCommands = extractTerminalCommands(from: text)

        // TITAN CORE™: detect xcode-select --install
        let mentionsXcodeTools = lower.contains("xcode-select") ||
                                 lower.contains("xcode command line") ||
                                 lower.contains("command line tools")

        // TITAN CORE™: detect specific files to run (scripts and binaries by name)
        let scriptsToRun  = extractFileMentions(kind: "script",  from: lower, lines: lines)
        let binariesToRun = extractFileMentions(kind: "binary",  from: lower, lines: lines)

        // Detect language of the section we're parsing
        let detectedLang  = lower.contains("установщик") || lower.contains("установите") ? "ru" : "en"

        return ParsedInstructions(
            rawText: text,
            sourceFileName: fileURL.lastPathComponent,
            steps: steps,
            mentionsPatch: mentionsPatch,
            mentionsOrder: mentionsOrder,
            mentionsRosetta: mentionsRosetta,
            mentionsAdminRequired: mentionsAdmin,
            customNotes: customNotes,
            appToLaunch: appToLaunch,
            mentionsSelectAll: mentionsSelectAll,
            mentionsManagerApp: mentionsManagerApp,
            hostsEntries: hostsEntries,
            terminalCommands: terminalCommands,
            mentionsXcodeTools: mentionsXcodeTools,
            scriptsToRun: scriptsToRun,
            binariesToRun: binariesToRun,
            detectedLanguage: detectedLang
        )
    }

    // Extracts domain names that instructions say to block.
    // Looks for domain-like strings near "block" / "hosts" trigger lines —
    // both backward (3 lines before) and forward (5 lines after).
    private static func extractBlockContext(from lower: String, lines: [String]) -> [String] {
        var domains: [String] = []
        let domainPattern = #"\b([a-z0-9\-]+(?:\.[a-z]{2,}){1,3})\b"#
        guard let regex = try? NSRegularExpression(pattern: domainPattern) else { return [] }

        // Triggers that indicate an upcoming or surrounding block list
        let triggers = ["block", "127.0.0.1", "hosts file", "/etc/hosts",
                        "add to hosts", "add the following to", "block the following",
                        "block these", "block addresses", "block the addresses"]

        // Build a set of line indices that are "in block context"
        var contextIndices = IndexSet()
        for (i, line) in lines.enumerated() {
            let ll = line.lowercased()
            guard triggers.contains(where: { ll.contains($0) }) else { continue }
            // The trigger line itself plus 5 lines after it and 3 before it
            let lo = max(0, i - 3)
            let hi = min(lines.count - 1, i + 5)
            contextIndices.insert(integersIn: lo...hi)
        }

        for i in contextIndices {
            let line = lines[i]
            let range = NSRange(line.startIndex..., in: line)
            for match in regex.matches(in: line, range: range) {
                guard let r = Range(match.range(at: 1), in: line) else { continue }
                let domain = String(line[r])
                let skip = ["little", "snitch", "lulu", "such", "tools", "using",
                            "the", "and", "or", "com", "net", "org"]
                let parts = domain.components(separatedBy: ".")
                guard parts.count >= 2, !skip.contains(parts[0]) else { continue }
                if domain.contains(".") && domain.count > 5 {
                    domains.append(domain)
                }
            }
        }
        return Array(Set(domains))
    }

    // Extracts shell commands mentioned in the instructions (in code blocks or after "command:")
    private static func extractTerminalCommands(from text: String) -> [String] {
        var commands: [String] = []
        // Look for xcode-select --install explicitly
        if text.contains("xcode-select --install") { commands.append("xcode-select --install") }
        // Generic: lines that look like terminal commands (start with $ or backtick-wrapped)
        let lines = text.components(separatedBy: .newlines)
        for line in lines {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("$ ") { commands.append(String(t.dropFirst(2))) }
        }
        return commands
    }

    // Extracts filenames mentioned in "Run the X file" patterns, preserving instruction order.
    //
    // The key pattern is: "Run the <name> file" where <name> can contain spaces.
    // We require "\s+file\b" as the terminator — NOT bare whitespace — so the lazy
    // quantifier expands fully to "block server" instead of stopping at "block".
    private static func extractFileMentions(kind: String, from lower: String, lines: [String]) -> [String] {
        var names: [String] = []
        var seen  = Set<String>()

        // "Run the <name> file" — the word "file" (word boundary) is the ONLY terminator.
        // This prevents the lazy quantifier from stopping at the first space inside the name
        // (e.g. "block server" would otherwise collapse to just "block").
        // \b after "file" also catches "file." and "file," so no separate period pattern needed.
        let pattern = #"run\s+the\s+([\w][\w\s\-\.]{1,40}?)\s+file\b"#

        let skip = Set(["installer", "the", "a", "an", "standard", "install",
                        "terminal", "command", "process", "setup"])

        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(lower.startIndex..., in: lower)
        for match in regex.matches(in: lower, range: range) {
            guard let r = Range(match.range(at: 1), in: lower) else { continue }
            // Collapse internal whitespace runs and trim edges
            let raw  = String(lower[r])
            let name = raw
                .trimmingCharacters(in: .whitespaces)
                .components(separatedBy: .whitespaces)
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            guard name.count > 3 && !skip.contains(name) else { continue }
            guard !name.hasSuffix(".pkg") && !name.hasSuffix(".app") &&
                  !name.hasSuffix(".dmg") && !name.hasSuffix(" file") else { continue }
            if seen.insert(name).inserted { names.append(name) }
        }
        return names
    }

    // MARK: - Instruction-guided file matching

    // Finds files in `directory` whose base names fuzzy-match any of the given name fragments.
    // Returns results in the same order as `names`, skipping names with no match.
    // Used by TitanMission.buildMission to locate instruction-mentioned files.
    static func findFilesByName(names: [String], in directory: String) -> [(name: String, url: URL)] {
        guard !names.isEmpty else { return [] }

        // Enumerate up to 3 levels deep, skipping known data folders
        let skipFolders: Set<String> = ["data", "samples", "presets", "resources",
                                         "library", "cache", "payload", "__macosx",
                                         "contents", "macos", "frameworks"]
        var allFiles: [URL] = []
        let fm = FileManager.default
        if let enumerator = fm.enumerator(
            at: URL(fileURLWithPath: directory),
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]) {
            for case let url as URL in enumerator {
                let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                let folderName = url.deletingLastPathComponent().lastPathComponent.lowercased()
                if isDir {
                    if skipFolders.contains(folderName) || skipFolders.contains(url.lastPathComponent.lowercased()) {
                        enumerator.skipDescendants()
                    }
                    continue
                }
                // Skip instruction/readme files
                let ext = url.pathExtension.lowercased()
                if ["html", "htm", "txt", "nfo", "rtf", "md", "pdf",
                    "png", "jpg", "icns", "webloc"].contains(ext) { continue }
                allFiles.append(url)
            }
        }

        var results: [(name: String, url: URL)] = []
        var usedPaths = Set<String>()

        for mentionedName in names {
            // Split into significant words (>2 chars) for fuzzy matching
            let fragments = mentionedName
                .components(separatedBy: .whitespaces)
                .filter { $0.count > 2 }
            guard !fragments.isEmpty else { continue }

            var best: (score: Int, url: URL)? = nil
            for fileURL in allFiles {
                guard !usedPaths.contains(fileURL.path) else { continue }
                let baseName = fileURL.deletingPathExtension().lastPathComponent.lowercased()

                // Count how many instruction fragments appear in the filename
                let hits = fragments.filter { baseName.contains($0) }.count
                guard hits > 0 else { continue }

                // Prefer shorter filenames (closer to exact match)
                let score = hits * 20 - baseName.count
                if best == nil || score > best!.score { best = (score, fileURL) }
            }

            if let match = best {
                results.append((name: mentionedName, url: match.url))
                usedPaths.insert(match.url.path)
            }
        }
        return results
    }

    // Extracts the name of an app the instructions tell the user to open/run.
    // Returns a lowercased key fragment (e.g. "waves central" → "wavescentral").
    private static func detectAppToLaunch(in lower: String) -> String? {
        // Look for "open/run/launch/use X" or "double-click X.app"
        let patterns = [
            #"(?:open|run|launch|start|use|execute)\s+([a-z][a-z0-9\s\-\_]{2,30}?)(?:\.app|\s|$)"#,
            #"([a-z][a-z0-9\s\-\_]{2,30}?)\.app"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(lower.startIndex..., in: lower)
            guard let match = regex.firstMatch(in: lower, range: range),
                  let captured = Range(match.range(at: 1), in: lower) else { continue }
            let name = String(lower[captured])
                .trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: " ", with: "")
            // Filter out common false positives
            let skipWords = Set(["the", "and", "then", "your", "this", "that",
                                 "all", "with", "for", "from", "after", "before",
                                 "click", "select", "choose", "follow", "read"])
            guard !skipWords.contains(name), name.count > 3 else { continue }
            return name
        }
        return nil
    }

    // MARK: - File classification

    private static func classifyFiles(
        _ files: [URL]
    ) -> [(url: URL, type: InstallStep.StepType, order: Int, note: String)] {
        var classified: [(url: URL, type: InstallStep.StepType, order: Int, note: String)] = []

        for url in files {
            let name    = url.lastPathComponent.lowercased()
            let ext     = url.pathExtension.lowercased()
            let leading = extractLeadingNumber(from: url.lastPathComponent)

            let type_: InstallStep.StepType
            var note = ""

            if isPatch(name: name) {
                type_ = .patch
                note = "Patch — applied after main installer"
            } else if ext == "pkg" || ext == "mpkg" {
                type_ = .installer
                note = "Package installer"
            } else if ["component", "vst3", "vst", "aaxplugin"].contains(ext) {
                type_ = .plugin
                note = "Audio plugin"
            } else if ext == "app" {
                if isManagerApp(url: url) {
                    type_ = .managedInstall
                    note = "Manager installer — ATLAS will launch and automate"
                } else {
                    type_ = .app
                    note = "Application"
                }
            } else {
                continue
            }

            classified.append((url: url, type: type_,
                               order: leading ?? 999, note: note))
        }

        return classified
    }

    // MARK: - Manager app detection

    // Returns true if this .app is a management/installation tool rather than
    // a regular application. These should be launched and automated, not just copied.
    static func isManagerApp(url: URL) -> Bool {
        let name = url.deletingPathExtension().lastPathComponent.lowercased()

        // Never classify patches as manager apps
        guard !isPatch(name: name) else { return false }

        let managerKeywords = [
            "central", "manager", "hub", "installer", "setup", "assistant",
            "activation", "license", "agent", "updater", "launcher",
            "configurator", "download", "portal", "auth", "install",
            "access", "control", "helper", "wizard"
        ]

        // Check name keywords
        if managerKeywords.contains(where: { name.contains($0) }) { return true }

        // Check bundle identifier
        let plist = url.appendingPathComponent("Contents/Info.plist")
        if let dict = NSDictionary(contentsOf: plist),
           let bid = (dict["CFBundleIdentifier"] as? String)?.lowercased() {
            if managerKeywords.contains(where: { bid.contains($0) }) { return true }
        }

        return false
    }

    // MARK: - Order determination

    private static func determineOrder(
        files: [(url: URL, type: InstallStep.StepType, order: Int, note: String)],
        instructions: ParsedInstructions?
    ) -> [InstallStep] {
        var sorted = files

        // If instructions provide numbered steps, try to match filenames to order
        if let instr = instructions, instr.mentionsOrder, !instr.steps.isEmpty {
            sorted = applyInstructionOrder(to: sorted, steps: instr.steps)
        }

        sorted.sort { a, b in
            // Explicit leading numbers win
            if a.order != 999 && b.order != 999 { return a.order < b.order }

            // Type priority: installers → plugins/apps → manager apps → patches
            let typePriority: (InstallStep.StepType) -> Int = { t in
                switch t {
                case .installer:      return 0
                case .app:            return 1
                case .plugin:         return 1
                case .managedInstall: return 2  // after PKGs, before patches
                case .patch:          return 3
                case .manual:         return 4
                }
            }
            let pa = typePriority(a.type), pb = typePriority(b.type)
            if pa != pb { return pa < pb }

            return a.url.lastPathComponent < b.url.lastPathComponent
        }

        return sorted.enumerated().map { index, item in
            InstallStep(url: item.url, type: item.type,
                       order: index + 1, note: item.note)
        }
    }

    // Tries to reorder files to match the instruction step sequence by
    // fuzzy-matching filenames against step text.
    private static func applyInstructionOrder(
        to files: [(url: URL, type: InstallStep.StepType, order: Int, note: String)],
        steps: [String]
    ) -> [(url: URL, type: InstallStep.StepType, order: Int, note: String)] {
        var result = files
        for (stepIdx, step) in steps.enumerated() {
            let stepLower = step.lowercased()
            for i in result.indices {
                let fname = result[i].url.deletingPathExtension()
                    .lastPathComponent.lowercased()
                // Fuzzy match: if the step text contains the filename (or vice versa)
                if stepLower.contains(fname) || fname.contains(stepLower.prefix(20)) {
                    result[i].order = stepIdx + 1
                }
            }
        }
        return result
    }

    // MARK: - Helpers

    static func isPatch(name: String) -> Bool {
        let keywords = ["patch", "crack", "keygen", "license", "activat",
                        "serial", "bypass", "fix", "loader", "unlocker",
                        "auth", "r2r", "vr", "team", "regged", "emulator",
                        "nocd", "nodvd", "nag"]
        return keywords.contains(where: { name.lowercased().contains($0) })
    }

    private static func extractLeadingNumber(from name: String) -> Int? {
        let pattern = #"^(\d+)[\.\s\-]"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: name,
                                           range: NSRange(name.startIndex..., in: name)),
              let range = Range(match.range(at: 1), in: name) else { return nil }
        return Int(name[range])
    }
}
