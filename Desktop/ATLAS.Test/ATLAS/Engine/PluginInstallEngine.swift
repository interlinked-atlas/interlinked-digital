import Foundation

struct PluginInstallEngine {

    // Returns both an InstallResult and the list of files placed,
    // so InstallationManager can save them to the history record.
    static func installPlugins(
        in directoryPath: String,
        logger: Logger
    ) async -> (result: InstallResult, installedFiles: [InstallRecord.InstalledFile]) {

        guard let password = KeychainManager.loadPassword() else {
            await logger.log("No password found in Keychain")
            return (.failure(reason: "No password stored. Please restart ATLAS."), [])
        }

        await logger.log("Scanning for audio plugins...")

        var components: [URL] = []
        var vst3s: [URL] = []
        var aaxPlugins: [URL] = []
        var vsts: [URL] = []

        if let enumerator = FileManager.default.enumerator(atPath: directoryPath) {
            for case let path as String in enumerator {
                guard !path.contains("__MACOSX") else { continue }
                let full = URL(fileURLWithPath: directoryPath)
                    .appendingPathComponent(path)
                if path.hasSuffix(".component") { components.append(full) }
                if path.hasSuffix(".vst3")      { vst3s.append(full) }
                if path.hasSuffix(".aaxplugin") { aaxPlugins.append(full) }
                if path.hasSuffix(".vst")       { vsts.append(full) }
            }
        }

        if components.isEmpty && vst3s.isEmpty && aaxPlugins.isEmpty && vsts.isEmpty {
            await logger.log("No plugin files found")
            return (.failure(reason: "No .component, .vst3, .aaxplugin, or .vst files found."), [])
        }

        await logger.log("Found \(components.count) AU, \(vst3s.count) VST3, \(aaxPlugins.count) AAX, \(vsts.count) VST")

        var installedFiles: [InstallRecord.InstalledFile] = []
        var succeeded = 0
        var failed = 0

        for url in components {
            let (success, destPath) = await installPlugin(
                url: url,
                destination: "/Library/Audio/Plug-Ins/Components",
                password: password,
                logger: logger
            )
            if success {
                succeeded += 1
                installedFiles.append(InstallRecord.InstalledFile(
                    sourceName: url.lastPathComponent,
                    destinationPath: destPath
                ))
            } else {
                failed += 1
            }
        }

        for url in vst3s {
            let (success, destPath) = await installPlugin(
                url: url,
                destination: "/Library/Audio/Plug-Ins/VST3",
                password: password,
                logger: logger
            )
            if success {
                succeeded += 1
                installedFiles.append(InstallRecord.InstalledFile(
                    sourceName: url.lastPathComponent,
                    destinationPath: destPath
                ))
            } else {
                failed += 1
            }
        }

        for url in aaxPlugins {
            let (success, destPath) = await installPlugin(
                url: url,
                destination: "/Library/Application Support/Avid/Audio/Plug-Ins",
                password: password,
                logger: logger
            )
            if success {
                succeeded += 1
                installedFiles.append(InstallRecord.InstalledFile(
                    sourceName: url.lastPathComponent,
                    destinationPath: destPath
                ))
            } else {
                failed += 1
            }
        }

        for url in vsts {
            let (success, destPath) = await installPlugin(
                url: url,
                destination: "/Library/Audio/Plug-Ins/VST",
                password: password,
                logger: logger
            )
            if success {
                succeeded += 1
                installedFiles.append(InstallRecord.InstalledFile(
                    sourceName: url.lastPathComponent,
                    destinationPath: destPath
                ))
            } else {
                failed += 1
            }
        }

        await logger.log("Plugin install complete: \(succeeded) succeeded, \(failed) failed")

        // DAW rescan notice + path mismatch warning
        if succeeded > 0 {
            let runningDAWs = DAWRescanAdvisor.runningDAWs()
            if !runningDAWs.isEmpty {
                await logger.log("  💡 Rescan plugins in: \(runningDAWs.joined(separator: ", "))")
                await logger.log("     Most DAWs: Preferences → Plug-ins → Rescan (or restart the DAW)")
            } else {
                await logger.log("  💡 Open your DAW and rescan plugins to see the newly installed plugin.")
            }
            await PluginPathAdvisor.logMismatchWarning(to: logger)
        }

        let names = installedFiles.map { $0.sourceName }.joined(separator: ", ")

        if failed == 0 {
            return (.success(appName: names), installedFiles)
        } else if succeeded == 0 {
            return (.failure(reason: "All plugin installs failed."), installedFiles)
        } else {
            return (.success(appName: "\(names) (partial)"), installedFiles)
        }
    }

    private static func installPlugin(
        url: URL,
        destination: String,
        password: String,
        logger: Logger
    ) async -> (success: Bool, destinationPath: String) {
        let name = url.lastPathComponent
        let destPath = "\(destination)/\(name)"

        await logger.log("Installing \(name) to \(destination)...")

        _ = runWithPassword(password: password,
                           arguments: ["/bin/mkdir", "-p", destination])

        if FileManager.default.fileExists(atPath: destPath) {
            await logger.log("  ↺ Replacing existing version of \(name)")
            _ = runWithPassword(password: password,
                               arguments: ["/bin/rm", "-rf", destPath])
        }

        let copyResult = runWithPassword(password: password,
                                        arguments: ["/bin/cp", "-r", url.path, destPath])

        if !copyResult.success {
            await logger.log("✗ Copy failed for \(name): \(copyResult.output)")
            return (false, destPath)
        }

        await logger.log("Copied \(name)")

        _ = runWithPassword(password: password,
                           arguments: ["/usr/bin/xattr", "-cr", destPath])
        _ = runWithPassword(password: password,
                           arguments: ["/usr/bin/xattr", "-r", "-d",
                                      "com.apple.quarantine", destPath])

        // Remove .DS_Store from the bundle root before signing.
        // cp -r copies it from the source folder; its presence causes codesign
        // to report "unsealed contents present in the bundle root".
        let bundleRootDSStore = destPath + "/.DS_Store"
        if FileManager.default.fileExists(atPath: bundleRootDSStore) {
            _ = runWithPassword(password: password,
                               arguments: ["/bin/rm", "-f", bundleRootDSStore])
        }

        let codesignResult = runWithPassword(
            password: password,
            arguments: ["/usr/bin/codesign", "--force", "--deep", "--sign", "-", destPath]
        )

        if codesignResult.success ||
           codesignResult.output.contains("replacing existing signature") ||
           codesignResult.output.contains("unsealed contents") {
            await logger.log("✓ Codesign applied to \(name)")
        } else {
            await logger.log("Warning: codesign issue for \(name): \(codesignResult.output)")
        }

        if FileManager.default.fileExists(atPath: destPath) {
            await logger.log("✓ \(name) verified at \(destination)")
            return (true, destPath)
        } else {
            await logger.log("✗ Verification failed for \(name)")
            return (false, destPath)
        }
    }

    private static func runWithPassword(
        password: String,
        arguments: [String]
    ) -> (success: Bool, output: String) {
        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        process.arguments = ["-S"] + arguments
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = outputPipe
        do {
            try process.run()
            let data = (password + "\n").data(using: .utf8)!
            inputPipe.fileHandleForWriting.write(data)
            inputPipe.fileHandleForWriting.closeFile()
            process.waitUntilExit()
        } catch {
            return (false, error.localizedDescription)
        }
        let out = outputPipe.fileHandleForReading.readDataToEndOfFile()
        return (process.terminationStatus == 0,
                String(data: out, encoding: .utf8) ?? "")
    }
}

extension PluginInstallEngine {

    // Installs a single standalone plugin file dropped directly by user.
    static func installSinglePlugin(
        url: URL,
        logger: Logger
    ) async -> (result: InstallResult, installedFiles: [InstallRecord.InstalledFile]) {

        guard let password = KeychainManager.loadPassword() else {
            await logger.log("No password found in Keychain")
            return (.failure(reason: "No password stored."), [])
        }

        let ext = url.pathExtension.lowercased()
        // TITAN CORE™ Smart Storage: prefix with custom volume root if set
        let libRoot = InstallEngine.storageRoot?.appendingPathComponent("Library").path ?? "/Library"
        let destination: String

        switch ext {
        case "component":
            destination = "\(libRoot)/Audio/Plug-Ins/Components"
        case "vst3":
            destination = "\(libRoot)/Audio/Plug-Ins/VST3"
        case "vst":
            destination = "\(libRoot)/Audio/Plug-Ins/VST"
        case "aaxplugin":
            destination = "\(libRoot)/Application Support/Avid/Audio/Plug-Ins"
        default:
            return (.failure(reason: "Unknown plugin type: .\(ext)"), [])
        }

        await logger.log("Installing standalone plugin: \(url.lastPathComponent)")
        let (success, destPath) = await installPlugin(
            url: url,
            destination: destination,
            password: password,
            logger: logger
        )

        if success {
            return (.success(appName: url.lastPathComponent),
                    [InstallRecord.InstalledFile(
                        sourceName: url.lastPathComponent,
                        destinationPath: destPath)])
        } else {
            return (.failure(reason: "Could not install \(url.lastPathComponent)"), [])
        }
    }
}
