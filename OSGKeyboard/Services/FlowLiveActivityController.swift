// FlowLiveActivityController.swift
// OSGKeyboard · Main App
//
// Starts and updates the Flow Live Activity so the Dynamic Island shows the
// OSGKeyboard brand mark while a voice session is active.

import ActivityKit
import Foundation
import OSGKeyboardShared

@MainActor
enum FlowLiveActivityController {
    private static var currentActivity: Activity<FlowActivityAttributes>?

    /// Begin showing OSGKeyboard in the Dynamic Island for an active Flow session.
    static func startSession() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            debug("Live Activity disabled in Settings")
            return
        }

        endStaleActivities()

        guard currentActivity == nil else {
            update(phase: .idle)
            return
        }

        let state = FlowActivityAttributes.ContentState(phase: .idle)
        let content = ActivityContent(state: state, staleDate: nil)

        do {
            currentActivity = try Activity.request(
                attributes: FlowActivityAttributes(),
                content: content,
                pushType: nil
            )
            debug("Live Activity started")
        } catch {
            debug("Live Activity start failed: \(error.localizedDescription)")
        }
    }

    static func update(phase: FlowActivityAttributes.ContentState.Phase) {
        guard let activity = currentActivity else { return }
        let state = FlowActivityAttributes.ContentState(phase: phase)
        let content = ActivityContent(state: state, staleDate: nil)
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
            debug("Live Activity ended")
        }
    }

    /// Host relaunch can leave orphan activities; clear them before starting anew.
    private static func endStaleActivities() {
        for activity in Activity<FlowActivityAttributes>.activities {
            Task {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
        currentActivity = nil
    }
}
