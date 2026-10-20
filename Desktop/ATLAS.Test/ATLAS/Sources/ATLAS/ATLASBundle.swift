import Foundation

extension Bundle {
    // Resolves ATLAS_ATLAS.bundle correctly in both a packaged .app and an SPM development build.
    // Bundle.module (SPM auto-generated) uses bundleURL (.app root) instead of resourceURL
    // (Contents/Resources/), so it fails on any Mac that is not the original build machine.
    static let atlasResources: Bundle = {
        // Packaged .app: /Applications/ATLAS.app/Contents/Resources/ATLAS_ATLAS.bundle
        if let url = Bundle.main.resourceURL?.appendingPathComponent("ATLAS_ATLAS.bundle"),
           let bundle = Bundle(url: url) {
            return bundle
        }
        // SPM development build: ATLAS_ATLAS.bundle is adjacent to the executable in the build dir
        let devURL = Bundle.main.bundleURL.appendingPathComponent("ATLAS_ATLAS.bundle")
        if let bundle = Bundle(url: devURL) { return bundle }
        fatalError("ATLAS_ATLAS.bundle not found at \(Bundle.main.resourceURL?.appendingPathComponent("ATLAS_ATLAS.bundle").path ?? "nil") or \(devURL.path)")
    }()
}
