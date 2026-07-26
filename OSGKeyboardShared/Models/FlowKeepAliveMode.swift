// FlowKeepAliveMode.swift
// OSGKeyboard · Shared
//
// User-selectable Flow session keep-alive strategy (mutually exclusive).

import Foundation

public enum FlowKeepAliveMode: String, CaseIterable, Identifiable, Sendable, Codable {
    /// Continuous audio capture + Live Activity (current default behaviour).
    case liveActivity = "liveActivity"
    /// Picture-in-picture waveform keep-alive; mic released between utterances.
    case pictureInPicture = "pictureInPicture"

    public var id: String { rawValue }

    /// Existing installs keep the Live Activity / continuous-capture path.
    public static let `default`: FlowKeepAliveMode = .liveActivity

    public var labelKey: String {
        switch self {
        case .liveActivity: return "settings.flow.keepAlive.liveActivity"
        case .pictureInPicture: return "settings.flow.keepAlive.pictureInPicture"
        }
    }

    public var subtitleKey: String {
        switch self {
        case .liveActivity: return "settings.flow.keepAlive.liveActivity.subtitle"
        case .pictureInPicture: return "settings.flow.keepAlive.pictureInPicture.subtitle"
        }
    }

    public static func fromStored(_ raw: String?) -> FlowKeepAliveMode {
        guard let raw, let value = FlowKeepAliveMode(rawValue: raw) else {
            return .default
        }
        return value
    }
}
