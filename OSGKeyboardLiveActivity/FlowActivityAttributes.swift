// FlowActivityAttributes.swift
// OSGKeyboard · Live Activity
//
// Shared ActivityKit model compiled into the widget extension and the
// main app so `FlowLiveActivityController` can start/update sessions.

import ActivityKit
import Foundation

/// Live Activity shown in the Dynamic Island while a Flow session is active.
struct FlowActivityAttributes: ActivityAttributes {
    /// Dynamic content updated as the user records and processes speech.
    struct ContentState: Codable, Hashable, Sendable {
        var phase: Phase

        enum Phase: String, Codable, Hashable, Sendable {
            case idle
            case recording
            case processing
        }
    }
}
