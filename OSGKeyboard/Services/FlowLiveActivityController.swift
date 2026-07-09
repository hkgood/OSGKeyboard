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
    /// Last phase pushed to the Live Activity so `keepAlive()` can refresh the
    /// `staleDate` without changing what the user sees.
    nonisolated(unsafe) private static var currentPhase: FlowActivityAttributes.ContentState.Phase = .idle

    /// If the host app is force-quit its `endSession()` never runs, orphaning
    /// the Live Activity. A short `staleDate` lets the system grey it out and
    /// reclaim it on its own within ~45s of the process dying. While the host is
    /// alive the heartbeat calls `keepAlive()` well inside this window, so a
    /// genuinely active session never looks stale.
    private static let staleWindow: TimeInterval = 45

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
            currentPhase = .idle
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
        currentPhase = phase
        let content = freshContent(phase: phase)
        Task {
            await activity.update(content)
        }
    }

    /// Push a fresh `staleDate` without changing the visible phase. The host
    /// heartbeat calls this well inside `staleWindow` so an in-use session
    /// never looks stale; once the process dies the refreshes stop and the
    /// system reclaims the orphaned Live Activity on its own.
    static func keepAlive() {
        guard let activity = currentActivity else { return }
        let content = freshContent(phase: currentPhase)
        Task {
            await activity.update(content)
        }
    }

    /// Dismiss the island presentation when the Flow session ends.
    static func endSession() {
        currentPhase = .idle
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

    /// Clear Live Activities orphaned by a previous (force-quit) host process.
    ///
    /// Safe to call on every app foreground: when this process already owns a
    /// Live Activity (`currentActivity != nil`) we leave it alone so a healthy
    /// running session is never torn down; we only sweep leftovers that belong
    /// to a dead process. Call this *before* attempting to (re)start a session
    /// so a failed start (e.g. mic timeout) still clears the stale island.
    static func clearOrphanedActivities() {
        guard currentActivity == nil else { return }
        endStaleActivities()
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
