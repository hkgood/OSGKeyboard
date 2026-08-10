// EditTransactionStore.swift
// OSGKeyboard · Shared
//
// Durable commit records for field edits and eventual history synchronization.

import Foundation

public struct HistoryMutation: Codable, Equatable, Sendable, Identifiable {
    public enum Action: String, Codable, Sendable {
        case update
        case restore
        case delete
        case append
    }

    public enum UsageCategory: String, Codable, Sendable {
        case ai
    }

    public let id: UUID
    public let sequence: Int64
    public let action: Action
    public let entryID: UUID
    public let expectedRevision: Int64?
    public let text: String?
    public let engineMode: String?
    public let source: SpeechHistoryEntry.Source?
    public let usageCategory: UsageCategory?
    public let createdAt: TimeInterval

    public init(
        id: UUID = UUID(),
        sequence: Int64 = Int64(Date().timeIntervalSince1970 * 1_000),
        action: Action,
        entryID: UUID,
        expectedRevision: Int64? = nil,
        text: String? = nil,
        engineMode: String? = nil,
        source: SpeechHistoryEntry.Source? = nil,
        usageCategory: UsageCategory? = nil,
        createdAt: TimeInterval = Date().timeIntervalSince1970
    ) {
        self.id = id
        self.sequence = sequence
        self.action = action
        self.entryID = entryID
        self.expectedRevision = expectedRevision
        self.text = text
        self.engineMode = engineMode
        self.source = source
        self.usageCategory = usageCategory
        self.createdAt = createdAt
    }
}

public enum HistoryMutationOutbox {
    private static let key = "editLastInput.historyMutations.v1"
    public static func enqueue(
        _ mutation: HistoryMutation,
        defaults: UserDefaults? = nil
    ) {
        guard let store = defaults ?? AppGroup.defaultsIfAvailable else { return }
        var mutations = pending(defaults: store)
        guard !mutations.contains(where: { $0.id == mutation.id }) else { return }
        mutations.append(mutation)
        persist(mutations.sorted { $0.sequence < $1.sequence }, store: store)
    }

    public static func pending(defaults: UserDefaults? = nil) -> [HistoryMutation] {
        guard let store = defaults ?? AppGroup.defaultsIfAvailable,
              store.synchronize(),
              let data = store.data(forKey: key),
              let decoded = try? JSONDecoder().decode([HistoryMutation].self, from: data)
        else {
            return []
        }
        return decoded.sorted { $0.sequence < $1.sequence }
    }

    public static func acknowledge(
        _ mutationID: UUID,
        defaults: UserDefaults? = nil
    ) {
        guard let store = defaults ?? AppGroup.defaultsIfAvailable else { return }
        let remaining = pending(defaults: store).filter { $0.id != mutationID }
        persist(remaining, store: store)
    }

    private static func persist(_ mutations: [HistoryMutation], store: UserDefaults) {
        if mutations.isEmpty {
            store.removeObject(forKey: key)
        } else if let data = try? JSONEncoder().encode(mutations) {
            store.set(data, forKey: key)
        }
        store.synchronize()
    }
}

public struct HistoryMutationReceipt: Codable, Equatable, Sendable {
    public let mutationID: UUID
    public let entryID: UUID?
    public let revision: Int64?
    public let appliedAt: TimeInterval

    public init(
        mutationID: UUID,
        entryID: UUID?,
        revision: Int64?,
        appliedAt: TimeInterval = Date().timeIntervalSince1970
    ) {
        self.mutationID = mutationID
        self.entryID = entryID
        self.revision = revision
        self.appliedAt = appliedAt
    }
}

public enum HistoryMutationReceiptStore {
    private static let key = "editLastInput.historyMutationReceipts.v1"

    public static func save(
        _ receipt: HistoryMutationReceipt,
        defaults: UserDefaults? = nil
    ) {
        guard let store = defaults ?? AppGroup.defaultsIfAvailable else { return }
        var receipts = all(defaults: store)
        receipts[receipt.mutationID] = receipt
        if receipts.count > 64 {
            let keep = receipts.values
                .sorted { $0.appliedAt > $1.appliedAt }
                .prefix(64)
            receipts = Dictionary(uniqueKeysWithValues: keep.map { ($0.mutationID, $0) })
        }
        if let data = try? JSONEncoder().encode(receipts) {
            store.set(data, forKey: key)
            store.synchronize()
        }
    }

    public static func receipt(
        for mutationID: UUID,
        defaults: UserDefaults? = nil
    ) -> HistoryMutationReceipt? {
        all(defaults: defaults)[mutationID]
    }

    private static func all(
        defaults: UserDefaults? = nil
    ) -> [UUID: HistoryMutationReceipt] {
        guard let store = defaults ?? AppGroup.defaultsIfAvailable else { return [:] }
        store.synchronize()
        guard let data = store.data(forKey: key) else { return [:] }
        return (try? JSONDecoder().decode(
            [UUID: HistoryMutationReceipt].self,
            from: data
        )) ?? [:]
    }
}

public struct PendingTextEditTransaction: Codable, Equatable, Sendable {
    public enum DeliveryMode: String, Codable, Sendable {
        case replace
        case append
    }

    public enum Phase: String, Codable, Sendable {
        case prepared
        case fieldApplied
        case committed
    }

    public let transactionID: UUID
    public let deliveryMode: DeliveryMode
    public let beforeText: String
    public let afterText: String
    /// Exact string inserted into the field, including a computed separator.
    public var appliedInsertedText: String?
    public let expectedFieldFingerprint: String?
    public let historyMutation: HistoryMutation
    public var phase: Phase
    public let createdAt: TimeInterval

    public init(
        transactionID: UUID = UUID(),
        deliveryMode: DeliveryMode,
        beforeText: String,
        afterText: String,
        appliedInsertedText: String? = nil,
        expectedFieldFingerprint: String?,
        historyMutation: HistoryMutation,
        phase: Phase = .prepared,
        createdAt: TimeInterval = Date().timeIntervalSince1970
    ) {
        self.transactionID = transactionID
        self.deliveryMode = deliveryMode
        self.beforeText = beforeText
        self.afterText = afterText
        self.appliedInsertedText = appliedInsertedText
        self.expectedFieldFingerprint = expectedFieldFingerprint
        self.historyMutation = historyMutation
        self.phase = phase
        self.createdAt = createdAt
    }
}

public enum PendingTextEditTransactionStore {
    private static let key = "editLastInput.pendingTransaction.v1"

    public static func load(defaults: UserDefaults? = nil) -> PendingTextEditTransaction? {
        guard let store = defaults ?? AppGroup.defaultsIfAvailable,
              let data = store.data(forKey: key) else {
            return nil
        }
        return try? JSONDecoder().decode(PendingTextEditTransaction.self, from: data)
    }

    public static func save(
        _ transaction: PendingTextEditTransaction,
        defaults: UserDefaults? = nil
    ) {
        guard let store = defaults ?? AppGroup.defaultsIfAvailable,
              let data = try? JSONEncoder().encode(transaction) else {
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
