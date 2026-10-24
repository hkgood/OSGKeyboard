// DictationProgress.swift
// OSGKeyboard · Shared
//
// Staged, time-estimated progress for the dictation wait after the user stops
// recording. The host only reports two milestones to the keyboard (`rawReady`
// when ASR finishes, `final` when polish finishes) and polish is a single
// non-streaming request, so the fill between milestones is an estimate: it
// eases toward a ceiling it never reaches, and only the real `final` result
// completes the bar.

import Foundation

/// Timestamps of one dictation wait, owned by `KeyboardState`.
public struct DictationProgressTimeline: Equatable, Sendable {
    public let utteranceID: UUID
    public let transcribingStartedAt: TimeInterval
    public private(set) var polishingStartedAt: TimeInterval?
    /// Raw transcript length when polish began; scales the expected duration.
    public private(set) var polishCharacterCount: Int = 0
    public private(set) var expectedPolishSeconds: TimeInterval = 0

    public init(utteranceID: UUID, transcribingStartedAt: TimeInterval) {
        self.utteranceID = utteranceID
        self.transcribingStartedAt = transcribingStartedAt
    }

    /// Records the ASR → polish milestone once; later `rawReady` repeats are ignored.
    public mutating func markPolishing(
        at time: TimeInterval,
        characterCount: Int,
        expectedSeconds: TimeInterval
    ) {
        guard polishingStartedAt == nil else { return }
        polishingStartedAt = time
        polishCharacterCount = characterCount
        expectedPolishSeconds = expectedSeconds
    }
}

public enum DictationProgressEstimator {
    /// Asymptote of the ASR stage; the bar never passes it before `rawReady`.
    static let transcribingCeiling = 0.25
    /// Time constant of the ASR stage curve (local drain is usually < 1 s).
    static let transcribingTimeConstant: TimeInterval = 1.0
    /// Where the polish stage starts, so `rawReady` reads as a visible step.
    static let polishingFloor = 0.35
    /// Asymptote of the polish stage; only the real result fills to 100 %.
    static let polishingCeiling = 0.95
    /// Duration of the ease from the ASR curve into the polish curve.
    static let stageBlendSeconds: TimeInterval = 0.25

    /// Fill fraction in `0...polishingCeiling` for `timeline` at `now`.
    public static func fraction(
        for timeline: DictationProgressTimeline,
        at now: TimeInterval
    ) -> Double {
        guard let polishStart = timeline.polishingStartedAt else {
            return transcribingFraction(elapsed: now - timeline.transcribingStartedAt)
        }
        let atMilestone = transcribingFraction(
            elapsed: polishStart - timeline.transcribingStartedAt
        )
        let elapsed = max(0, now - polishStart)
        // At `elapsed == expected` the polish curve covers ~86 % of its range.
        let timeConstant = max(timeline.expectedPolishSeconds, 0.5) / 2
        let polishing = polishingFloor
            + (polishingCeiling - polishingFloor) * (1 - exp(-elapsed / timeConstant))
        let blend = min(elapsed / stageBlendSeconds, 1)
        return atMilestone + (polishing - atMilestone) * blend
    }

    static func transcribingFraction(elapsed: TimeInterval) -> Double {
        transcribingCeiling * (1 - exp(-max(0, elapsed) / transcribingTimeConstant))
    }
}

/// Learns this device's polish latency so the estimate tracks the user's
/// provider and network. Stored in the extension's own defaults; it is a UI
/// hint, not a setting, so it is neither synced nor shared with the host.
public struct DictationPolishLatencyCalibration {
    static let overheadKey = "keyboard.dictationProgress.polishOverheadSeconds"
    static let defaultOverheadSeconds: TimeInterval = 1.5
    static let secondsPerCharacter: TimeInterval = 0.012
    static let overheadRange: ClosedRange<TimeInterval> = 0.5...15
    /// Weight of the newest observation in the moving average.
    static let smoothing = 0.3

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func expectedSeconds(forCharacterCount count: Int) -> TimeInterval {
        overheadSeconds + Double(max(0, count)) * Self.secondsPerCharacter
    }

    public func record(observedSeconds: TimeInterval, characterCount: Int) {
        guard observedSeconds.isFinite, observedSeconds > 0 else { return }
        let observedOverhead = observedSeconds
            - Double(max(0, characterCount)) * Self.secondsPerCharacter
        let blended = overheadSeconds * (1 - Self.smoothing) + observedOverhead * Self.smoothing
        defaults.set(
            min(max(blended, Self.overheadRange.lowerBound), Self.overheadRange.upperBound),
            forKey: Self.overheadKey
        )
    }

    var overheadSeconds: TimeInterval {
        let stored = defaults.double(forKey: Self.overheadKey)
        return stored > 0 ? stored : Self.defaultOverheadSeconds
    }
}
