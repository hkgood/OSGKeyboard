// FlowLiveActivityController.swift
// OSGKeyboard · Main App
//
// Starts and updates the Flow Live Activity so the Dynamic Island shows the
// OSGKeyboard brand mark while a voice session is active.

import ActivityKit
import Foundation
import OSGKeyboardShared

enum FlowLiveActivityController {
    nonisolated(unsafe) private static var currentActivity: Activity<FlowActivityAttributes>?

    /// If the host app is force-quit its `endSession()` never runs, orphaning
    /// the Live Activity. A `staleDate` lets the system grey it out and become
    /// willing to reclaim it without our process — refreshed on every update
    /// so a genuinely active, in-use session never looks stale.
    private static let staleWindow: TimeInterval = 60 * 60

    private static func freshContent(
        phase: FlowActivityAttributes.ContentState.Phase
    ) -> ActivityContent<FlowActivityAttributes.ContentState> {
        ActivityContent(
            state: FlowActivityAttributes.ContentState(phase: phase),
            staleDate: Date().addingTimeInterval(staleWindow)
        )
    }

    /// Begin showing OSGKeyboard in the Dynamic Island for an active Flow session.
    static func startSession() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            FlowDiagnostics.log("Live Activity disabled in Settings")
            return
        }

        endStaleActivities()

        guard currentActivity == nil else {
            update(phase: .idle)
            return
        }

        do {
            currentActivity = try Activity.request(
                attributes: FlowActivityAttributes(),
                content: freshContent(phase: .idle),
                pushType: nil
            )
            FlowDiagnostics.log("Live Activity started")
        } catch {
            FlowDiagnostics.log("Live Activity start failed: \(error.localizedDescription)")
        }
    }

    static func update(phase: FlowActivityAttributes.ContentState.Phase) {
        guard let activity = currentActivity else { return }
        let content = freshContent(phase: phase)
        Task {
            await activity.update(content)
        }
    }

    /// Dismiss the island presentation when the Flow session ends.
    static func endSession() {
        guard let activity = currentActivity else {
            endStaleActivities()
            return
        }

        currentActivity = nil
        Task {
            await activity.end(nil, dismissalPolicy: .immediate)
            FlowDiagnostics.log("Live Activity ended")
        }
    }

    /// Host relaunch can leave orphan activities; clear them before starting anew.
    private static func endStaleActivities() {
        let staleActivities = Activity<FlowActivityAttributes>.activities
        currentActivity = nil
        guard !staleActivities.isEmpty else { return }
        Task {
            for activity in staleActivities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }
}
