// KeyboardExtensionMemoryTelemetry.swift
// OSGKeyboard · Shared
//
// Observes keyboard-extension memory without changing runtime behavior.
// The host process never starts this monitor, so shared typing code can emit
// extension-only milestones without duplicating host telemetry.

import Foundation
import Darwin

public enum KeyboardExtensionMemoryBudget {
    /// Start preserving evidence before the extension reaches its safe ceiling.
    public static let warningMB: Double = 36
    /// Internal release target. Apple's keyboard-extension limit is not public.
    public static let safePeakMB: Double = 40
    /// Leave headroom below the observed ~60 MiB device jetsam boundary.
    public static let criticalMB: Double = 48

    public enum Level: String, Sendable, Equatable {
        case normal
        case warning
        case high
        case critical
        case unavailable
    }

    public static func level(forPhysFootprintMB footprintMB: Double) -> Level {
        guard footprintMB >= 0 else { return .unavailable }
        if footprintMB >= criticalMB { return .critical }
        if footprintMB >= safePeakMB { return .high }
        if footprintMB >= warningMB { return .warning }
        return .normal
    }
}

@MainActor
public enum KeyboardExtensionMemoryTelemetry {
    private static let peakLogStepMB: Double = 4
    private static let bootSampleInterval = Duration.milliseconds(50)
    private static let bootSampleDuration: TimeInterval = 4

    private static var isActive = false
    private static var processID: Int32 = 0
    private static var context = "surface=- language=-"
    private static var baselineFootprintMB: Double = -1
    private static var peakFootprintMB: Double = -1
    private static var lastLoggedPeakMB: Double = -1
    private static var highestLevel = KeyboardExtensionMemoryBudget.Level.normal
    private static var startedAt: TimeInterval = 0
    private static var samplingTask: Task<Void, Never>?

    public static func begin(context initialContext: String) {
        samplingTask?.cancel()
        samplingTask = nil
        isActive = true
        processID = getpid()
        context = initialContext
        startedAt = ProcessInfo.processInfo.systemUptime

        let snapshot = OSGDiag.memorySnapshot()
        baselineFootprintMB = snapshot.physFootprintMB
        peakFootprintMB = snapshot.physFootprintMB
        lastLoggedPeakMB = snapshot.physFootprintMB
        highestLevel = .normal
        emit(stage: "process.begin", snapshot: snapshot, alwaysLog: true)
    }

    public static func updateContext(_ newContext: String) {
        guard isActive else { return }
        context = newContext
    }

    public static func record(_ stage: String, details: String? = nil) {
        guard isActive else { return }
        let eventContext = details.map { "\(context) \($0)" } ?? context
        emit(
            stage: stage,
            snapshot: OSGDiag.memorySnapshot(),
            eventContext: eventContext,
            alwaysLog: true
        )
    }

    /// Samples short-lived startup spikes that milestone-only logging can miss.
    /// Poll samples log only on a new budget band or each additional 4 MiB peak.
    public static func startBootSampling() {
        guard isActive else { return }
        samplingTask?.cancel()
        let deadline = ProcessInfo.processInfo.systemUptime + bootSampleDuration
        samplingTask = Task { @MainActor in
            while !Task.isCancelled, ProcessInfo.processInfo.systemUptime < deadline {
                try? await Task.sleep(for: bootSampleInterval)
                guard !Task.isCancelled else { return }
                emit(
                    stage: "boot.sample",
                    snapshot: OSGDiag.memorySnapshot(),
                    eventContext: context,
                    alwaysLog: false
                )
            }
            samplingTask = nil
            record("boot.sample.complete")
        }
    }

    private static func emit(
        stage: String,
        snapshot: OSGDiag.MemorySnapshot,
        eventContext: String? = nil,
        alwaysLog: Bool
    ) {
        let footprint = snapshot.physFootprintMB
        if footprint >= 0 {
            peakFootprintMB = max(peakFootprintMB, footprint)
        }
        let level = KeyboardExtensionMemoryBudget.level(forPhysFootprintMB: footprint)
        let crossedLevel = levelRank(level) > levelRank(highestLevel)
        if crossedLevel {
            highestLevel = level
        }
        let peakAdvanced = peakFootprintMB >= 0
            && (lastLoggedPeakMB < 0 || peakFootprintMB - lastLoggedPeakMB >= peakLogStepMB)
        guard alwaysLog || crossedLevel || peakAdvanced else { return }
        if peakFootprintMB >= 0 {
            lastLoggedPeakMB = peakFootprintMB
        }

        let elapsedMS = max(
            0,
            Int((ProcessInfo.processInfo.systemUptime - startedAt) * 1_000)
        )
        let delta = baselineFootprintMB >= 0 && peakFootprintMB >= 0
            ? peakFootprintMB - baselineFootprintMB
            : -1
        OSGDiag.log(
            String(
                format: "extMemory pid=%d stage=%@ elapsed=%dms level=%@ crossed=%d "
                    + "rss=%.1fMB foot=%.1fMB peak=%.1fMB delta=%.1fMB "
                    + "safe=%dMB critical=%dMB context={%@}",
                processID,
                stage,
                elapsedMS,
                level.rawValue,
                crossedLevel ? 1 : 0,
                snapshot.rssMB,
                footprint,
                peakFootprintMB,
                delta,
                Int(KeyboardExtensionMemoryBudget.safePeakMB),
                Int(KeyboardExtensionMemoryBudget.criticalMB),
                eventContext ?? context
            ),
            category: "memory"
        )
    }

    private static func levelRank(_ level: KeyboardExtensionMemoryBudget.Level) -> Int {
        switch level {
        case .unavailable:
            return -1
        case .normal:
            return 0
        case .warning:
            return 1
        case .high:
            return 2
        case .critical:
            return 3
        }
    }
}
