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
    /// the Live Activity. `staleDate` semantics (verified against ActivityKit
    /// behaviour, not folklore): the *Dynamic Island* presentation is reliably
    /// removed shortly after the stale date passes, but the *lock-screen*
    /// banner may linger greyed-out depending on the iOS version — it is NOT
    /// guaranteed to be dismissed. Treating staleDate as "auto-cleanup" is
    /// therefore wrong on its own; the full zombie defence is this short
    /// window + launch-time reconciliation (`clearOrphanedActivities`) + the
    /// widget rendering an explicit "disconnected" state via
    /// `context.isStale`. While the host is alive the heartbeat calls
    /// `keepAlive()` every ~10 s, well inside this window.
    private static let staleWindow: TimeInterval = 30

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

    /// `applicationWillTerminate` 专用：阻塞到所有 `end` 完成，避免进程先退出而锁屏卡片残留。
    /// 等待必须带超时：ActivityKit 的 `end` 走异步 XPC，若在 watchdog 杀进程前
    /// 没有返回，无限期 `wait()` 会吞掉整个 ~5 秒终止窗口，反而让后续清理全部没跑。
    nonisolated static func endAllSynchronouslyOnTerminate() {
        let semaphore = DispatchSemaphore(value: 0)
        Task.detached(priority: .userInitiated) {
            let activities = Activity<FlowActivityAttributes>.activities
            let count = activities.count
            for activity in activities {
                await activity.end(activity.content, dismissalPolicy: .immediate)
            }
            FlowDiagnostics.log("Live Activity ended synchronously on terminate (count=\(count))")
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 2)
        currentPhase = .idle
        currentActivity = nil
    }
}
