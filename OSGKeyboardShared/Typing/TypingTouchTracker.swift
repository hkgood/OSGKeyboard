// TypingTouchTracker.swift
// OSGKeyboard · Shared
//
// Multi-finger typing contract (system-keyboard overlap):
// each finger is independent; a new key-down commits any other pending
// character/space/return so press order, not release order, wins.
// Shift can be held with one finger while another types.

import Foundation

/// Per-step side effects for the UIKit touch pad to apply.
public struct TypingTouchEffects: Equatable, Sendable {
    public var commits: [TypingKeyHitTarget] = []
    public var playFeedback: TypingKeyHitTarget?
    public var deleteFire = false
    public var startDeleteRepeat = false
    public var stopDeleteRepeat = false
    public var beginShift = false
    public var endShift = false

    public init() {}
}

/// Pure multi-touch state machine. IDs are `ObjectIdentifier` of `UITouch`
/// in the extension, or any unique object in tests.
public final class TypingTouchTracker {
    private struct Finger {
        let id: ObjectIdentifier
        var key: TypingKeyHitTarget?
        var committed: Bool
        var ownsShift: Bool
        var ownsDeleteRepeat: Bool
        let order: UInt64
    }

    private var fingers: [ObjectIdentifier: Finger] = [:]
    private var nextOrder: UInt64 = 0

    public init() {}

    public var highlightedKeyIDs: Set<String> {
        Set(
            fingers.values.compactMap { finger in
                guard !finger.committed else { return nil }
                return finger.key?.id
            }
        )
    }

    public func began(id: ObjectIdentifier, key: TypingKeyHitTarget?) -> TypingTouchEffects {
        var effects = TypingTouchEffects()

        if let key, hasUncommittedFinger(on: key.id) {
            return effects
        }

        if key != nil {
            commitPendingCharacterKeys(into: &effects)
            stopForeignDeleteRepeats(into: &effects)
        }

        var finger = Finger(
            id: id,
            key: key,
            committed: false,
            ownsShift: false,
            ownsDeleteRepeat: false,
            order: nextOrder
        )
        nextOrder += 1

        if let key {
            effects.playFeedback = key
            activate(key, on: &finger, effects: &effects)
        }
        fingers[id] = finger
        return effects
    }

    public func moved(id: ObjectIdentifier, key: TypingKeyHitTarget?) -> TypingTouchEffects {
        guard var finger = fingers[id], !finger.committed else {
            return TypingTouchEffects()
        }
        if finger.key?.id == key?.id {
            return TypingTouchEffects()
        }

        var effects = TypingTouchEffects()
        if finger.ownsDeleteRepeat {
            effects.stopDeleteRepeat = true
            finger.ownsDeleteRepeat = false
        }

        finger.key = key
        if let key {
            effects.playFeedback = key
            activate(key, on: &finger, effects: &effects)
        }
        fingers[id] = finger
        return effects
    }

    public func ended(id: ObjectIdentifier, key: TypingKeyHitTarget?) -> TypingTouchEffects {
        guard let finger = fingers.removeValue(forKey: id) else {
            return TypingTouchEffects()
        }
        return finish(finger, hit: key, commitIfNeeded: true)
    }

    public func cancelled(id: ObjectIdentifier) -> TypingTouchEffects {
        guard let finger = fingers.removeValue(forKey: id) else {
            return TypingTouchEffects()
        }
        return finish(finger, hit: nil, commitIfNeeded: false)
    }

    // MARK: - Internals

    private func activate(
        _ key: TypingKeyHitTarget,
        on finger: inout Finger,
        effects: inout TypingTouchEffects
    ) {
        switch key.behavior {
        case .commitOnRelease:
            break
        case .deleteRepeat:
            effects.deleteFire = true
            effects.startDeleteRepeat = true
            finger.ownsDeleteRepeat = true
        case .shiftHold:
            if !finger.ownsShift, !fingers.values.contains(where: { $0.ownsShift }) {
                effects.beginShift = true
                finger.ownsShift = true
            }
        }
    }

    /// Press order = typing order: flush other uncommitted character keys.
    private func commitPendingCharacterKeys(into effects: inout TypingTouchEffects) {
        let pending = fingers.values
            .filter { !$0.committed && $0.key?.behavior == .commitOnRelease }
            .sorted { $0.order < $1.order }
        for finger in pending {
            if let key = finger.key {
                effects.commits.append(key)
            }
            fingers[finger.id]?.committed = true
        }
    }

    /// Holding delete + tapping a letter must stop the repeat.
    private func stopForeignDeleteRepeats(into effects: inout TypingTouchEffects) {
        for (id, finger) in fingers where finger.ownsDeleteRepeat {
            effects.stopDeleteRepeat = true
            fingers[id]?.ownsDeleteRepeat = false
        }
    }

    private func hasUncommittedFinger(on keyID: String) -> Bool {
        fingers.values.contains { !$0.committed && $0.key?.id == keyID }
    }

    private func finish(
        _ finger: Finger,
        hit: TypingKeyHitTarget?,
        commitIfNeeded: Bool
    ) -> TypingTouchEffects {
        var effects = TypingTouchEffects()
        if finger.ownsDeleteRepeat {
            effects.stopDeleteRepeat = true
        }
        if finger.ownsShift {
            effects.endShift = true
        }
        if commitIfNeeded, !finger.committed, let hit, hit.behavior == .commitOnRelease {
            effects.commits.append(hit)
        }
        return effects
    }
}
