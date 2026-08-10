// EditableInputReference.swift
// OSGKeyboard · Shared
//
// A short-lived, cross-process-safe reference to the last text the keyboard
// actually inserted. It is material for explicit voice editing, not history.

import Foundation

public struct EditableInputReference: Codable, Equatable, Sendable {
    public static let schemaVersion = 1
    public static let lifetime: TimeInterval = 10 * 60
    /// Initial safety budget. Device benchmarks may lower this value.
    public static let maxEditableGraphemes = 1_200

    public let schemaVersion: Int
    public let targetID: UUID
    public let historyEntryID: UUID?
    public let historyEntryRevision: Int64?
    public let pendingHistoryMutationID: UUID?
    public let displayText: String
    /// Exact host-field insertion, including any leading separator.
    public let insertedText: String
    public let postInsertionFingerprint: String?
    public let extensionInstanceID: UUID
    public let observedDocumentRevision: Int64
    public let createdAt: TimeInterval
    public let expiresAt: TimeInterval

    public init(
        targetID: UUID = UUID(),
        historyEntryID: UUID? = nil,
        historyEntryRevision: Int64? = nil,
        pendingHistoryMutationID: UUID? = nil,
        displayText: String,
        insertedText: String,
        postInsertionFingerprint: String?,
        extensionInstanceID: UUID,
        observedDocumentRevision: Int64 = 0,
        createdAt: TimeInterval = Date().timeIntervalSince1970
    ) {
        self.schemaVersion = Self.schemaVersion
        self.targetID = targetID
        self.historyEntryID = historyEntryID
        self.historyEntryRevision = historyEntryRevision
        self.pendingHistoryMutationID = pendingHistoryMutationID
        self.displayText = displayText
        self.insertedText = insertedText
        self.postInsertionFingerprint = postInsertionFingerprint
        self.extensionInstanceID = extensionInstanceID
        self.observedDocumentRevision = observedDocumentRevision
        self.createdAt = createdAt
        self.expiresAt = createdAt + Self.lifetime
    }

    public var isWithinLengthBudget: Bool {
        !displayText.isEmpty && displayText.count <= Self.maxEditableGraphemes
    }

    public func isExpired(at now: TimeInterval = Date().timeIntervalSince1970) -> Bool {
        now >= expiresAt
    }

    /// Rebuilt extensions must prove the entire insertion is still at the caret.
    public func isFullyVerified(
        contextBeforeInput: String?,
        fieldFingerprint: String?
    ) -> Bool {
        guard !isExpired(), isWithinLengthBudget,
              let contextBeforeInput,
              contextBeforeInput.hasSuffix(insertedText) else {
            return false
        }
        guard let expected = postInsertionFingerprint else { return true }
        return fieldFingerprint == expected
    }
}

public enum EditableInputReferenceStore {
    private static let key = "editLastInput.reference.v1"

    public static func load(
        defaults: UserDefaults? = nil,
        now: TimeInterval = Date().timeIntervalSince1970
    ) -> EditableInputReference? {
        guard let store = defaults ?? AppGroup.defaultsIfAvailable,
              let data = store.data(forKey: key),
              let reference = try? JSONDecoder().decode(EditableInputReference.self, from: data)
        else {
            return nil
        }
        guard !reference.isExpired(at: now) else {
            clear(defaults: store)
            return nil
        }
        return reference
    }

    public static func save(
        _ reference: EditableInputReference,
        defaults: UserDefaults? = nil
    ) {
        guard let store = defaults ?? AppGroup.defaultsIfAvailable,
              let data = try? JSONEncoder().encode(reference) else {
            return
        }
        store.set(data, forKey: key)
        store.synchronize()
    }

    public static func clear(defaults: UserDefaults? = nil) {
        guard let store = defaults ?? AppGroup.defaultsIfAvailable else { return }
        store.removeObject(forKey: key)
        store.synchronize()
    }
}
