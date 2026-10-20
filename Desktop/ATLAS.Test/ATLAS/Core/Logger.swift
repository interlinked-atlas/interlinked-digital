// Core/Logger.swift
// Append-only timestamped log.
// @MainActor means all updates happen on the main thread,
// which is required for @Published properties that drive SwiftUI views.

import Foundation

@MainActor
class Logger: ObservableObject {
    @Published var entries: [String] = []

    func log(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let timestamp = formatter.string(from: Date())
        let entry = "[\(timestamp)] \(message)"
        entries.append(entry)
        print(entry)
    }

    func clear() {
        entries = []
    }
}