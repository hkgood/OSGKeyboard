// AnalyticsUploadScheduling.swift
// OSGKeyboard · Main App
//
// Count- and time-based foreground upload scheduling. Recording remains
// fire-and-forget; networking is single-flight and stops when the app resigns.

import Foundation
import OSGKeyboardShared

struct AnalyticsUploadPolicy: Sendable {
    static let mobileDefault = Self(
        eventThreshold: 20,
        flushInterval: .seconds(60),
        activationDelay: .seconds(10),
        maximumBatches: 2
    )

    let eventThreshold: Int
    let flushInterval: Duration
    let activationDelay: Duration
    let maximumBatches: Int

    init(
        eventThreshold: Int,
        flushInterval: Duration,
        activationDelay: Duration,
        maximumBatches: Int
    ) {
        self.eventThreshold = max(1, eventThreshold)
        self.flushInterval = flushInterval
        self.activationDelay = activationDelay
        self.maximumBatches = max(1, maximumBatches)
    }
}

actor AnalyticsUploadSignal: AnalyticsUploadTriggering {
    typealias Action = @Sendable () async -> Void

    private let policy: AnalyticsUploadPolicy
    private var action: Action?
    private var isActive = false
    private var pendingSignals = 0
    private var timerTask: Task<Void, Never>?
    private var uploadTask: Task<Void, Never>?

    init(policy: AnalyticsUploadPolicy = .mobileDefault) {
        self.policy = policy
    }

    func install(_ action: @escaping Action) {
        self.action = action
        if isActive, pendingSignals > 0, uploadTask == nil {
            schedule(after: policy.activationDelay, replacingTimer: true)
        }
    }

    func requestUpload() {
        pendingSignals = min(Int.max, pendingSignals + 1)
        guard isActive, uploadTask == nil else { return }

        if pendingSignals >= policy.eventThreshold {
            schedule(after: .zero, replacingTimer: true)
        } else {
            schedule(after: policy.flushInterval)
        }
    }

    /// Starts one bounded backlog drain after the foreground has settled.
    func requestActivationUpload() {
        pendingSignals = max(1, pendingSignals)
        guard isActive, uploadTask == nil else { return }
        schedule(after: policy.activationDelay, replacingTimer: true)
    }

    func setActive(_ active: Bool) async {
        guard active != isActive else {
            if active, pendingSignals > 0, uploadTask == nil {
                schedule(after: policy.activationDelay)
            }
            return
        }

        isActive = active
        if active {
            if pendingSignals > 0 {
                schedule(after: policy.activationDelay, replacingTimer: true)
            }
        } else {
            await cancelAndWait()
        }
    }

    /// Cancels timers and networking, then waits until the upload action has
    /// unwound. Callers can keep a short UIKit background assertion while this
    /// returns so no SQLite transaction survives process suspension.
    func pauseAndWait() async {
        isActive = false
        await cancelAndWait()
    }

    private func schedule(
        after delay: Duration,
        replacingTimer: Bool = false
    ) {
        guard isActive, action != nil, uploadTask == nil else { return }
        if replacingTimer {
            timerTask?.cancel()
            timerTask = nil
        }
        guard timerTask == nil else { return }

        timerTask = Task { [weak self] in
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }
            await self?.timerFired()
        }
    }

    private func timerFired() {
        timerTask = nil
        guard isActive,
              uploadTask == nil,
              pendingSignals > 0,
              let action else {
            return
        }

        pendingSignals = 0
        uploadTask = Task { [weak self] in
            await action()
            await self?.uploadFinished()
        }
    }

    private func uploadFinished() {
        uploadTask = nil
        guard isActive, pendingSignals > 0 else { return }
        let delay: Duration = pendingSignals >= policy.eventThreshold
            ? .zero
            : policy.flushInterval
        schedule(after: delay, replacingTimer: true)
    }

    private func cancelAndWait() async {
        timerTask?.cancel()
        timerTask = nil

        let task = uploadTask
        task?.cancel()
        await task?.value
        uploadTask = nil
    }
}
