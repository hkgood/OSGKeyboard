// FlowInactivityDuration.swift
// OSGKeyboard · Shared
//
// User-selectable Flow session inactivity timeout. The timer resets after
// each completed utterance (and on session start).

import Foundation

public enum FlowInactivityDuration: String, CaseIterable, Identifiable, Sendable, Codable {
    case oneMinute = "1m"
    case fiveMinutes = "5m"
    case tenMinutes = "10m"
    case thirtyMinutes = "30m"
    case threeHours = "3h"
    case twelveHours = "12h"
    case twentyFourHours = "24h"

    public var id: String { rawValue }

    /// Privacy-safe default: users can choose a longer window explicitly.
    public static let `default`: FlowInactivityDuration = .fiveMinutes

    public var timeInterval: TimeInterval {
        switch self {
        case .oneMinute: return 60
        case .fiveMinutes: return 5 * 60
        case .tenMinutes: return 10 * 60
        case .thirtyMinutes: return 30 * 60
        case .threeHours: return 3 * 60 * 60
        case .twelveHours: return 12 * 60 * 60
        case .twentyFourHours: return 24 * 60 * 60
        }
    }

    public var labelKey: String {
        switch self {
        case .oneMinute: return "settings.flow.inactivity.1m"
        case .fiveMinutes: return "settings.flow.inactivity.5m"
        case .tenMinutes: return "settings.flow.inactivity.10m"
        case .thirtyMinutes: return "settings.flow.inactivity.30m"
        case .threeHours: return "settings.flow.inactivity.3h"
        case .twelveHours: return "settings.flow.inactivity.12h"
        case .twentyFourHours: return "settings.flow.inactivity.24h"
        }
    }

    public static func fromStored(_ raw: String?) -> FlowInactivityDuration {
        guard let raw, let value = FlowInactivityDuration(rawValue: raw) else {
            return .default
        }
        return value
    }
}
