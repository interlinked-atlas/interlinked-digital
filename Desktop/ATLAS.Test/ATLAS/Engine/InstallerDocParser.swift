import Foundation

// MARK: - Data model

/// Structured information extracted from installer documentation files
/// (READMEs, instruction guides, license files, NFOs, etc.)
/// Surfaced to the user in the Activation Information panel after install.
struct InstallerDocInfo: Codable, Sendable {
    let sourceFiles: [String]          // filenames that were parsed (display only)
    let steps: [String]                // activation / installation steps, ordered
    let licenseKeys: [LicenseKey]      // serial numbers / license keys found
    let activationURLs: [String]       // URLs for activation portals / vendor sites
    let notes: [String]                // other notable text snippets

    struct LicenseKey: Codable, Hashable, Sendable {
        let label: String   // e.g. "License Key", "Serial Number"
        let value: String
    }

    var isEmpty: Bool {
        steps.isEmpty && licenseKeys.isEmpty && activationURLs.isEmpty && notes.isEmpty
    }

    /// True when the installer documentation contains something the user must
    /// manually act on after installation — an activation code to enter, or a
    /// URL to visit. Steps alone (e.g. "run the PKG") do not qualify, because
    /// those describe what ATLAS already handles automatically.
    var requiresUserAction: Bool {
        !licenseKeys.isEmpty || !activationURLs.isEmpty
    }
}

// MARK: - Internal language section model

private struct DocumentSection {
    let text: String         // stripped plain text of this section
    let isPreferred: Bool    // true when this section is in the user's preferred language
}

// MARK: - Parser engine

/// Generalized installer documentation parser.
/// Scans a mounted volume or extracted directory for README, instruction,
/// license, and serial files — extracts structured activation information
/// without any vendor-specific logic.
///
/// Language-aware: when a document contains sections in multiple languages
/// (separated by headings), ATLAS extracts steps only from the preferred
/// language section (English by default). License keys and URLs are always
/// extracted from all sections because they are language-agnostic.
struct InstallerDocParser {

    // MARK: - Language preference

    /// BCP-47 language tag for the language ATLAS should prefer.
    /// Currently always "en" — ATLAS ships English only.
    /// A future Settings preference can update this at runtime.
    static var preferredLanguage: String = "en"

    // MARK: - Data-driven configuration

    private static let docNameKeywords: [String] = [
        "readme", "read me", "read_me",
        "install", "installation",
        "instruction", "instructions",
        "guide", "manual",
        "activation", "activate",
        "license", "licence",
        "serial", "keygen", "key gen",
        "registration", "register",
        "how to", "how-to", "howto",
        "setup", "notes", "info",
        "important", "before you",
        "release", "patch", "crack",
    ]

    private static let docExtensions: Set<String> = [
        "txt", "nfo", "md", "html", "htm", "rtf",
    ]

    /// License / serial key patterns (label, regex capturing group 1).
    /// Order: more specific patterns first.
    private static let keyPatterns: [(String, String)] = [
        // 5-block hyphenated key (iLok-style)
        ("License Key",
         #"\b([A-Z0-9]{4,6}[-–][A-Z0-9]{4,6}[-–][A-Z0-9]{4,6}[-–][A-Z0-9]{4,6}[-–][A-Z0-9]{4,6})\b"#),
        // Standard 4-block hyphenated key (XXXX-XXXX-XXXX-XXXX)
        ("License Key",
         #"\b([A-Z0-9]{4,6}[-–][A-Z0-9]{4,6}[-–][A-Z0-9]{4,6}[-–][A-Z0-9]{4,6})\b"#),
        // 3-block hyphenated key
        ("License Key",
         #"\b([A-Z0-9]{5,8}[-–][A-Z0-9]{5,8}[-–][A-Z0-9]{5,8})\b"#),
        // Labeled key on same line: "Serial: XXXX", "Key=XXXXX"
        ("License",
         #"(?i)(?:serial|license|licence|reg(?:istration)?|key|code)[\s:=]+([A-Z0-9][A-Z0-9\-]{9,})"#),
        // Bare code: 14–32 uppercase-alphanumeric chars on their own line.
        // Post-validated to require both a letter and a digit.
        ("License Key",
         #"(?m)^([A-Z0-9]{14,32})$"#),
        // NFO-style: starts with 2+ letters, mixes letters and digits
        ("Registration Code",
         #"\b([A-Z]{2,}[0-9]{2,}[A-Z0-9]{10,26})\b"#),
    ]

    /// Phrases that introduce activation / installation steps.
    private static let activationSectionKeywords: [String] = [
        "installation instruction",
        "installation step",
        "install instruction",
        "how to install",
        "how to activate",
        "activation step",
        "activation instruction",
        "how to register",
        "registration step",
        "how to use",
        "to use this software",
        "getting started",
        "before you start",
        "for activation",
        "for registration",
        "listed below",
        "use one of",
        "license code",
        "license key",
        "activation code",
        "serial number",
        "registration code",
        "follow these",
        "follow the steps",
        "please follow",
        "instructions:",
        "steps:",
        "to install:",
        "to activate:",
        "to register:",
        "activation:",
    ]

    private static let stepPrefixPatterns: [String] = [
        #"^\s*\d{1,2}[\.\)\-:\s]\s+"#,
        #"^\s*[Ss]tep\s*\d+"#,
        #"^\s*[-•·*►▶]\s+"#,
    ]

    private static let noiseLinePatterns: [String] = [
        #"^[=\-\*\/#\|\.\+~]{5,}$"#,
        #"^[\s\W]{0,3}$"#,
    ]

    // MARK: - Public entry point

    static func scan(volumeURL: URL) -> InstallerDocInfo? {
        let docFiles = findDocFiles(in: volumeURL, maxDepth: 3)
        guard !docFiles.isEmpty else { return nil }

        var allSteps:    [String]                      = []
        var allKeys:     [InstallerDocInfo.LicenseKey] = []
        var allURLs:     [String]                      = []
        var allNotes:    [String]                      = []
        var sourceFiles: [String]                      = []
        var seenKeys  = Set<String>()
        var seenSteps = Set<String>()

        for fileURL in docFiles {
            guard let extracted = extractText(from: fileURL) else { continue }
            sourceFiles.append(fileURL.lastPathComponent)

            let parsed = parseContent(fullText: extracted.full, preferredText: extracted.preferred)

            for key in parsed.licenseKeys {
                let norm = key.value.uppercased().filter { !$0.isWhitespace }
                guard !seenKeys.contains(norm) else { continue }
                seenKeys.insert(norm)
                allKeys.append(key)
            }
            for step in parsed.steps {
                let norm = step.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard norm.count >= 8, !seenSteps.contains(norm) else { continue }
                seenSteps.insert(norm)
                allSteps.append(step.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            for url in parsed.activationURLs where !allURLs.contains(url) {
                allURLs.append(url)
            }
            for note in parsed.notes where !allNotes.contains(note) {
                allNotes.append(note)
            }
        }

        guard !allSteps.isEmpty || !allKeys.isEmpty || !allURLs.isEmpty else { return nil }

        return InstallerDocInfo(
            sourceFiles:    sourceFiles,
            steps:          Array(allSteps.prefix(20)),
            licenseKeys:    allKeys,
            activationURLs: Array(allURLs.prefix(5)),
            notes:          Array(allNotes.prefix(5))
        )
    }

    // MARK: - File detection

    private static func findDocFiles(in baseURL: URL, maxDepth: Int) -> [URL] {
        var found: [URL] = []
        let fm = FileManager.default
        let basePath = baseURL.path

        guard let enumerator = fm.enumerator(
            at: baseURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        for case let fileURL as URL in enumerator {
            let relative = fileURL.path.dropFirst(basePath.count)
            let depth = relative.components(separatedBy: "/").filter { !$0.isEmpty }.count
            if depth > maxDepth { enumerator.skipDescendants(); continue }

            guard (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true
            else { continue }

            let ext  = fileURL.pathExtension.lowercased()
            let name = fileURL.deletingPathExtension().lastPathComponent.lowercased()
            let full = fileURL.lastPathComponent.lowercased()

            guard docExtensions.contains(ext) else { continue }

            let matched = docNameKeywords.contains { name.contains($0) || full.contains($0) }
            if matched { found.append(fileURL) }
        }

        return Array(
            found.sorted {
                let d0 = $0.path.dropFirst(basePath.count).components(separatedBy: "/").count
                let d1 = $1.path.dropFirst(basePath.count).components(separatedBy: "/").count
                return d0 < d1
            }.prefix(8)
        )
    }

    // MARK: - Text extraction

    /// Returns `(full, preferred)`:
    /// - `full`      — all content (all languages), used for license key + URL extraction
    /// - `preferred` — preferred-language content only, used for step extraction
    ///
    /// When a document contains only one language, both values are identical.
    private static func extractText(from fileURL: URL) -> (full: String, preferred: String)? {
        guard let data = try? Data(contentsOf: fileURL),
              data.count < 512_000
        else { return nil }

        var raw = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .windowsCP1252)
                ?? String(data: data, encoding: .isoLatin1)
                ?? ""
        guard !raw.isEmpty else { return nil }

        switch fileURL.pathExtension.lowercased() {
        case "html", "htm":
            return languageSplit(htmlSections: splitHTMLIntoLanguageSections(raw))
        case "rtf":
            let text = stripRTF(raw)
            guard !text.isEmpty else { return nil }
            return (full: text, preferred: text)
        default:
            return languageSplit(textSections: splitPlainTextIntoLanguageSections(raw))
        }
    }

    /// Combines sections into (full, preferred) pair.
    private static func languageSplit(htmlSections sections: [DocumentSection]) -> (full: String, preferred: String)? {
        let full = sections.map(\.text).joined(separator: "\n\n")
        guard !full.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let preferred = sections.filter(\.isPreferred).map(\.text).joined(separator: "\n\n")
        return (full: full, preferred: preferred.isEmpty ? full : preferred)
    }

    private static func languageSplit(textSections sections: [DocumentSection]) -> (full: String, preferred: String)? {
        let full = sections.map(\.text).joined(separator: "\n\n")
        guard !full.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let preferred = sections.filter(\.isPreferred).map(\.text).joined(separator: "\n\n")
        return (full: full, preferred: preferred.isEmpty ? full : preferred)
    }

    // MARK: - HTML language-section splitting

    /// Splits an HTML document into per-section chunks at h2/h3/h4 heading boundaries,
    /// then classifies each chunk by language.
    ///
    /// This handles the common pattern where installer docs ship multilingual versions
    /// under separate headings (e.g. Russian h3 → Russian content, then English h3 →
    /// English content). Each chunk is classified independently so the caller can
    /// filter to the preferred language before extracting steps.
    private static func splitHTMLIntoLanguageSections(_ html: String) -> [DocumentSection] {
        guard let headingRegex = try? NSRegularExpression(pattern: #"(?i)<h[2-4][^>]*>"#)
        else { return [DocumentSection(text: stripHTML(html), isPreferred: true)] }

        let allMatches = headingRegex.matches(in: html, range: NSRange(html.startIndex..., in: html))
        guard !allMatches.isEmpty else {
            return [DocumentSection(text: stripHTML(html), isPreferred: true)]
        }

        let boundaries: [String.Index] = allMatches.compactMap {
            Range($0.range, in: html)?.lowerBound
        }

        // Build raw HTML chunks: one preamble + one per heading
        var rawChunks: [String] = []
        let preamble = String(html[html.startIndex ..< boundaries[0]])
        if !preamble.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            rawChunks.append(preamble)
        }
        for (i, start) in boundaries.enumerated() {
            let end = i + 1 < boundaries.count ? boundaries[i + 1] : html.endIndex
            rawChunks.append(String(html[start ..< end]))
        }

        var sections = rawChunks.compactMap { chunk -> DocumentSection? in
            let text = stripHTML(chunk)
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return DocumentSection(text: text, isPreferred: isPreferredLanguage(text))
        }

        // If no section matched the preferred language, fall back: treat all as preferred
        if !sections.contains(where: \.isPreferred) {
            sections = sections.map { DocumentSection(text: $0.text, isPreferred: true) }
        }
        return sections
    }

    /// Splits plain text into language sections separated by 3+ blank lines or dividers.
    private static func splitPlainTextIntoLanguageSections(_ text: String) -> [DocumentSection] {
        guard let sepRegex = try? NSRegularExpression(
            pattern: #"\n{3,}|^[-=]{10,}\s*$"#, options: .anchorsMatchLines)
        else { return [DocumentSection(text: text, isPreferred: true)] }

        var chunks: [String] = []
        var lastEnd = text.startIndex
        for m in sepRegex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let r = Range(m.range, in: text) else { continue }
            let chunk = String(text[lastEnd ..< r.lowerBound])
            if !chunk.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                chunks.append(chunk)
            }
            lastEnd = r.upperBound
        }
        let tail = String(text[lastEnd...])
        if !tail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { chunks.append(tail) }

        guard !chunks.isEmpty else { return [DocumentSection(text: text, isPreferred: true)] }

        var sections = chunks.map { chunk -> DocumentSection in
            DocumentSection(text: chunk, isPreferred: isPreferredLanguage(chunk))
        }
        if !sections.contains(where: \.isPreferred) {
            sections = sections.map { DocumentSection(text: $0.text, isPreferred: true) }
        }
        return sections
    }

    // MARK: - Language classification

    /// Returns true if `text` is in the user's preferred language.
    ///
    /// For `preferredLanguage == "en"` (current only value): English / Latin-script text
    /// is identified by ASCII alphabetic characters dominating (>60%) over clearly
    /// non-Latin script characters (Cyrillic, CJK, Arabic, Hebrew, Thai, Devanagari…).
    ///
    /// Sections with fewer than 15 identifiable alphabetic chars are too short to
    /// classify reliably, so they are treated as preferred (neutral / boilerplate).
    private static func isPreferredLanguage(_ text: String) -> Bool {
        var asciiAlpha    = 0
        var nonLatinAlpha = 0

        for scalar in text.unicodeScalars {
            let v = scalar.value
            if (v >= 65 && v <= 90) || (v >= 97 && v <= 122) {
                asciiAlpha += 1
            } else if v > 127 {
                switch v {
                case 0x0400...0x04FF: nonLatinAlpha += 1  // Cyrillic
                case 0x4E00...0x9FFF: nonLatinAlpha += 1  // CJK Unified Ideographs
                case 0x3040...0x30FF: nonLatinAlpha += 1  // Hiragana / Katakana
                case 0xF900...0xFAFF: nonLatinAlpha += 1  // CJK Compatibility
                case 0x0600...0x06FF: nonLatinAlpha += 1  // Arabic
                case 0x0590...0x05FF: nonLatinAlpha += 1  // Hebrew
                case 0x0E00...0x0E7F: nonLatinAlpha += 1  // Thai
                case 0x0900...0x097F: nonLatinAlpha += 1  // Devanagari
                case 0x0C00...0x0C7F: nonLatinAlpha += 1  // Telugu
                case 0x0B80...0x0BFF: nonLatinAlpha += 1  // Tamil
                default: break
                }
            }
        }

        let total = asciiAlpha + nonLatinAlpha
        guard total >= 15 else { return true }  // too short → treat as preferred
        return Double(asciiAlpha) / Double(total) > 0.60
    }

    // MARK: - HTML stripping

    /// Convert HTML to plain text while preserving structure critical for parsing.
    private static func stripHTML(_ html: String) -> String {
        var s = html

        // Remove <script> and <style> blocks entirely
        for tag in ["script", "style"] {
            s = s.replacingOccurrences(
                of: "(?i)<\(tag)[^>]*>[\\s\\S]*?</\(tag)>",
                with: " ", options: .regularExpression)
        }

        // List items: opening <li> → bullet prefix so list items keep their list nature
        s = s.replacingOccurrences(
            of: #"(?i)<li[^>]*>"#,
            with: "\n• ", options: .regularExpression)

        // Block-level separators → newlines
        s = s.replacingOccurrences(
            of: #"(?i)</(p|div|li|tr|h[1-6]|blockquote)>"#,
            with: "\n", options: .regularExpression)
        s = s.replacingOccurrences(
            of: #"(?i)<(blockquote|/blockquote|hr)[^>]*>"#,
            with: "\n", options: .regularExpression)
        s = s.replacingOccurrences(
            of: #"(?i)<br\s*/?>"#,
            with: "\n", options: .regularExpression)

        // Strip all remaining tags
        s = s.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)

        // Decode common HTML entities
        let entities: [(String, String)] = [
            ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
            ("&nbsp;", " "), ("&#39;", "'"), ("&quot;", "\""),
            ("&mdash;", "—"), ("&ndash;", "–"),
        ]
        for (entity, char) in entities {
            s = s.replacingOccurrences(of: entity, with: char)
        }

        // Collapse runs of 3+ consecutive blank lines to 2 to prevent over-eager section resets
        s = s.replacingOccurrences(
            of: #"(\n\s*){3,}"#,
            with: "\n\n", options: .regularExpression)

        return s
    }

    private static func stripRTF(_ rtf: String) -> String {
        var s = rtf
        s = s.replacingOccurrences(of: #"\\[a-z]+[-]?\d*[ ]?"#, with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\{|\}"#, with: "", options: .regularExpression)
        return s
    }

    // MARK: - Content parsing

    private struct ParsedContent {
        var steps:          [String]                      = []
        var licenseKeys:    [InstallerDocInfo.LicenseKey] = []
        var activationURLs: [String]                      = []
        var notes:          [String]                      = []
    }

    private static func parseContent(fullText: String, preferredText: String) -> ParsedContent {
        var result = ParsedContent()

        // URLs — language-agnostic, scan full text
        if let urlRegex = try? NSRegularExpression(pattern: #"https?://[^\s<>"'\]\[){,]{8,}"#) {
            for m in urlRegex.matches(in: fullText, range: NSRange(fullText.startIndex..., in: fullText)) {
                if let r = Range(m.range, in: fullText) {
                    var url = String(fullText[r])
                    while let last = url.last, ".,;:)\"'".contains(last) { url.removeLast() }
                    if !result.activationURLs.contains(url) { result.activationURLs.append(url) }
                }
            }
        }

        // License keys — language-agnostic (same keys appear in every language block)
        for (label, pattern) in keyPatterns {
            let opts: NSRegularExpression.Options = pattern.hasPrefix("(?m)")
                ? [.caseInsensitive, .anchorsMatchLines]
                : [.caseInsensitive]
            guard let regex = try? NSRegularExpression(pattern: pattern, options: opts) else { continue }
            for m in regex.matches(in: fullText, range: NSRange(fullText.startIndex..., in: fullText)) {
                let captureRange = m.numberOfRanges > 1 ? m.range(at: 1) : m.range
                guard let r = Range(captureRange, in: fullText) else { continue }
                let value = String(fullText[r]).trimmingCharacters(in: .whitespaces)
                guard isPlausibleKey(value) else { continue }
                result.licenseKeys.append(InstallerDocInfo.LicenseKey(label: label, value: value))
            }
        }

        // Steps — extracted from preferred-language text only
        let keyValues = Set(result.licenseKeys.map(\.value))
        result.steps = extractSteps(from: preferredText, excludingKeys: keyValues)

        return result
    }

    // MARK: - Key validation

    private static func isPlausibleKey(_ s: String) -> Bool {
        guard s.count >= 8 else { return false }
        guard !isVersionNumber(s) else { return false }
        guard !isFilePath(s) else { return false }

        // Bare codes (no hyphens, 14+ chars): must contain both a letter and a digit
        let stripped = s.filter { $0 != "-" && $0 != "–" }
        if stripped.count >= 14 && !s.contains("-") && !s.contains("–") {
            return stripped.contains(where: \.isLetter) && stripped.contains(where: \.isNumber)
        }
        return true
    }

    // MARK: - Automated-step filter

    // Phrases indicating a step that ATLAS executes automatically — the user
    // does not need to act on it after installation. Steps matching these are
    // removed from the activation dialog unless they also contain a manual-
    // action signal (e.g. the user is asked to type a code in that same step).
    private static let automatedInstallerPhrases: [String] = [
        "run the installer",
        "run the pkg",
        "run the mpkg",
        "double-click the installer",
        "double click the installer",
        "perform a standard install",
        "perform the installation",
        "standard installation",
        "drag to your application",
        "drag it to application",
        "drag to the application",
        "drag and drop",
        "mount the disk image",
        "open the dmg",
        "extract the archive",
        "follow the on-screen",
        "follow on-screen",
        "click next",
        "click finish",
        "click install",
        "press next",
        "press finish",
        "proceed through the installer",
        "install normally",
        "install the pkg",
        "install the application",
        "launch the copy license",
        "run copy license",
        "copy license",             // e.g. "Launch the Copy License file"
        "license installer",
        "license file",             // "the license file will be installed"
        "the terminal app will open",
        "terminal app will open",
        "reboot your",
        "restart your computer",
        "restart your mac",
    ]

    // Phrases that indicate the user must take a manual step.
    // These override the automated filter — the step is always kept.
    private static let manualActionPhrases: [String] = [
        "enter your",
        "enter the",
        "type your",
        "type the",
        "paste your",
        "paste the",
        "serial number",
        "serial:",
        "activation code",
        "registration key",
        "license key",
        "licence key",
        "challenge code",
        "response code",
        "go to preferences",
        "open preferences",
        "navigate to",
        "authorize your",
        "register your",
    ]

    /// Returns true when a step describes something ATLAS handles automatically
    /// and the user does not need to act on it.
    private static func isAutomatedInstallerStep(_ step: String) -> Bool {
        let lower = step.lowercased()
        // Manual-action signals take priority — keep the step
        for phrase in manualActionPhrases where lower.contains(phrase) { return false }
        // Automated-only phrases — discard the step
        for phrase in automatedInstallerPhrases where lower.contains(phrase) { return true }
        return false
    }

    // MARK: - Step extraction

    private static func extractSteps(from text: String, excludingKeys keyValues: Set<String>) -> [String] {
        let lines = text.components(separatedBy: .newlines)
        var steps: [String]  = []
        var inSection        = false
        var blankCount       = 0
        var stepsSinceHeader = 0

        for rawLine in lines {
            let line  = rawLine.trimmingCharacters(in: .whitespaces)
            let lower = line.lowercased()

            if line.isEmpty {
                blankCount += 1
                // Require 4 consecutive blank lines to end a section — HTML-derived
                // text often has 2–3 blank lines between adjacent list items.
                if blankCount >= 4 && stepsSinceHeader > 0 {
                    inSection        = false
                    stepsSinceHeader = 0
                }
                continue
            }
            blankCount = 0

            // Skip lines already captured as license keys
            if keyValues.contains(line) { continue }

            // Detect section-header lines
            if activationSectionKeywords.contains(where: { lower.contains($0) }) {
                inSection        = true
                stepsSinceHeader = 0
                continue
            }

            let isNumbered = stepPrefixPatterns.contains { pat in
                (try? NSRegularExpression(pattern: pat, options: .caseInsensitive))?
                    .firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil
            }

            if isNumbered || inSection {
                guard line.count >= 8, !isNoiseLine(line) else { continue }

                if isNumbered {
                    let stripped = stripStepPrefix(line)
                    guard !keyValues.contains(stripped) else { continue }
                    steps.append(stripped.count >= 6 ? stripped : line)
                    stepsSinceHeader += 1
                    inSection = true
                } else {
                    steps.append(line)
                    stepsSinceHeader += 1
                }

                if steps.count >= 18 { break }
            }
        }
        // Remove steps that describe automated installer actions the user doesn't need to act on
        return steps.filter { !isAutomatedInstallerStep($0) }
    }

    private static func stripStepPrefix(_ line: String) -> String {
        for pattern in stepPrefixPatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                  let m = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                  let r = Range(m.range, in: line) else { continue }
            return String(line[r.upperBound...]).trimmingCharacters(in: .whitespaces)
        }
        return line
    }

    private static func isNoiseLine(_ line: String) -> Bool {
        for pattern in noiseLinePatterns {
            if (try? NSRegularExpression(pattern: pattern))?
                .firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil {
                return true
            }
        }
        return line.filter({ $0.isLetter || $0.isNumber }).count < 3
    }

    // MARK: - False-positive filters

    private static func isVersionNumber(_ s: String) -> Bool {
        let parts = s.components(separatedBy: CharacterSet(charactersIn: ".-"))
        return parts.count >= 2 && parts.allSatisfy { $0.allSatisfy(\.isNumber) && !$0.isEmpty }
    }

    private static func isFilePath(_ s: String) -> Bool {
        s.hasPrefix("/") || s.hasPrefix("./") || s.contains(".app") || s.contains(".pkg")
    }
}
