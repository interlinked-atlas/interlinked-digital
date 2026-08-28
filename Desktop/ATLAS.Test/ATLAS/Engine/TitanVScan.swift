import Foundation
import CryptoKit

private final class Box<T> { var value: T; init(_ v: T) { value = v } }

// MARK: - Threat Types

enum ThreatType: String, Codable, CaseIterable {
    case informationStealer   = "Information Stealer"
    case rat                  = "Remote Access Trojan"
    case cryptoMiner          = "Cryptocurrency Miner"
    case ransomware           = "Ransomware"
    case backdoor             = "Backdoor"
    case downloader           = "Downloader / Loader"
    case spyware              = "Spyware"
    case adware               = "Adware"
    case clipboardHijacker    = "Clipboard Hijacker"
    case persistence          = "Persistence Mechanism"
    case maliciousScript      = "Malicious Script"
    case browserCredTheft     = "Browser Credential Theft"
    case cryptoWalletTheft    = "Crypto Wallet Theft"
    case keylogger            = "Keylogger"
    case rootkit              = "Rootkit"

    var icon: String {
        switch self {
        case .informationStealer:  return "person.crop.circle.badge.minus"
        case .rat:                 return "desktopcomputer.trianglebadge.exclamationmark"
        case .cryptoMiner:         return "cpu.fill"
        case .ransomware:          return "lock.fill"
        case .backdoor:            return "door.left.hand.open"
        case .downloader:          return "arrow.down.circle.fill"
        case .spyware:             return "eye.fill"
        case .adware:              return "megaphone.fill"
        case .clipboardHijacker:   return "doc.on.clipboard.fill"
        case .persistence:         return "arrow.clockwise.circle.fill"
        case .maliciousScript:     return "terminal.fill"
        case .browserCredTheft:    return "globe.badge.chevron.backward"
        case .cryptoWalletTheft:   return "bitcoinsign.circle.fill"
        case .keylogger:           return "keyboard.fill"
        case .rootkit:             return "ant.fill"
        }
    }

    var color: String {
        switch self {
        case .ransomware, .rat, .rootkit, .backdoor:         return "#EF5B5B"
        case .informationStealer, .browserCredTheft,
             .cryptoWalletTheft, .keylogger, .spyware:       return "#FF7A5C"
        case .cryptoMiner, .downloader, .persistence,
             .maliciousScript:                               return "#F0A030"
        case .adware, .clipboardHijacker:                    return "#F0C030"
        }
    }
}

// MARK: - Threat Detail

struct ThreatDetail: Identifiable {
    let id = UUID()
    let type: ThreatType
    let name: String          // e.g. "Atomic Stealer", "XMRig", "LaunchDaemon dropper"
    let affectedFile: String  // filename where it was found
    let detail: String        // human-readable explanation
    let canStrip: Bool        // true = can remove this without breaking the install
}

// MARK: - VScan Verdict

enum VScanVerdict: String, Codable {
    case clean           // no threats
    case licenseTool     // keygen/patch only, no extra malware
    case suspicious      // unusual patterns, user decides
    case bundledThreat   // real software + extra malware (can strip components)
    case malware         // no legitimate software — entire file is malicious

    var label: String {
        switch self {
        case .clean:         return "Clean"
        case .licenseTool:   return "License Tool"
        case .suspicious:    return "Suspicious"
        case .bundledThreat: return "Threat Detected"
        case .malware:       return "Malware"
        }
    }

    var isBlocking: Bool  { self == .malware }
    var isWarning: Bool   { self == .suspicious || self == .bundledThreat }
    var isClear: Bool     { self == .clean || self == .licenseTool }
}

// MARK: - VScan Result

struct VScanResult {
    let verdict: VScanVerdict
    let threats: [ThreatDetail]
    let scannedFile: String
    let hash: String
    let strippableThreats: [ThreatDetail]  // threats that can be removed before install
    let blockingThreats: [ThreatDetail]    // threats embedded in core — cannot strip

    var canStripAndInstall: Bool {
        !strippableThreats.isEmpty && blockingThreats.isEmpty
    }

    var primaryThreatName: String {
        threats.first?.name ?? "Unknown threat"
    }

    var summaryLine: String {
        switch verdict {
        case .clean:         return "No threats detected by TITAN VSCAN™"
        case .licenseTool:   return "License tool detected — no additional malware found"
        case .suspicious:    return "\(threats.count) suspicious pattern\(threats.count == 1 ? "" : "s") detected"
        case .bundledThreat:
            let names = Array(Set(threats.map(\.name))).prefix(2).joined(separator: ", ")
            return "\(threats.count) threat\(threats.count == 1 ? "" : "s") found: \(names)"
        case .malware:
            let names = Array(Set(threats.map(\.name))).prefix(2).joined(separator: ", ")
            return "Malware detected: \(names)"
        }
    }
}

// MARK: - Engine

@MainActor
final class TitanVScan: ObservableObject {
    static let shared = TitanVScan()

    @Published var isScanning = false
    @Published var scanPhase  = ""
    @Published var lastResult: VScanResult? = nil

    private init() {}

    // MARK: - Public

    func scan(url: URL) async -> VScanResult? {
        guard Features.isPro else { return nil }

        isScanning = true
        lastResult = nil
        defer { isScanning = false }

        let fileName  = url.lastPathComponent
        let ext       = url.pathExtension.lowercased()

        scanPhase = "Analyzing…"

        // Run all heavy work off the main actor in one detached task
        typealias ScanOut = (hash: String, threats: [ThreatDetail])
        let capturedURL = url
        let capturedExt = ext
        let out: ScanOut = await Task.detached(priority: .utility) {
            let h = titanVScanSHA256(capturedURL) ?? ""
            var t: [ThreatDetail] = []
            if capturedExt == "pkg" || capturedExt == "mpkg" {
                t.append(contentsOf: titanVScanPKGScripts(capturedURL))
            }
            t.append(contentsOf: titanVScanBinaryStrings(capturedURL))
            return (h, t)
        }.value

        scanPhase = ""

        // ── Deduplicate ───────────────────────────────────────────────────────
        var seen = Set<String>()
        let uniqueThreats = out.threats.filter {
            seen.insert("\($0.type.rawValue)|\($0.name)").inserted
        }

        // ── Verdict ───────────────────────────────────────────────────────────
        // Only the eight defined threat categories can produce a non-clean verdict.
        // Modified, patched, cracked, or unusual software is not a detection criterion.
        let verdict: VScanVerdict
        if uniqueThreats.isEmpty {
            verdict = .clean
        } else {
            let blockingTypes: Set<ThreatType> = [
                .informationStealer, .rat, .cryptoMiner, .ransomware,
                .backdoor, .downloader, .browserCredTheft, .cryptoWalletTheft,
                .keylogger, .rootkit, .spyware
            ]
            let hasBlocking = uniqueThreats.contains { blockingTypes.contains($0.type) }
            verdict = hasBlocking ? .malware : .suspicious
        }

        let result = VScanResult(
            verdict: verdict,
            threats: uniqueThreats,
            scannedFile: fileName,
            hash: out.hash,
            strippableThreats: uniqueThreats.filter(\.canStrip),
            blockingThreats: uniqueThreats.filter { !$0.canStrip }
        )
        lastResult = result
        return result
    }

}

// MARK: - Free scanning functions (called from detached tasks)

private func titanVScanPKGScripts(_ url: URL) -> [ThreatDetail] {
        let fm = FileManager.default
        let tmpDir = fm.temporaryDirectory
            .appendingPathComponent("ATLAS_VSCAN_\(UUID().uuidString.prefix(8))")
        defer { try? fm.removeItem(at: tmpDir) }

        let expand = titanVScanProcess("/usr/sbin/pkgutil",
                                args: ["--expand", url.path, tmpDir.path], timeout: 20)
        guard expand.ok else { return [] }

        let scriptsDir = tmpDir.appendingPathComponent("Scripts")
        guard let scripts = try? fm.contentsOfDirectory(atPath: scriptsDir.path) else { return [] }

        var threats: [ThreatDetail] = []

        for script in scripts {
            let scriptPath = scriptsDir.appendingPathComponent(script)
            guard let content = try? String(contentsOf: scriptPath, encoding: .utf8) else { continue }
            let lower = content.lowercased()
            let fileName = "PKG Scripts/\(script)"

            // curl/wget pipe to shell — classic dropper pattern
            if lower.contains("curl") && (lower.contains("| bash") || lower.contains("| sh") || lower.contains("|bash") || lower.contains("|sh")) {
                threats.append(ThreatDetail(
                    type: .downloader,
                    name: "Script downloader",
                    affectedFile: fileName,
                    detail: "Postinstall script downloads and executes code from the internet (curl | bash). This is the most common delivery mechanism for macOS malware.",
                    canStrip: true
                ))
            }
            if lower.contains("wget") && (lower.contains("| bash") || lower.contains("| sh")) {
                threats.append(ThreatDetail(
                    type: .downloader,
                    name: "Script downloader",
                    affectedFile: fileName,
                    detail: "Postinstall script uses wget to download and execute remote code.",
                    canStrip: true
                ))
            }

            // Hidden binary drop — chmod +x combined with a specifically hidden/suspicious temp path
            if lower.contains("chmod +x") && (lower.contains("/tmp/.") || lower.contains("/library/caches/.")) {
                threats.append(ThreatDetail(
                    type: .downloader,
                    name: "Hidden binary dropper",
                    affectedFile: fileName,
                    detail: "Script drops and executes a hidden executable in a non-standard location — a strong indicator of malware delivery.",
                    canStrip: true
                ))
            }

            // Keychain access
            if lower.contains("security find-generic-password") || lower.contains("security find-internet-password") {
                threats.append(ThreatDetail(
                    type: .informationStealer,
                    name: "Keychain credential theft",
                    affectedFile: fileName,
                    detail: "Script accesses macOS Keychain to steal saved passwords and credentials.",
                    canStrip: true
                ))
            }
        }

        return threats
    }

private func titanVScanBinaryStrings(_ url: URL) -> [ThreatDetail] {
        // Collect binary targets to scan
        var targets: [URL] = []
        let fm = FileManager.default
        let ext = url.pathExtension.lowercased()

        if ext == "app" {
            if let macOS = try? fm.contentsOfDirectory(
                at: url.appendingPathComponent("Contents/MacOS"),
                includingPropertiesForKeys: nil) {
                targets = macOS
            }
        } else if ext == "dmg" || ext == "iso" {
            // Already unmounted — scan the disk image itself
            targets = [url]
        } else {
            targets = [url]
        }

        var threats: [ThreatDetail] = []

        for target in targets.prefix(3) {
            let strResult = titanVScanProcess("/usr/bin/strings", args: ["-a", target.path], timeout: 15)
            guard strResult.ok else { continue }
            let strings = strResult.output
            let lower = strings.lowercased()
            let fileName = target.lastPathComponent

            // ── Browser credential theft (Category 1) ────────────────────────
            // These are highly specific internal browser data store paths with no
            // legitimate use inside an audio plugin or installer binary.
            let browserPaths = [
                "chrome/default/login data",
                "chrome/default/cookies",
                "firefox/profiles",
                "safari/cookies.binarycookies",
                "safari/history.db",
                "browser/default/login data"
            ]
            if browserPaths.contains(where: { lower.contains($0) }) {
                threats.append(ThreatDetail(
                    type: .browserCredTheft,
                    name: "Browser credential harvester",
                    affectedFile: fileName,
                    detail: "Binary contains paths to browser password and cookie stores (Chrome, Firefox, Safari). This is a hallmark of information stealers like Atomic Stealer, Banshee, and Poseidon.",
                    canStrip: false
                ))
            }

            // ── Crypto wallet theft (Category 1) ─────────────────────────────
            // Path-specific wallet references unlikely to appear in audio software.
            // Removed bare "exodus" and "phantom" — too generic for audio context
            // ("phantom" is a common audio/recording term; "exodus" matches product names).
            let walletPaths = [
                ".bitcoin/wallet.dat", "electrum/wallets",
                "metamask", "coinbase wallet",
                "application support/exodus",
                "atomic wallet", "trust wallet"
            ]
            if walletPaths.contains(where: { lower.contains($0) }) {
                threats.append(ThreatDetail(
                    type: .cryptoWalletTheft,
                    name: "Crypto wallet harvester",
                    affectedFile: fileName,
                    detail: "Binary targets cryptocurrency wallet files (Bitcoin, Electrum, MetaMask, Exodus). Characteristic of macOS stealers.",
                    canStrip: false
                ))
            }

            // ── Account token theft (Category 1) ─────────────────────────────
            // Application-internal storage paths; zero legitimate use in audio software.
            let accountPaths = [
                "discord/local storage", "discord/leveldb",
                "steam/config/loginusers",
                "telegram desktop"
            ]
            if accountPaths.contains(where: { lower.contains($0) }) {
                threats.append(ThreatDetail(
                    type: .informationStealer,
                    name: "Account token stealer",
                    affectedFile: fileName,
                    detail: "Binary targets Discord, Steam, or Telegram session tokens to hijack accounts.",
                    canStrip: false
                ))
            }

            // ── Cryptocurrency miner (Category 5) ────────────────────────────
            // Anchor strings: full protocol URIs and complete mining-pool domain names.
            // These are specific enough that a single match is meaningful evidence —
            // they cannot appear coincidentally in any legitimate software.
            let anchorMinerStrings = [
                "stratum+tcp://",   // Stratum mining protocol — the definitive mining indicator
                "pool.minexmr.com", "moneroocean",
                "supportxmr.com",   "hashvault.pro",
                "pool.hashvault",   "c3pool.com"
            ]
            // Corroborating strings: mining-related but short enough to appear as
            // incidental substrings inside large binaries (e.g. "xmrig" inside
            // "xMrIgp", or "minexmr" inside longer identifiers). A single match is
            // not sufficient; two or more together constitute meaningful evidence.
            let corroboratingMinerStrings = ["xmrig", "minexmr"]

            let hasAnchor = anchorMinerStrings.contains(where: { lower.contains($0) })
            let corroboratingCount = corroboratingMinerStrings.filter { lower.contains($0) }.count
            if hasAnchor || corroboratingCount >= 2 {
                threats.append(ThreatDetail(
                    type: .cryptoMiner,
                    name: "XMRig / Monero miner",
                    affectedFile: fileName,
                    detail: "Binary contains mining pool addresses or protocol strings. This is a cryptocurrency miner that will use your CPU/GPU without consent.",
                    canStrip: false
                ))
            }

            // ── C2 / RAT indicators (Category 4) ─────────────────────────────
            // Specific RAT framework names; zero legitimate use in audio software.
            let ratStrings = [
                "asyncrat", "quasarrat", "njrat", "darkcomet",
                "remcos", "nanocore", "connectback",
                "reverse_shell", "reverseshell"
            ]
            if ratStrings.contains(where: { lower.contains($0) }) {
                threats.append(ThreatDetail(
                    type: .rat,
                    name: "Remote Access Trojan",
                    affectedFile: fileName,
                    detail: "Binary contains strings associated with known RAT frameworks. This would give an attacker remote control of your computer.",
                    canStrip: false
                ))
            }

            // ── Known macOS malware family signatures ─────────────────────────
            // Removed "realst" (6-char substring, false-positive risk as part of other words)
            // and "adload" (can match ad/analytics SDK strings in legitimate plugins).
            let macMalwareStrings: [(String, String, ThreatType)] = [
                ("atomicstealer",       "Atomic Stealer",   .informationStealer),
                ("atomic stealer",      "Atomic Stealer",   .informationStealer),
                ("bansheestealer",      "Banshee Stealer",  .informationStealer),
                ("poseidon stealer",    "Poseidon",         .informationStealer),
                ("evilquest",           "EvilQuest",        .ransomware),
                ("rustdoor",            "RustDoor",         .backdoor),
                ("dazzlespy",           "DazzleSpy",        .spyware),
                ("shlayer",             "Shlayer",          .downloader),
                ("pirrit",              "Pirrit",           .adware),
                ("bundlore",            "Bundlore",         .adware),
                ("crescentcore",        "CrescentCore",     .backdoor),
            ]
            for (sig, name, type) in macMalwareStrings {
                if lower.contains(sig) {
                    threats.append(ThreatDetail(
                        type: type,
                        name: name,
                        affectedFile: fileName,
                        detail: "Binary contains strings associated with the \(name) malware family.",
                        canStrip: false
                    ))
                }
            }

            // ── Clipboard hijacker / Category 7 (System Configuration) ────────
            // Removed "0x" condition — hex literals are ubiquitous in any binary.
            // Retained specific crypto-address patterns combined with clipboard API.
            if lower.contains("nspasteboard") &&
               (lower.contains("bc1q") || lower.contains("bitcoin") || lower.contains("ethereum")) {
                threats.append(ThreatDetail(
                    type: .clipboardHijacker,
                    name: "Crypto clipboard hijacker",
                    affectedFile: fileName,
                    detail: "Binary monitors the clipboard and replaces cryptocurrency addresses with attacker-controlled wallets. Any crypto you try to send goes to the attacker.",
                    canStrip: false
                ))
            }

            // ── Ransomware indicators (Category 6) ───────────────────────────
            let ransomStrings = ["lockbit", "blackcat", "stop/djvu", "phobos ransomware", "your files have been encrypted", "ransom"]
            if ransomStrings.contains(where: { lower.contains($0) }) {
                threats.append(ThreatDetail(
                    type: .ransomware,
                    name: "Ransomware",
                    affectedFile: fileName,
                    detail: "Binary contains strings associated with ransomware. This would encrypt your files and demand payment.",
                    canStrip: false
                ))
            }

            // ── Keylogger (Category 1 — credential capture) ───────────────────
            // Requires BOTH keyboard event creation AND system-wide event tap —
            // the combination is specific to keylogger behavior.
            if lower.contains("cgeventcreatekeyboardevent") && lower.contains("cgeventtapcreatetype") {
                threats.append(ThreatDetail(
                    type: .keylogger,
                    name: "Keylogger",
                    affectedFile: fileName,
                    detail: "Binary installs a system-wide keyboard event tap to record everything you type.",
                    canStrip: false
                ))
            }
        }

        return threats
    }

private func titanVScanSHA256(_ url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        let chunk = 1024 * 1024
        while true {
            let data = handle.readData(ofLength: chunk)
            if data.isEmpty { break }
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

private func titanVScanProcess(_ path: String, args: [String], timeout: TimeInterval = 15)
    -> (ok: Bool, output: String) {
        let p = Process()
        let pipe = Pipe()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        p.standardOutput = pipe
        p.standardError = Pipe()
        p.standardInput = FileHandle.nullDevice
        do { try p.run() } catch { return (false, "") }

        let sema = DispatchSemaphore(value: 0)
        let box = Box<Data>(Data())
        DispatchQueue.global(qos: .utility).async {
            box.value = pipe.fileHandleForReading.readDataToEndOfFile()
            sema.signal()
        }
        let kill = DispatchWorkItem { p.terminate() }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: kill)
        p.waitUntilExit()
        kill.cancel()
        _ = sema.wait(timeout: .now() + 5)
        return (p.terminationStatus == 0, String(data: box.value, encoding: .utf8) ?? "")
    }
