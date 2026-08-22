// KeyboardSetupBridge.swift
// OSGKeyboard · Shared
//
// The main app cannot query iOS for installed keyboards. The extension
// reports when it has appeared with Full Access so onboarding can skip
// the manual setup step for returning users.

import CryptoKit
import Foundation

public struct OOBEPracticeSession: Codable, Equatable, Sendable {
    public let sessionID: UUID
    public let expectedFeature: ManagedGatewayOOBEFeature
    public let startedAt: Date
    public let expiresAt: Date

    public init(
        sessionID: UUID,
        expectedFeature: ManagedGatewayOOBEFeature,
        startedAt: Date,
        expiresAt: Date
    ) {
        self.sessionID = sessionID
        self.expectedFeature = expectedFeature
        self.startedAt = startedAt
        self.expiresAt = expiresAt
    }

    public func isActive(at now: Date) -> Bool {
        startedAt <= now && now < expiresAt
    }
}

public struct OOBEPracticeCompletion: Codable, Equatable, Sendable {
    public let sessionID: UUID
    public let feature: ManagedGatewayOOBEFeature
    public let timestamp: Date

    public init(sessionID: UUID, feature: ManagedGatewayOOBEFeature, timestamp: Date) {
        self.sessionID = sessionID
        self.feature = feature
        self.timestamp = timestamp
    }
}

public struct OOBEClipboardMaterial: Codable, Equatable, Sendable {
    public let sessionID: UUID
    public let text: String
    public let expiresAt: Date
    public let sha256: String

    public init(sessionID: UUID, text: String, expiresAt: Date, sha256: String) {
        self.sessionID = sessionID
        self.text = text
        self.expiresAt = expiresAt
        self.sha256 = sha256
    }
}

public enum KeyboardSetupBridge {
    private enum Key {
        static let fullAccessReady = "keyboard.extension.fullAccessReady"
        static let lastSeenAt = "keyboard.extension.lastSeenAt"
        static let onboardingPracticeExpiresAt = "keyboard.onboarding.practiceExpiresAt"
        static let lastVoiceInsertionAt = "keyboard.extension.lastVoiceInsertionAt"
        static let oobePracticeSession = "keyboard.onboarding.practiceSession.v2"
        static let oobePracticeCompletion = "keyboard.onboarding.practiceCompletion.v2"
        static let oobeClipboardMaterial = "keyboard.onboarding.clipboardMaterial.v1"
    }

    /// True when the keyboard extension last appeared with Full Access enabled.
    public static var isReadyForOnboardingSkip: Bool {
        isReadyForOnboardingSkip(defaults: nil)
    }

    public static func isReadyForOnboardingSkip(defaults: UserDefaults?) -> Bool {
        guard let store = defaults ?? AppGroup.defaultsIfAvailable else { return false }
        return store.bool(forKey: Key.fullAccessReady)
    }

    /// True after the extension has appeared at least once. Unlike
    /// `isReadyForOnboardingSkip`, this also covers an appearance without Full
    /// Access so the host can explain the missing setting precisely.
    public static var hasAppeared: Bool {
        hasAppeared(defaults: nil)
    }

    public static func hasAppeared(defaults: UserDefaults?) -> Bool {
        guard let store = defaults ?? AppGroup.defaultsIfAvailable else { return false }
        return store.double(forKey: Key.lastSeenAt) > 0
    }

    /// A short-lived exception that lets the real keyboard complete its first
    /// voice insertion while the host still owns the onboarding screen.
    public static var isOnboardingPracticeActive: Bool {
        onboardingPracticeIsActive()
    }

    public static var activeOOBEPracticeSession: OOBEPracticeSession? {
        oobePracticeSession()
    }

    /// Wall clock of the most recent voice insertion issued by the extension.
    /// The host compares this with the current practice start time, so an old
    /// insertion can never complete a new onboarding run.
    public static var lastVoiceInsertionAt: Date? {
        guard AppGroup.isAvailable else { return nil }
        let value = AppGroup.defaults.double(forKey: Key.lastVoiceInsertionAt)
        return value > 0 ? Date(timeIntervalSince1970: value) : nil
    }

    public static func onboardingPracticeIsActive(
        defaults: UserDefaults? = nil,
        now: Date = Date()
    ) -> Bool {
        guard let store = defaults ?? AppGroup.defaultsIfAvailable else { return false }
        if oobePracticeSession(defaults: store, now: now) != nil {
            return true
        }
        return store.double(forKey: Key.onboardingPracticeExpiresAt) > now.timeIntervalSince1970
    }

    public static func setOnboardingPracticeActive(
        _ active: Bool,
        duration: TimeInterval = 30 * 60,
        defaults: UserDefaults? = nil,
        now: Date = Date()
    ) {
        guard let store = defaults ?? AppGroup.defaultsIfAvailable else { return }
        if active {
            _ = beginOOBEPracticeSession(
                expectedFeature: .voiceInput,
                duration: duration,
                defaults: store,
                now: now
            )
            store.set(
                now.addingTimeInterval(duration).timeIntervalSince1970,
                forKey: Key.onboardingPracticeExpiresAt
            )
        } else {
            endOOBEPracticeSession(defaults: store)
        }
        AppGroupConfigDarwin.postConfigChanged()
    }

    /// Starts a host-owned OOBE session. The same session ID can be retained
    /// while the host advances through the four expected features.
    @discardableResult
    public static func beginOOBEPracticeSession(
        sessionID: UUID = UUID(),
        expectedFeature: ManagedGatewayOOBEFeature,
        duration: TimeInterval = 30 * 60,
        defaults: UserDefaults? = nil,
        now: Date = Date()
    ) -> OOBEPracticeSession? {
        guard duration > 0,
              let store = defaults ?? AppGroup.defaultsIfAvailable else {
            return nil
        }
        let session = OOBEPracticeSession(
            sessionID: sessionID,
            expectedFeature: expectedFeature,
            startedAt: now,
            expiresAt: now.addingTimeInterval(duration)
        )
        store.set(encode(session), forKey: Key.oobePracticeSession)
        store.removeObject(forKey: Key.oobePracticeCompletion)
        store.removeObject(forKey: Key.oobeClipboardMaterial)
        store.set(session.expiresAt.timeIntervalSince1970, forKey: Key.onboardingPracticeExpiresAt)
        store.synchronize()
        AppGroupConfigDarwin.postConfigChanged()
        return session
    }

    @discardableResult
    public static func updateOOBEExpectedFeature(
        _ feature: ManagedGatewayOOBEFeature,
        sessionID: UUID,
        duration: TimeInterval? = nil,
        defaults: UserDefaults? = nil,
        now: Date = Date()
    ) -> OOBEPracticeSession? {
        guard let store = defaults ?? AppGroup.defaultsIfAvailable,
              let current = oobePracticeSession(defaults: store, now: now),
              current.sessionID == sessionID else {
            return nil
        }
        let expiresAt = duration.map { now.addingTimeInterval(max($0, 0)) }
            ?? current.expiresAt
        guard expiresAt > now else {
            endOOBEPracticeSession(defaults: store)
            return nil
        }
        let updated = OOBEPracticeSession(
            sessionID: current.sessionID,
            expectedFeature: feature,
            startedAt: current.startedAt,
            expiresAt: expiresAt
        )
        store.set(encode(updated), forKey: Key.oobePracticeSession)
        store.removeObject(forKey: Key.oobePracticeCompletion)
        store.removeObject(forKey: Key.oobeClipboardMaterial)
        store.set(updated.expiresAt.timeIntervalSince1970, forKey: Key.onboardingPracticeExpiresAt)
        store.synchronize()
        AppGroupConfigDarwin.postConfigChanged()
        return updated
    }

    public static func oobePracticeSession(
        defaults: UserDefaults? = nil,
        now: Date = Date()
    ) -> OOBEPracticeSession? {
        guard let store = defaults ?? AppGroup.defaultsIfAvailable,
              let session = decode(
                  OOBEPracticeSession.self,
                  from: store.data(forKey: Key.oobePracticeSession)
              ) else {
            return nil
        }
        guard session.isActive(at: now) else {
            endOOBEPracticeSession(defaults: store, notify: false)
            return nil
        }
        return session
    }

    public static func endOOBEPracticeSession(defaults: UserDefaults? = nil) {
        guard let store = defaults ?? AppGroup.defaultsIfAvailable else { return }
        endOOBEPracticeSession(defaults: store, notify: true)
    }

    /// Records completion only when both session identity and expected feature
    /// still match. Stale extension callbacks cannot complete a later step.
    @discardableResult
    public static func markOOBEPracticeCompleted(
        sessionID: UUID,
        feature: ManagedGatewayOOBEFeature,
        defaults: UserDefaults? = nil,
        now: Date = Date()
    ) -> Bool {
        guard let store = defaults ?? AppGroup.defaultsIfAvailable,
              let session = oobePracticeSession(defaults: store, now: now),
              session.sessionID == sessionID,
              session.expectedFeature == feature else {
            return false
        }
        let completion = OOBEPracticeCompletion(
            sessionID: sessionID,
            feature: feature,
            timestamp: now
        )
        store.set(encode(completion), forKey: Key.oobePracticeCompletion)
        store.synchronize()
        AppGroupConfigDarwin.postConfigChanged()
        return true
    }

    public static func oobePracticeCompletion(
        sessionID: UUID,
        feature: ManagedGatewayOOBEFeature,
        defaults: UserDefaults? = nil,
        now: Date = Date()
    ) -> OOBEPracticeCompletion? {
        guard let store = defaults ?? AppGroup.defaultsIfAvailable,
              let session = oobePracticeSession(defaults: store, now: now),
              session.sessionID == sessionID,
              session.expectedFeature == feature,
              let completion = decode(
                  OOBEPracticeCompletion.self,
                  from: store.data(forKey: Key.oobePracticeCompletion)
              ),
              completion.sessionID == sessionID,
              completion.feature == feature,
              completion.timestamp >= session.startedAt,
              completion.timestamp <= session.expiresAt else {
            return nil
        }
        return completion
    }

    /// Seeds only host-provided demo text for reply/translate practice. This
    /// bypasses clipboard history entirely and cannot expose any other item.
    @discardableResult
    public static func seedOOBEClipboardMaterial(
        _ text: String,
        sessionID: UUID,
        duration: TimeInterval = 10 * 60,
        defaults: UserDefaults? = nil,
        now: Date = Date()
    ) -> OOBEClipboardMaterial? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let store = defaults ?? AppGroup.defaultsIfAvailable,
              let session = oobePracticeSession(defaults: store, now: now),
              session.sessionID == sessionID,
              session.expectedFeature == .clipboardTranslate
                || session.expectedFeature == .clipboardReply else {
            return nil
        }
        let expiresAt = min(session.expiresAt, now.addingTimeInterval(max(duration, 0)))
        guard expiresAt > now else { return nil }
        let material = OOBEClipboardMaterial(
            sessionID: sessionID,
            text: trimmed,
            expiresAt: expiresAt,
            sha256: digest(trimmed)
        )
        store.set(encode(material), forKey: Key.oobeClipboardMaterial)
        store.synchronize()
        AppGroupConfigDarwin.postConfigChanged()
        return material
    }

    public static func oobeClipboardMaterial(
        sessionID: UUID,
        defaults: UserDefaults? = nil,
        now: Date = Date()
    ) -> String? {
        guard let store = defaults ?? AppGroup.defaultsIfAvailable else {
            return nil
        }
        guard let session = oobePracticeSession(defaults: store, now: now),
              session.sessionID == sessionID,
              let material = decode(
                  OOBEClipboardMaterial.self,
                  from: store.data(forKey: Key.oobeClipboardMaterial)
              ),
              material.sessionID == sessionID,
              material.expiresAt > now,
              material.expiresAt <= session.expiresAt,
              material.sha256 == digest(material.text) else {
            store.removeObject(forKey: Key.oobeClipboardMaterial)
            return nil
        }
        return material.text
    }

    /// Called from the keyboard extension on each appearance.
    public static func markExtensionAppearance(
        hasFullAccess: Bool,
        defaults: UserDefaults? = nil,
        now: Date = Date()
    ) {
        guard let store = defaults ?? AppGroup.defaultsIfAvailable else { return }
        store.set(now.timeIntervalSince1970, forKey: Key.lastSeenAt)
        store.set(hasFullAccess, forKey: Key.fullAccessReady)
        // Flush before notifying the host so its immediate refresh cannot race
        // the cross-process preferences write.
        store.synchronize()
        AppGroupConfigDarwin.postConfigChanged()
    }

    /// Called only after a Flow transcript has been inserted into the host
    /// field, not when recognition merely produced a result.
    public static func markVoiceInsertion() {
        guard AppGroup.isAvailable else { return }
        AppGroup.defaults.set(
            Date().timeIntervalSince1970,
            forKey: Key.lastVoiceInsertionAt
        )
        AppGroupConfigDarwin.postConfigChanged()
    }

    private static func endOOBEPracticeSession(
        defaults: UserDefaults,
        notify: Bool
    ) {
        defaults.removeObject(forKey: Key.onboardingPracticeExpiresAt)
        defaults.removeObject(forKey: Key.oobePracticeSession)
        defaults.removeObject(forKey: Key.oobePracticeCompletion)
        defaults.removeObject(forKey: Key.oobeClipboardMaterial)
        defaults.synchronize()
        if notify {
            AppGroupConfigDarwin.postConfigChanged()
        }
    }

    private static func encode<Value: Encodable>(_ value: Value) -> Data? {
        try? JSONEncoder().encode(value)
    }

    private static func decode<Value: Decodable>(
        _ type: Value.Type,
        from data: Data?
    ) -> Value? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func digest(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
