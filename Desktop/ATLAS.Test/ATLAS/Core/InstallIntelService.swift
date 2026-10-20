import Foundation

// Fetches web-sourced install intelligence from the InterLinked API.
// Used ONLY as a fallback when no local instruction file is present.
// All errors are swallowed — failure returns nil and ATLAS proceeds normally.

struct WebInstallIntel: Decodable {
    let found:              Bool
    let source:             String?
    let sourceUrl:          String?
    let steps:              [String]?
    let hostsEntries:       [String]?
    let mentionsRosetta:    Bool?
    let requiresAdmin:      Bool?
    let mentionsSelectAll:  Bool?
    let appToLaunch:        String?
    let knownIssues:        [String]?
    let notes:              String?
    let confidence:         Double?
    let cached:             Bool?

    enum CodingKeys: String, CodingKey {
        case found, source, sourceUrl, steps, hostsEntries
        case mentionsRosetta, requiresAdmin, mentionsSelectAll
        case appToLaunch, knownIssues, notes, confidence, cached
    }
}

enum InstallIntelService {

    private static let endpoint = URL(string: "https://www.interlinked.digital/api/atlas/install-intel")!
    private static let timeoutSeconds: TimeInterval = 8

    // Fetches install intel for a product name.
    // Returns nil on any error or when nothing useful was found.
    static func fetch(productName: String, fileNames: [String] = []) async -> WebInstallIntel? {
        guard !productName.isEmpty else { return nil }

        var req = URLRequest(url: endpoint, timeoutInterval: timeoutSeconds)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "productName": productName,
            "fileNames": fileNames,
        ]
        guard let encoded = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        req.httpBody = encoded

        guard let (data, response) = try? await URLSession.shared.data(for: req),
              let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else { return nil }

        guard let intel = try? JSONDecoder().decode(WebInstallIntel.self, from: data),
              intel.found else { return nil }

        // Discard low-confidence results — not worth using
        if let confidence = intel.confidence, confidence < 0.4 { return nil }

        return intel
    }

    // Converts web intel into a synthetic ParsedInstructions so the rest of
    // InstallIntelligence can consume it without any changes to that code path.
    static func toSyntheticInstructions(_ intel: WebInstallIntel, sourceDir: String) -> ParsedInstructions {
        ParsedInstructions(
            rawText:              intel.notes ?? intel.steps?.joined(separator: "\n") ?? "",
            sourceFileName:       "Web Intel (\(intel.source ?? "online"))",
            steps:                intel.steps ?? [],
            mentionsPatch:        intel.steps?.joined().lowercased().contains("patch") ?? false,
            mentionsOrder:        !(intel.steps?.isEmpty ?? true),
            mentionsRosetta:      intel.mentionsRosetta      ?? false,
            mentionsAdminRequired: intel.requiresAdmin       ?? false,
            customNotes:          intel.knownIssues          ?? [],
            appToLaunch:          intel.appToLaunch,
            mentionsSelectAll:    intel.mentionsSelectAll    ?? false,
            mentionsManagerApp:   intel.appToLaunch != nil,
            folderCopySteps:      [],
            hostsEntries:         intel.hostsEntries         ?? [],
            terminalCommands:     [],
            mentionsXcodeTools:   false,
            scriptsToRun:         [],
            binariesToRun:        [],
            detectedLanguage:     "en",
            requiresInternetActivation: false,
            isDownloadAssistant:  false
        )
    }
}
