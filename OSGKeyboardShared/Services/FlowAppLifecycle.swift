// FlowAppLifecycle.swift
// OSGKeyboard · Shared
//
// Tracks whether the host app process is in the foreground.
// Retained for any future GPU-backed paths; CoreML ASR does not require it.

import Foundation

public final class FlowAppLifecycle: @unchecked Sendable {

    public static let shared = FlowAppLifecycle()

    private let lock = NSLock()
    private var isForeground = true

    private init() {}

    /// `true` when the host app scene is active (`.active`).
    public var allowsGPUInference: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isForeground
    }

    public func setForeground(_ foreground: Bool) {
        lock.lock()
        isForeground = foreground
        lock.unlock()
    }

    /// Blocks until foreground or cancellation.
    public func waitUntilForeground() async -> Bool {
        while !allowsGPUInference {
            if Task.isCancelled { return false }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        return true
    }
}
