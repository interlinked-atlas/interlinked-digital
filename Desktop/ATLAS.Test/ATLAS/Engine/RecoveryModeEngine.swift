import Foundation
import SwiftUI

// MARK: - RecoveryModeEngine
//
// Orchestration layer for Recovery Mode reinstallation.
// Owns the [RecoverySlot] list derived from a loaded AtlasKit.
// Drives serial installations through the existing InstallEngine pipeline.
// Never modifies the source AtlasKit or SanitizedRecord data.

@MainActor
final class RecoveryModeEngine: ObservableObject {

    @Published private(set) var slots: [RecoverySlot]
    @Published private(set) var isRunningBatch: Bool = false
    @Published private(set) var isComplete: Bool = false

    private let store: HistoryStore

    #if DEBUG
    /// When set, replaces the real InstallEngine call in installSingleSlot().
    /// Returns the slot state to apply on completion. Receives the installer URL.
    /// Used exclusively by RecoveryKitTests — never set in production builds.
    var _testInstallOverride: ((URL) async -> RecoverySlotState)? = nil
    #endif

    init(kit: AtlasKit, store: HistoryStore) {
        self.store = store
        self.slots = kit.records.map { record in
            RecoverySlot(id: record.id, record: record)
        }
    }

    // MARK: - Slot management

    func setInstaller(id: UUID, url: URL) {
        guard let idx = slots.firstIndex(where: { $0.id == id }) else { return }
        if slots[idx].state.isInstalling { return }
        if case .success = slots[idx].state { return }
        let type_ = InstallerClassifier.classify(url: url)
        slots[idx].installerURL   = url
        slots[idx].classifiedType = type_
        if case .unsupported(let ext) = type_ {
            slots[idx].state = .unsupportedFormat(ext)
        } else {
            slots[idx].state = .ready
        }
        slots[idx].progress    = 0
        slots[idx].progressStep = ""
        isComplete = false
    }

    func skip(id: UUID) {
        guard let idx = slots.firstIndex(where: { $0.id == id }),
              !slots[idx].state.isTerminal,
              !slots[idx].state.isInstalling else { return }
        slots[idx].state = .skipped
        checkCompletion()
    }

    func retrySlot(id: UUID) {
        guard let idx = slots.firstIndex(where: { $0.id == id }) else { return }
        guard case .failure = slots[idx].state else { return }
        slots[idx].state       = slots[idx].installerURL != nil ? .ready : .waitingForInstaller
        slots[idx].progress    = 0
        slots[idx].progressStep = ""
        isComplete = false
    }

    // MARK: - Installation

    /// Install all slots currently in .ready state, serially.
    /// Stops the batch if any slot hits .limitReached.
    /// Continues past per-slot failures.
    func installAllReady() async {
        guard !isRunningBatch else { return }
        isRunningBatch = true
        defer { isRunningBatch = false }

        let readyIDs = slots.filter { $0.state == .ready }.map(\.id)
        for id in readyIDs {
            await installSingleSlot(id: id)
            // Stop batch on limit — continuing would only produce more .limitReached slots
            if let slot = slots.first(where: { $0.id == id }),
               case .limitReached = slot.state {
                break
            }
        }
        checkCompletion()
    }

    /// Install one slot. Checks limit, runs InstallEngine, records result.
    func installSingleSlot(id: UUID) async {
        guard let idx = slots.firstIndex(where: { $0.id == id }),
              slots[idx].state == .ready,
              let url = slots[idx].installerURL else { return }

        slots[idx].state       = .installing
        slots[idx].progress    = 0
        slots[idx].progressStep = "Checking installation limit…"
        slots[idx].log         = []

        // Server-side limit gate — atomic reserve; confirmed on success or
        // released on failure/unsupported below.
        let reservation = await MonthlyLimitManager.shared.reserveSlot()
        guard reservation.allowed else {
            if let i = slots.firstIndex(where: { $0.id == id }) {
                slots[i].state = .limitReached
            }
            return
        }
        let reservationID = reservation.reservationID
        // Local lock check (edge case when server is unreachable)
        if MonthlyLimitManager.shared.isLocked {
            if let i = slots.firstIndex(where: { $0.id == id }) {
                slots[i].state = .limitReached
            }
            return
        }

        if let i = slots.firstIndex(where: { $0.id == id }) {
            slots[i].progressStep = "Starting installation…"
        }

        let logger = Logger()
        let slotID = id

        #if DEBUG
        // Test override path — replaces real install pipeline when _testInstallOverride is set.
        // In production (non-DEBUG) builds this block does not exist.
        if let override = _testInstallOverride {
            let resultState = await override(url)
            if let reservationID {
                if resultState == .success {
                    await MonthlyLimitManager.shared.confirmSuccess(reservationID: reservationID)
                } else {
                    await MonthlyLimitManager.shared.releaseReservation(reservationID: reservationID)
                }
            }
            if let i = slots.firstIndex(where: { $0.id == id }) {
                slots[i].state    = resultState
                slots[i].progress = resultState == .success ? 1.0 : slots[i].progress
            }
            checkCompletion()
            return
        }
        #endif

        let progressReporter: ProgressReporter = { [weak self] pct, step in
            await MainActor.run { [weak self] in
                guard let self else { return }
                guard let i = self.slots.firstIndex(where: { $0.id == slotID }) else { return }
                var copy = self.slots
                copy[i].progress     = pct
                copy[i].progressStep = step
                if !step.isEmpty, copy[i].log.last != step {
                    copy[i].log.append(step)
                }
                self.slots = copy
            }
        }

        // One jobID for this Recovery Mode install, generated before the call
        // (no retry in this path, but ownership must still be explicit rather
        // than inferred from a mutable global — see beginInstall's docs).
        let journalJobID = UUID()
        let outcome = await InstallEngine.install(url: url, logger: logger, journalJobID: journalJobID, progress: progressReporter)

        guard let finalIdx = slots.firstIndex(where: { $0.id == id }) else {
            if let reservationID {
                if case .success = outcome.result {
                    await MonthlyLimitManager.shared.confirmSuccess(reservationID: reservationID)
                } else {
                    await MonthlyLimitManager.shared.releaseReservation(reservationID: reservationID)
                }
            }
            OperationJournal.shared.clear(jobID: journalJobID)
            return
        }

        let fileType = url.pathExtension.lowercased()

        switch outcome.result {
        case .success:
            // Only a confirmed successful recovery-mode install consumes a monthly
            // installation — the authoritative success signal for this path.
            if let reservationID {
                await MonthlyLimitManager.shared.confirmSuccess(reservationID: reservationID)
            }
            // Write install log and create InstallRecord (same as normal install)
            var record = InstallLogger.writeLog(
                fileURL: url,
                fileType: fileType.isEmpty ? "app" : fileType,
                entries: logger.entries,
                result: outcome.result,
                installedFiles: outcome.installedFiles,
                pkgReceiptIDs: outcome.receiptIDs
            )
            // Tag the record as a Recovery Kit reinstall
            record.recoveryKitID = slots[finalIdx].record.id
            if !InstallEngine.lastPKGEvidenceMap.isEmpty {
                record.fileEvidenceMap = InstallEngine.lastPKGEvidenceMap
            }
            if !InstallEngine.lastPKGReceiptProvenance.isEmpty {
                record.pkgReceiptProvenance = InstallEngine.lastPKGReceiptProvenance
            }
            store.add(record)
            slots[finalIdx].state    = .success
            slots[finalIdx].progress = 1.0

        case .failure:
            if let reservationID {
                await MonthlyLimitManager.shared.releaseReservation(reservationID: reservationID)
            }
            // Write failure log for diagnostics; do NOT add to HistoryStore (per spec: successful only)
            InstallLogger.writeLog(
                fileURL: url,
                fileType: fileType.isEmpty ? "app" : fileType,
                entries: logger.entries,
                result: outcome.result,
                installedFiles: [],
                pkgReceiptIDs: []
            )
            let reason: String
            if case .failure(let r) = outcome.result { reason = r } else { reason = "Unknown error" }
            slots[finalIdx].state = .failure(reason)
        case .unsupportedDAWInstallation(let dawName):
            if let reservationID {
                await MonthlyLimitManager.shared.releaseReservation(reservationID: reservationID)
            }
            slots[finalIdx].state = .failure("DAW installation not supported: \(dawName)")
        }
        // Every branch above has now reached a definitive, already-persisted
        // (or deliberately-not-persisted, per the failure-path comment)
        // conclusion — the journal's job is done.
        OperationJournal.shared.clear(jobID: journalJobID)

        // Check after every individual install — enables per-slot completion screen,
        // not just after installAllReady().
        checkCompletion()
    }

    // MARK: - Pro gating (extracted for testability)

    /// Pure function — determines if Recovery Mode may be entered.
    /// Production callers pass `Features.recoveryModeEnabled` (= AuthManager.shared.isPro).
    /// Extracted so XCTest can verify Standard/Pro cases without depending on AuthManager.
    nonisolated static func canStartRecovery(isPro: Bool) -> Bool { isPro }

    // MARK: - Completion

    private func checkCompletion() {
        isComplete = !slots.isEmpty && slots.allSatisfy { $0.state.isTerminal }
    }

    // MARK: - Computed counts

    var readyCount:              Int { slots.filter { $0.state == .ready }.count }
    var installingCount:         Int { slots.filter { $0.state.isInstalling }.count }
    var successCount:            Int { slots.filter { if case .success      = $0.state { return true }; return false }.count }
    var failedCount:             Int { slots.filter { if case .failure      = $0.state { return true }; return false }.count }
    var skippedCount:            Int { slots.filter { if case .skipped      = $0.state { return true }; return false }.count }
    var limitReachedCount:       Int { slots.filter { if case .limitReached = $0.state { return true }; return false }.count }
    var unsupportedFormatCount:  Int { slots.filter { if case .unsupportedFormat = $0.state { return true }; return false }.count }
    /// Slots awaiting user action before they can be installed: no installer yet, or unsupported installer.
    var pendingCount:            Int { slots.filter {
        if $0.state == .waitingForInstaller { return true }
        if case .unsupportedFormat = $0.state { return true }
        return false
    }.count }
}
