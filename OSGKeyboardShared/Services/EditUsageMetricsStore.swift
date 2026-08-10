// EditUsageMetricsStore.swift
// OSGKeyboard · Shared
//
// Separate counters so editing never inflates ordinary dictation characters.

import Foundation

public struct EditUsageMetrics: Codable, Equatable, Sendable {
    public var enteredCount = 0
    public var replacedCount = 0
    public var appendedCount = 0
    public var cancelledCount = 0
    public var failedCount = 0
    public var instructionDurationSeconds: TimeInterval = 0
    public var updatedAt = Date()
}

public enum EditUsageMetricsStore {
    public enum Outcome: Sendable {
        case entered
        case replaced
        case appended
        case cancelled
        case failed
    }

    private static let key = "editLastInput.usageMetrics.v1"

    public static func record(
        _ outcome: Outcome,
        instructionDuration: TimeInterval = 0,
        defaults: UserDefaults? = nil
    ) {
        guard let store = defaults ?? AppGroup.defaultsIfAvailable else { return }
        var metrics = load(defaults: store)
        switch outcome {
        case .entered: metrics.enteredCount += 1
        case .replaced: metrics.replacedCount += 1
        case .appended: metrics.appendedCount += 1
        case .cancelled: metrics.cancelledCount += 1
        case .failed: metrics.failedCount += 1
        }
        metrics.instructionDurationSeconds += max(0, instructionDuration)
        metrics.updatedAt = Date()
        if let data = try? JSONEncoder().encode(metrics) {
            store.set(data, forKey: key)
            store.synchronize()
        }
    }

    public static func load(defaults: UserDefaults? = nil) -> EditUsageMetrics {
        guard let store = defaults ?? AppGroup.defaultsIfAvailable,
              let data = store.data(forKey: key),
              let metrics = try? JSONDecoder().decode(EditUsageMetrics.self, from: data)
        else {
            return EditUsageMetrics()
        }
        return metrics
    }

    public static func recordInstructionDuration(
        _ duration: TimeInterval,
        defaults: UserDefaults? = nil
    ) {
        guard duration > 0,
              let store = defaults ?? AppGroup.defaultsIfAvailable else {
            return
        }
        var metrics = load(defaults: store)
        metrics.instructionDurationSeconds += duration
        metrics.updatedAt = Date()
        if let data = try? JSONEncoder().encode(metrics) {
            store.set(data, forKey: key)
            store.synchronize()
        }
    }
}
