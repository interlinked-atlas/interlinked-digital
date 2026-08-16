import Foundation
import CryptoKit

// MARK: - AtlasKit

/// Top-level container for an exported ATLAS Recovery Kit.
/// Holds a sanitized snapshot of installation records — no credentials, no license keys.
struct AtlasKit: Codable, Sendable {
    let kitVersion: Int             // format version; currently 1
    let atlasVersion: String        // app version string at export time
    let exportedAt: Date
    var payloadHash: String         // SHA256 hex of payload encoded with payloadHash = ""; var for two-phase hash
    let records: [SanitizedRecord]
    let archivedRecords: [SanitizedRecord]

    // MARK: - Centralized encoder factory
    // Single source of truth for encoder config — used for export hashing, export write, and import verification.
    static func makeEncoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }

    // MARK: - Two-phase SHA256 hash

    /// Computes the payload hash for a kit.
    /// Phase: set payloadHash = "" on a copy, encode with makeEncoder(), SHA256 the bytes.
    static func computeHash(for kit: AtlasKit) throws -> String {
        var copy = kit
        copy.payloadHash = ""
        let data = try makeEncoder().encode(copy)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - SanitizedRecord

/// A sanitized copy of InstallRecord with sensitive and machine-internal fields excluded.
/// Structurally excludes: logFileName, rollbackBackupPath, sessionID, installerDocInfo, feedbackSubmittedAt.
/// These fields cannot appear in the export because they are never copied into this type.
struct SanitizedRecord: Codable, Sendable {
    let id: UUID
    let date: Date
    let fileName: String
    let fileType: String
    let installedFiles: [SanitizedInstalledFile]
    let pkgReceiptIDs: [String]
    let status: InstallRecord.InstallStatus
    let failureReason: String?
    // logFileName: excluded — local filesystem path, meaningless cross-Mac
    // rollbackBackupPath: excluded — ATLAS internal path
    // sessionID: excluded — internal queue grouping, no recovery value
    let addedHostsEntries: [String]?
    let titanVerified: Bool?
    let demoDetected: Bool?
    let activationRequired: Bool?
    let verificationWarning: String?
    // installerDocInfo: EXCLUDED — contains licenseKeys (third-party serial numbers/activation codes)
    let runtimeCreatedPaths: [String]?
    let disabledFormats: [DisabledFormatEntry]?
    // feedbackSubmittedAt: excluded — internal ATLAS telemetry
    let archivedAt: Date?
    let archiveReason: String?

    init(from record: InstallRecord) {
        id                  = record.id
        date                = record.date
        fileName            = record.fileName
        fileType            = record.fileType
        installedFiles      = record.installedFiles.map { SanitizedInstalledFile(from: $0) }
        pkgReceiptIDs       = record.pkgReceiptIDs
        status              = record.status
        failureReason       = record.failureReason
        addedHostsEntries   = record.addedHostsEntries
        titanVerified       = record.titanVerified
        demoDetected        = record.demoDetected
        activationRequired  = record.activationRequired
        verificationWarning = record.verificationWarning
        // installerDocInfo intentionally not copied
        runtimeCreatedPaths = record.runtimeCreatedPaths
        disabledFormats     = record.disabledFormats
        // feedbackSubmittedAt intentionally not copied
        archivedAt          = record.archivedAt
        archiveReason       = record.archiveReason
    }
}

// MARK: - SanitizedInstalledFile

/// Sanitized version of InstallRecord.InstalledFile — source name and destination path only.
/// Destination paths are reference data: they identify where files were installed on the source Mac.
/// During import, these paths are displayed for reference only and never passed to any filesystem operation.
struct SanitizedInstalledFile: Codable, Sendable {
    let sourceName: String
    let destinationPath: String

    init(from file: InstallRecord.InstalledFile) {
        sourceName      = file.sourceName
        destinationPath = file.destinationPath
    }
}

// MARK: - Recovery Mode runtime model (never persisted in .atlaskit)

/// One slot per SanitizedRecord in a loaded kit.
/// Tracks the user-supplied installer and per-product install state during a Recovery Mode session.
/// Lives only in RecoveryModeEngine — discarded when Recovery Mode exits.
struct RecoverySlot: Identifiable {
    let id: UUID                          // == SanitizedRecord.id
    let record: SanitizedRecord           // reference metadata from the loaded kit
    var installerURL: URL?                // user-supplied installer file
    var classifiedType: InstallerType?    // result of InstallerClassifier.classify
    var state: RecoverySlotState = .waitingForInstaller
    var progress: Double = 0
    var progressStep: String = ""
    var log: [String] = []
}

enum RecoverySlotState: Equatable {
    case waitingForInstaller
    case ready
    case unsupportedFormat(String)   // installer type not supported
    case installing
    case success
    case failure(String)
    case skipped
    case limitReached

    var isTerminal: Bool {
        switch self {
        case .success, .failure, .skipped, .limitReached: return true
        default: return false
        }
    }

    var isInstalling: Bool {
        if case .installing = self { return true }
        return false
    }
}
