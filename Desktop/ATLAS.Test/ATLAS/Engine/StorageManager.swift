import Foundation
import AppKit

// MARK: - Volume model

struct StorageVolume: Identifiable {
    let id = UUID()
    let name: String
    let url: URL
    let isInternal: Bool
    let isExternal: Bool
    let isBoot: Bool
    let availableBytes: Int64
    let totalBytes: Int64

    var displayName: String {
        isBoot ? "\(name) (System Drive)" : name
    }

    var availableFormatted: String { Self.format(availableBytes) }
    var totalFormatted: String     { Self.format(totalBytes) }
    var usedPercent: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(totalBytes - availableBytes) / Double(totalBytes)
    }

    var icon: String {
        if isBoot    { return "internaldrive.fill" }
        if isExternal { return "externaldrive.fill" }
        return "internaldrive"
    }

    static func format(_ bytes: Int64) -> String {
        let gb = Double(bytes) / (1024 * 1024 * 1024)
        let tb = gb / 1024
        if tb >= 1 { return String(format: "%.1f TB", tb) }
        if gb >= 1 { return String(format: "%.1f GB", gb) }
        let mb = Double(bytes) / (1024 * 1024)
        return String(format: "%.0f MB", mb)
    }
}

// MARK: - Validation

struct StorageValidation {
    let isValid: Bool
    let message: String
}

// MARK: - Manager

final class StorageManager {
    static let shared = StorageManager()
    private init() {}

    // Large-install threshold: 5 GB
    static let largeInstallThreshold: Int64 = 5 * 1024 * 1024 * 1024

    func availableVolumes() -> [StorageVolume] {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [
            .volumeNameKey,
            .volumeIsRemovableKey,
            .volumeIsEjectableKey,
            .volumeIsInternalKey,
            .volumeIsLocalKey,
            .volumeAvailableCapacityKey,
            .volumeTotalCapacityKey,
            .volumeIsReadOnlyKey,
        ]
        guard let mounts = try? fm.mountedVolumeURLs(
            includingResourceValuesForKeys: keys,
            options: [.skipHiddenVolumes]
        ) else { return [] }

        let bootDevice = bootVolumeURL()

        // Build a set of disk-image mount points to exclude (Virtual media type)
        let diskImageMounts = diskImageMountPoints()

        var volumes: [StorageVolume] = []
        for url in mounts {
            guard let res = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            guard res.volumeIsLocal == true else { continue }           // skip network
            guard res.volumeIsReadOnly != true else { continue }        // skip read-only
            guard (res.volumeTotalCapacity ?? 0) > 0 else { continue } // skip zero-size

            // Skip mounted disk images (DMG, ISO, sparse bundle, etc.)
            let mountPath = url.standardized.path
            guard !diskImageMounts.contains(mountPath) else { continue }

            // Only show physical internal drives and real external drives (USB/Thunderbolt)
            let isInternal = res.volumeIsInternal ?? false
            let isEjectable = res.volumeIsEjectable == true
            let isRemovable = res.volumeIsRemovable == true
            // A real external drive is ejectable AND removable but NOT a disk image (already filtered)
            let isExternal = !isInternal && (isEjectable || isRemovable)
            // Skip anything that is neither internal nor a real external physical drive
            guard isInternal || isExternal else { continue }

            let name   = res.volumeName ?? url.lastPathComponent
            let isBoot = mountPath == bootDevice

            let volume = StorageVolume(
                name:           name,
                url:            url,
                isInternal:     isInternal,
                isExternal:     isExternal,
                isBoot:         isBoot,
                availableBytes: Int64(res.volumeAvailableCapacity ?? 0),
                totalBytes:     Int64(res.volumeTotalCapacity ?? 0)
            )
            volumes.append(volume)
        }

        // Sort: boot volume first, then internal, then external
        return volumes.sorted {
            if $0.isBoot != $1.isBoot { return $0.isBoot }
            if $0.isInternal != $1.isInternal { return $0.isInternal }
            return $0.name < $1.name
        }
    }

    func validate(_ volume: StorageVolume, neededBytes: Int64) -> StorageValidation {
        if volume.availableBytes < neededBytes {
            let needed = StorageVolume.format(neededBytes)
            let avail  = StorageVolume.format(volume.availableBytes)
            return StorageValidation(isValid: false,
                message: "Not enough space — need \(needed), only \(avail) free.")
        }
        if volume.availableBytes < Int64(Double(neededBytes) * 1.15) {
            return StorageValidation(isValid: true,
                message: "Space is tight on this volume. Proceeding anyway.")
        }
        return StorageValidation(isValid: true, message: "")
    }

    // MARK: - Helpers

    // Returns the set of mount points backed by disk images (DMG, ISO, SPARSEIMAGE, etc.)
    // Checks each mounted volume via `diskutil info -plist` for Protocol == "Disk Image".
    private func diskImageMountPoints() -> Set<String> {
        let fm = FileManager.default
        guard let allMounts = try? fm.mountedVolumeURLs(
            includingResourceValuesForKeys: [.volumeIsLocalKey],
            options: [.skipHiddenVolumes]) else { return [] }

        var imageMounts = Set<String>()
        for url in allMounts {
            let proc = Process()
            proc.launchPath = "/usr/sbin/diskutil"
            proc.arguments  = ["info", "-plist", url.path]
            let pipe = Pipe()
            proc.standardOutput = pipe
            proc.standardError  = Pipe()
            guard (try? proc.run()) != nil else { continue }
            proc.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil)
                    as? [String: Any] else { continue }
            if let proto = plist["Protocol"] as? String, proto == "Disk Image" {
                imageMounts.insert(url.standardized.path)
            }
        }
        return imageMounts
    }

    private func bootVolumeURL() -> String {
        let result = Process()
        result.launchPath = "/usr/sbin/diskutil"
        result.arguments  = ["info", "-plist", "/"]
        let pipe = Pipe()
        result.standardOutput = pipe
        try? result.run()
        result.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if let plist = try? PropertyListSerialization.propertyList(
            from: data, format: nil) as? [String: Any],
           let mount = plist["MountPoint"] as? String {
            return URL(fileURLWithPath: mount).standardized.path
        }
        return "/"
    }
}
