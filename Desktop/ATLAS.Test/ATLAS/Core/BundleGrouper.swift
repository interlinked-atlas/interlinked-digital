import Foundation

// BundleGrouper — when users drop multiple files at once, this detects
// which files belong to the same product so ATLAS can label them as a
// bundle and install them in the right sequence (plugin first, then library).

struct InstallBundle {
    let name: String           // inferred product name
    let files: [URL]           // all files in this group, in install order
    let isSingleFile: Bool     // false = multi-file bundle
}

struct BundleGrouper {

    // MARK: - Entry point

    /// Group a list of dropped URLs into logical install bundles.
    /// Files that share a product name are grouped together.
    /// Files with no clear group become single-file bundles.
    static func group(_ urls: [URL]) -> [InstallBundle] {
        guard urls.count > 1 else {
            return urls.map { InstallBundle(name: nameFor($0), files: [$0], isSingleFile: true) }
        }

        // Step 1: build a normalized token set for each URL
        var tokenMap: [(url: URL, tokens: Set<String>)] = urls.map { url in
            (url, tokenize(url))
        }

        // Step 2: greedy grouping — merge URLs that share at least one substantive token
        var groups: [[URL]] = []
        var used = Set<Int>()

        for i in 0..<tokenMap.count {
            guard !used.contains(i) else { continue }
            var group = [tokenMap[i].url]
            used.insert(i)
            for j in (i+1)..<tokenMap.count {
                guard !used.contains(j) else { continue }
                let sharedTokens = tokenMap[i].tokens.intersection(tokenMap[j].tokens)
                if !sharedTokens.isEmpty {
                    group.append(tokenMap[j].url)
                    used.insert(j)
                    // Expand to also grab tokens from j for further matching
                    tokenMap[i] = (tokenMap[i].url, tokenMap[i].tokens.union(tokenMap[j].tokens))
                }
            }
            groups.append(group)
        }

        // Step 3: sort files within each group (plugin before library/patch)
        return groups.map { files in
            let sorted = sortInstallOrder(files)
            let name = bundleName(for: sorted)
            return InstallBundle(name: name, files: sorted, isSingleFile: sorted.count == 1)
        }
    }

    // MARK: - Tokenize

    private static func tokenize(_ url: URL) -> Set<String> {
        let raw = url.deletingPathExtension().lastPathComponent
        // Normalize: lowercase, remove version strings, split on separators
        let stripped = raw
            .lowercased()
            .replacingOccurrences(of: #"v?\d+[\.\d]*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"[_\-\.\s]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)

        let words = stripped.components(separatedBy: " ").filter { $0.count >= 3 }

        // Only keep substantive tokens (skip generic words)
        let stopWords: Set<String> = ["the","for","and","mac","osx","win","x64","x86",
                                      "installer","install","setup","update","patch",
                                      "crack","keygen","fixed","release","repack"]
        let filtered = Set(words.filter { !stopWords.contains($0) })
        return filtered
    }

    // MARK: - Install order

    // Within a bundle: PKGs run first (the plugin/app), then scripts/binaries (patch/keygen)
    private static func sortInstallOrder(_ urls: [URL]) -> [URL] {
        let order: (URL) -> Int = { url in
            let ext = url.pathExtension.lowercased()
            switch ext {
            case "pkg":                      return 0
            case "dmg":                      return 1
            case "component","vst3","vst","aaxplugin": return 2
            case "app":                      return 3
            case "zip","rar","7z":           return 4
            case "sh","command","bash":      return 5
            default:                         return 6
            }
        }
        return urls.sorted { order($0) < order($1) }
    }

    // MARK: - Name inference

    private static func bundleName(for files: [URL]) -> String {
        // Use the name from the "primary" file (first in sorted order)
        guard let first = files.first else { return "Unknown" }
        return nameFor(first)
    }

    static func nameFor(_ url: URL) -> String {
        // Strip extension and clean up the filename into a readable product name
        var name = url.deletingPathExtension().lastPathComponent
        // Remove version patterns like "v1.2.3", "1.2", "V16"
        name = name.replacingOccurrences(of: #"\s*[vV]?\d[\d\.]*\s*$"#, with: "", options: .regularExpression)
        // Replace separators with spaces
        name = name.replacingOccurrences(of: #"[_\-]+"#, with: " ", options: .regularExpression)
        return name.trimmingCharacters(in: .whitespaces)
    }
}
