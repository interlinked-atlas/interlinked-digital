import Foundation

struct InstallRecord: Codable, Identifiable {
    let id: UUID
    let date: Date
    let fileName: String
    let fileType: String
    let installedFiles: [InstalledFile]
    let pkgReceiptIDs: [String]
    var status: InstallStatus
    var failureReason: String?        // set on failed installs; shown in the UI
    let logFileName: String
    var rollbackBackupPath: String?   // set after a successful uninstall; enables undo
    var sessionID: UUID?              // shared by all items installed in the same queue run
    // TITAN CORE™: domains added to /etc/hosts — removed on rollback (PRO only)
    var addedHostsEntries: [String]?
    var titanVerified: Bool?      // true = TITAN VERIFY™ passed with no demo signals
    var demoDetected: Bool?       // true = demo/trial signals found during verify scan
    var activationRequired: Bool? // true = installed OK but needs license key / in-DAW activation
    var verificationWarning: String? // non-nil = soft check flagged (e.g. AU not yet registered)
    var installerDocInfo: InstallerDocInfo? // parsed activation docs from installer media
    // Folders that appeared in user/system Library dirs DURING install (runtime-created, not in PKG receipt)
    // e.g. ~/Library/Application Support/MBM Audio created by the app on first run post-install
    var runtimeCreatedPaths: [String]?
    // Per-format disable state. nil = no formats ever disabled for this record.
    var disabledFormats: [DisabledFormatEntry]?
    // Date the user submitted feedback for this record. nil = no feedback submitted yet.
    var feedbackSubmittedAt: Date?
    // Set when this record is moved to Archive. nil = active Library record.
    var archivedAt: Date?
    // Why the record was archived: "clear_all" | "removed"
    var archiveReason: String?
    // Set when this record was created through a Recovery Kit reinstall. nil for all normal installs.
    // Runtime-only tracking: not exported to .atlaskit via SanitizedRecord.
    var recoveryKitID: UUID? = nil
    // Full path to the original installer file ATLAS received at install time.
    // Provenance only — never refers to an installed product destination.
    // nil for records created before this field was added.
    var installerSourcePath: String? = nil

    // MARK: - Ownership evidence (PKG installs only)
    //
    // Populated by installPKG using pre/post FilesystemSnapshot diffs.
    // Maps each path that CHANGED during the install to its evidence classification.
    // Paths not in this map are either preExistingUnchanged (within snapshot coverage)
    // or bomOnly (outside snapshot coverage) — both are non-deletable by default.
    // nil on non-PKG installs and legacy records (pre-evidence-model records).
    var fileEvidenceMap: [String: FileOwnershipEvidence]?

    // Classifies whether each attributed receipt was newly created by this transaction
    // or pre-existed and was merely rewritten. Used to decide whether to call
    // pkgutil --forget on uninstall: only .created receipts are forgotten.
    // nil on non-PKG installs and legacy records.
    var pkgReceiptProvenance: [String: ReceiptProvenance]?

    enum InstallStatus: String, Codable {
        case success
        case failure
        case uninstalled
    }

    struct InstalledFile: Codable {
        let sourceName: String
        let destinationPath: String
        // Nil on legacy records (pre-evidence model). Treat as .bomOnly when nil
        // and the record has a non-nil fileEvidenceMap (indicating the record was
        // produced after the evidence model was introduced).
        let ownershipEvidence: FileOwnershipEvidence?

        init(sourceName: String,
             destinationPath: String,
             ownershipEvidence: FileOwnershipEvidence? = nil) {
            self.sourceName        = sourceName
            self.destinationPath   = destinationPath
            self.ownershipEvidence = ownershipEvidence
        }
    }

    var statusIcon: String {
        if demoDetected == true        { return "exclamationmark.triangle.fill" }
        if activationRequired == true  { return "key.fill" }
        if verificationWarning != nil  { return "exclamationmark.circle.fill" }
        switch status {
        case .success:     return "checkmark.circle.fill"
        case .failure:     return "xmark.circle.fill"
        case .uninstalled: return "trash.circle.fill"
        }
    }

    var formattedDate: String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: date)
    }

    var shortTime: String {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f.string(from: date)
    }

    var shortDate: String {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: date)
    }

    var fileCount: Int { installedFiles.count }

    // MARK: - Codable with backward compatibility for records without rollbackBackupPath

    enum CodingKeys: String, CodingKey {
        case id, date, fileName, fileType, installedFiles, pkgReceiptIDs
        case status, failureReason, logFileName, rollbackBackupPath, sessionID
        case addedHostsEntries, titanVerified, demoDetected, runtimeCreatedPaths
        case activationRequired, verificationWarning, installerDocInfo
        case disabledFormats, feedbackSubmittedAt
        case archivedAt, archiveReason
        case recoveryKitID
        case installerSourcePath
        case fileEvidenceMap
        case pkgReceiptProvenance
    }

    init(id: UUID = UUID(), date: Date = Date(), fileName: String, fileType: String,
         installedFiles: [InstalledFile], pkgReceiptIDs: [String],
         status: InstallStatus, failureReason: String? = nil, logFileName: String,
         rollbackBackupPath: String? = nil, sessionID: UUID? = nil,
         addedHostsEntries: [String]? = nil,
         titanVerified: Bool? = nil, demoDetected: Bool? = nil,
         activationRequired: Bool? = nil, verificationWarning: String? = nil,
         installerDocInfo: InstallerDocInfo? = nil,
         runtimeCreatedPaths: [String]? = nil,
         disabledFormats: [DisabledFormatEntry]? = nil,
         feedbackSubmittedAt: Date? = nil,
         archivedAt: Date? = nil,
         archiveReason: String? = nil,
         recoveryKitID: UUID? = nil,
         installerSourcePath: String? = nil,
         fileEvidenceMap: [String: FileOwnershipEvidence]? = nil,
         pkgReceiptProvenance: [String: ReceiptProvenance]? = nil) {
        self.id = id
        self.date = date
        self.fileName = fileName
        self.fileType = fileType
        self.installedFiles = installedFiles
        self.pkgReceiptIDs = pkgReceiptIDs
        self.status = status
        self.failureReason = failureReason
        self.logFileName = logFileName
        self.rollbackBackupPath = rollbackBackupPath
        self.sessionID = sessionID
        self.addedHostsEntries = addedHostsEntries
        self.titanVerified = titanVerified
        self.demoDetected = demoDetected
        self.activationRequired  = activationRequired
        self.verificationWarning = verificationWarning
        self.installerDocInfo    = installerDocInfo
        self.runtimeCreatedPaths = runtimeCreatedPaths
        self.disabledFormats     = disabledFormats
        self.feedbackSubmittedAt = feedbackSubmittedAt
        self.archivedAt          = archivedAt
        self.archiveReason       = archiveReason
        self.recoveryKitID       = recoveryKitID
        self.installerSourcePath = installerSourcePath
        self.fileEvidenceMap     = fileEvidenceMap
        self.pkgReceiptProvenance = pkgReceiptProvenance
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id                 = try c.decode(UUID.self,             forKey: .id)
        date               = try c.decode(Date.self,             forKey: .date)
        fileName           = try c.decode(String.self,           forKey: .fileName)
        fileType           = try c.decode(String.self,           forKey: .fileType)
        installedFiles     = try c.decode([InstalledFile].self,  forKey: .installedFiles)
        pkgReceiptIDs      = try c.decode([String].self,         forKey: .pkgReceiptIDs)
        status             = try c.decode(InstallStatus.self,    forKey: .status)
        failureReason      = try c.decodeIfPresent(String.self,  forKey: .failureReason)
        logFileName        = try c.decode(String.self,           forKey: .logFileName)
        rollbackBackupPath = try c.decodeIfPresent(String.self,  forKey: .rollbackBackupPath)
        sessionID          = try c.decodeIfPresent(UUID.self,    forKey: .sessionID)
        addedHostsEntries    = try c.decodeIfPresent([String].self, forKey: .addedHostsEntries)
        titanVerified        = try c.decodeIfPresent(Bool.self,    forKey: .titanVerified)
        demoDetected         = try c.decodeIfPresent(Bool.self,    forKey: .demoDetected)
        activationRequired   = try c.decodeIfPresent(Bool.self,                    forKey: .activationRequired)
        verificationWarning  = try c.decodeIfPresent(String.self,                  forKey: .verificationWarning)
        installerDocInfo     = try c.decodeIfPresent(InstallerDocInfo.self,        forKey: .installerDocInfo)
        runtimeCreatedPaths  = try c.decodeIfPresent([String].self,                forKey: .runtimeCreatedPaths)
        disabledFormats      = try c.decodeIfPresent([DisabledFormatEntry].self,   forKey: .disabledFormats)
        feedbackSubmittedAt  = try c.decodeIfPresent(Date.self,                    forKey: .feedbackSubmittedAt)
        archivedAt           = try c.decodeIfPresent(Date.self,                    forKey: .archivedAt)
        archiveReason        = try c.decodeIfPresent(String.self,                  forKey: .archiveReason)
        recoveryKitID        = try c.decodeIfPresent(UUID.self,                          forKey: .recoveryKitID)
        installerSourcePath  = try c.decodeIfPresent(String.self,                        forKey: .installerSourcePath)
        fileEvidenceMap      = try c.decodeIfPresent([String: FileOwnershipEvidence].self, forKey: .fileEvidenceMap)
        pkgReceiptProvenance = try c.decodeIfPresent([String: ReceiptProvenance].self,    forKey: .pkgReceiptProvenance)
    }
}

// MARK: - FileOwnershipEvidence
//
// Classifies each file path relative to the install transaction that created it.
// Determined at install time by comparing pre/post FilesystemSnapshot (ctime-based).
// This is the authoritative signal for uninstall authorization.
//
// Authorization rules:
//   .transactionCreated    → SAFE to delete. Path did not exist before; installer wrote it.
//   .transactionReplaced   → FAIL CLOSED. Installer overwrote a pre-existing path.
//                            A prior product may still depend on it. Do not delete without
//                            explicit pre-install backup (not yet implemented).
//   .preExistingUnchanged  → DO NOT DELETE. Installer declared it in the BOM but did not
//                            write it. The file belongs to a prior installation.
//   .bomOnly               → DO NOT DELETE. Path is outside FilesystemSnapshot coverage;
//                            no ctime evidence is available.
enum FileOwnershipEvidence: String, Codable, Sendable {
    case transactionCreated
    case transactionReplaced
    case preExistingUnchanged
    case bomOnly
}

// MARK: - ReceiptProvenance
//
// Classifies whether a PKG receipt ID was created by this transaction or pre-existed.
// Used to determine whether pkgutil --forget should run on uninstall.
//
//   .created   → ATLAS created this receipt. Safe to forget on uninstall.
//   .rewritten → Receipt pre-existed. Installer rewrote the plist/BOM timestamp but
//                did not create the receipt. Do NOT forget — another product may depend
//                on it (e.g. com.adobe.Fonts installed by Adobe CC then rewritten by
//                FabFilter). Forgetting would corrupt the other product's pkgutil record.
enum ReceiptProvenance: String, Codable, Sendable {
    case created
    case rewritten
}

// MARK: - DisabledFormatEntry
// Records the original system path and the ATLAS-managed disabled storage path for one plugin format.
// Written by PluginToggleEngine.disable() and removed by PluginToggleEngine.enable().
struct DisabledFormatEntry: Codable {
    let format: String              // "au", "vst", "vst3", "aax" — lowercase
    let originalPath: String        // e.g. /Library/Audio/Plug-Ins/VST3/Serum.vst3
    let disabledStoragePath: String // e.g. ~/Library/Application Support/ATLAS/Disabled/<UUID>/Serum.vst3
    let disabledAt: Date
}
