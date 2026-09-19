// KeyboardExtensionMemoryTelemetry.swift
// OSGKeyboard · Shared
//
// Observes keyboard-extension memory AND sheds load before the system does.
// The host process never starts this monitor, so shared typing code can emit
// extension-only milestones without duplicating host telemetry.
//
// Observation alone was not enough: `didReceiveMemoryWarning` is the only
// system signal an extension gets, and jetsam frequently kills a keyboard at
// the ~60 MiB boundary without ever delivering one. `reliefHandler` lets the
// extension drop its heavy caches on OUR thresholds (40 / 48 MiB), which are
// deliberately below that boundary.

import Darwin
import Foundation

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
    /// Highest level already relieved in the current pressure episode. Reset only
    /// when the footprint falls back below `warningMB` — see `requestReliefIfNeeded`.
    private static var lastReliefLevel = KeyboardExtensionMemoryBudget.Level.normal

    /// Poll interval once the startup burst is over. Sustained sampling is what
    /// catches growth *between* milestones (a long clipboard session, a big
    /// candidate list) — milestone-only sampling misses it entirely.
    private static let sustainedSampleInterval = Duration.seconds(1)
    /// Invoked on the main actor when the footprint crosses `.high` or
    /// `.critical`. The keyboard extension installs this to release the Rime
    /// engine, the English lexicon and any in-flight pipeline work. Nothing
    /// else in the process is allowed to set it.
    ///
    /// Returns whether relief was actually performed. `false` means the host
    /// declined *this* attempt (it is mid-composition and will not yank the
    /// typing surface out from under the user), and the level stays armed so the
    /// next poll asks again — a declined attempt must not be mistaken for a
    /// completed one, or the keyboard would sit at 48 MiB having shed nothing.
    public static var reliefHandler: (@MainActor @Sendable (KeyboardExtensionMemoryBudget.Level) -> Bool)?

    public static func begin(context initialContext: String) {
        samplingTask?.cancel()
        samplingTask = nil
        lastReliefLevel = .normal
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

    /// Samples short-lived startup spikes that milestone-only logging can miss,
    /// then keeps polling at a low rate for the rest of the presentation so
    /// pressure that builds up mid-session still reaches `reliefHandler`.
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
            guard !Task.isCancelled else { return }
            record("boot.sample.complete")
            await pollPressure()
        }
    }

    /// Resumes low-rate sampling for a re-presented keyboard without replaying
    /// the startup burst. No-ops while the boot burst is still running.
    public static func startSustainedSamplingIfIdle() {
        guard isActive, samplingTask == nil else { return }
        samplingTask = Task { @MainActor in
            await pollPressure()
        }
    }

    /// Stops sampling (keyboard dismissed). The extension process survives
    /// between presentations, so an uncancelled poll would keep waking a hidden
    /// keyboard forever.
    public static func stopSampling() {
        samplingTask?.cancel()
        samplingTask = nil
    }

    private static func pollPressure() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: sustainedSampleInterval)
            guard !Task.isCancelled else { return }
            emit(
                stage: "pressure.sample",
                snapshot: OSGDiag.memorySnapshot(),
                eventContext: context,
                alwaysLog: false
            )
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
        // Shed BEFORE logging: at `.critical` we are ~12 MiB from the observed
        // jetsam boundary and the log line is the less important half.
        requestReliefIfNeeded(level: level, stage: stage)
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

    /// Asks the host to release heavy resources, at most once per level per
    /// pressure episode. Escalation (`.high` → `.critical`) still fires: the
    /// harder shed must not be swallowed by the soft one that preceded it.
    private static func requestReliefIfNeeded(
        level: KeyboardExtensionMemoryBudget.Level,
        stage: String
    ) {
        // Hysteresis, not a cooldown. A timed gap re-sheds every few seconds
        // while the footprint sits above the threshold, which reads to the user
        // as the keyboard repeatedly resetting itself. Re-arm only once pressure
        // has genuinely receded — back under `warningMB`, a full band below the
        // level that triggered the shed. `.warning` itself neither sheds nor
        // re-arms: it is the band the keyboard lands in right after shedding.
        if level == .normal {
            lastReliefLevel = .normal
        }
        guard level == .high || level == .critical, let handler = reliefHandler else { return }
        guard levelRank(level) > levelRank(lastReliefLevel) else { return }
        OSGDiag.log(
            "extMemory relief level=\(level.rawValue) stage=\(stage) \(OSGDiag.memoryTag())",
            category: "memory"
        )
        guard handler(level) else {
            OSGDiag.log(
                "extMemory relief declined level=\(level.rawValue) stage=\(stage)",
                category: "memory"
            )
            return
        }
        lastReliefLevel = level
    }

    #if DEBUG
    /// Test seam: drives the threshold + hysteresis logic without needing the
    /// test process's real footprint to cross 48 MiB.
    static func simulateFootprintForTesting(_ footprintMB: Double, stage: String = "test") {
        requestReliefIfNeeded(
            level: KeyboardExtensionMemoryBudget.level(forPhysFootprintMB: footprintMB),
            stage: stage
        )
    }
    #endif

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
