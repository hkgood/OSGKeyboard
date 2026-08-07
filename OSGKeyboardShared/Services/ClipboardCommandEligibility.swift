// ClipboardCommandEligibility.swift
// OSGKeyboard · Shared
//
// Tracks clipboard open-window eligibility (30s from first sighting of a
// pasteboard change) for opportunity-read UI. Pure timing logic — no UIKit.

import Foundation

public struct ClipboardCommandEligibility: Equatable, Sendable {
    public var changeCount: Int
    public var snapshot: String
    public var startedAt: TimeInterval

    public init(changeCount: Int, snapshot: String, startedAt: TimeInterval = Date().timeIntervalSince1970) {
        self.changeCount = changeCount
        self.snapshot = snapshot
        self.startedAt = startedAt
    }

    public func isOpen(at now: TimeInterval = Date().timeIntervalSince1970) -> Bool {
        now - startedAt <= ClipboardMaterialFilter.eligibilityDuration
    }

    public func remaining(at now: TimeInterval = Date().timeIntervalSince1970) -> TimeInterval {
        max(0, ClipboardMaterialFilter.eligibilityDuration - (now - startedAt))
    }
}

public enum ClipboardCommandEligibilityTracker: Sendable {
    /// Update eligibility from an opportunity-read sample.
    /// - Parameters:
    ///   - changeCount: `UIPasteboard.general.changeCount`
    ///   - rawText: pasteboard string (may be nil)
    ///   - previous: last known eligibility
    ///   - now: clock
    public static func refresh(
        changeCount: Int,
        rawText: String?,
        previous: ClipboardCommandEligibility?,
        now: TimeInterval = Date().timeIntervalSince1970
    ) -> ClipboardCommandEligibility? {
        guard let rawText else { return nil }

        if let previous, previous.changeCount == changeCount {
            return previous.isOpen(at: now) ? previous : nil
        }

        switch ClipboardMaterialFilter.evaluate(rawText) {
        case .eligible(let snapshot):
            return ClipboardCommandEligibility(
                changeCount: changeCount,
                snapshot: snapshot,
                startedAt: now
            )
        case .rejected:
            return nil
        }
    }
}

/// In-memory clipboard-command task session (plan §8 layer B). Owned by the keyboard.
public struct ClipboardCommandTaskSession: Equatable, Sendable {
    public var snapshot: String
    public var previousOutput: String?
    public var lastInsertedText: String?
    public var expiresAt: TimeInterval
    public var fieldFingerprint: String?

    public init(
        snapshot: String,
        previousOutput: String? = nil,
        lastInsertedText: String? = nil,
        expiresAt: TimeInterval,
        fieldFingerprint: String? = nil
    ) {
        self.snapshot = snapshot
        self.previousOutput = previousOutput
        self.lastInsertedText = lastInsertedText
        self.expiresAt = expiresAt
        self.fieldFingerprint = fieldFingerprint
    }

    public func isActive(at now: TimeInterval = Date().timeIntervalSince1970) -> Bool {
        now <= expiresAt
    }

    public mutating func refreshExpiry(at now: TimeInterval = Date().timeIntervalSince1970) {
        expiresAt = now + ClipboardMaterialFilter.sessionDuration
    }

    public mutating func noteSuccessfulInsert(_ text: String, at now: TimeInterval = Date().timeIntervalSince1970) {
        lastInsertedText = text
        previousOutput = text
        refreshExpiry(at: now)
    }
}
