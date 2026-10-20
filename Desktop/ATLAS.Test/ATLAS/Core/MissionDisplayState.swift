import Foundation

// Presentation-only model for ATLASMissionProgressView.
// No references to TitanMission or any engine type.

enum StepDisplayStatus {
    case pending, running, done, failed, warning, skipped
}

struct MissionStepDisplay: Identifiable {
    var id: UUID
    var title: String
    var status: StepDisplayStatus
    var resultNote: String
}

struct MissionDisplayState {
    var fileName: String
    var progress: Double          // 0.0 – 1.0
    var statusText: String
    var isRunning: Bool
    var isComplete: Bool
    var anyFailed: Bool
    var anyWarnings: Bool
    var steps: [MissionStepDisplay]
}
