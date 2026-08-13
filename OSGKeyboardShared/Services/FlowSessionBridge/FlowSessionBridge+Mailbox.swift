// FlowSessionBridge+Mailbox.swift
// OSGKeyboard · Shared

import Foundation

extension FlowSessionBridge {
    // MARK: - Typed Flow protocol

    /// Persists the latest command plus a bounded journal of the newest 12
    /// commands before notifying. Receivers replay by `commandSeq` for
    /// at-least-once handling and use that sequence as the idempotency key.
    public static func writeCommand(_ command: FlowCommand, defaults: UserDefaults? = nil) {
        let store = FlowSessionBridgeStorage.resolvedDefaults(defaults)
        if let data = FlowSessionBridgeStorage.encode(command) {
            store.set(data, forKey: FlowSessionKeys.flowCommandPayload)
        }
        var journal = FlowSessionBridgeStorage.decode(
            [FlowCommand].self,
            from: store.data(forKey: FlowSessionKeys.flowCommandJournalPayload)
        ) ?? []
        if !journal.contains(where: { $0.commandSeq == command.commandSeq }) {
            journal.append(command)
            journal.sort { $0.commandSeq < $1.commandSeq }
            journal = Array(journal.suffix(12))
            if let data = FlowSessionBridgeStorage.encode(journal) {
                store.set(data, forKey: FlowSessionKeys.flowCommandJournalPayload)
            }
        }
        FlowSessionBridgeStorage.flush(store)
        FlowSessionDarwin.postCommandChanged()
    }

    public static func latestCommand(defaults: UserDefaults? = nil) -> FlowCommand? {
        let store = FlowSessionBridgeStorage.resolvedDefaults(defaults)
        return FlowSessionBridgeStorage.decode(
            FlowCommand.self,
            from: store.data(forKey: FlowSessionKeys.flowCommandPayload)
        )
    }

    public static func commands(
        after commandSeq: Int64,
        defaults: UserDefaults? = nil
    ) -> [FlowCommand] {
        let store = FlowSessionBridgeStorage.resolvedDefaults(defaults)
        let journal = FlowSessionBridgeStorage.decode(
            [FlowCommand].self,
            from: store.data(forKey: FlowSessionKeys.flowCommandJournalPayload)
        ) ?? []
        return journal
            .filter { $0.commandSeq > commandSeq }
            .sorted { $0.commandSeq < $1.commandSeq }
    }

    public static func writeStartTransaction(
        _ transaction: FlowStartTransaction,
        defaults: UserDefaults? = nil
    ) {
        let store = FlowSessionBridgeStorage.resolvedDefaults(defaults)
        if let data = FlowSessionBridgeStorage.encode(transaction) {
            store.set(data, forKey: FlowSessionKeys.flowStartTransactionPayload)
        }
        FlowSessionBridgeStorage.flush(store)
    }

    public static func startTransaction(
        defaults: UserDefaults? = nil
    ) -> FlowStartTransaction? {
        let store = FlowSessionBridgeStorage.resolvedDefaults(defaults)
        return FlowSessionBridgeStorage.decode(
            FlowStartTransaction.self,
            from: store.data(forKey: FlowSessionKeys.flowStartTransactionPayload)
        )
    }

    public static func clearStartTransaction(defaults: UserDefaults? = nil) {
        let store = FlowSessionBridgeStorage.resolvedDefaults(defaults)
        store.removeObject(forKey: FlowSessionKeys.flowStartTransactionPayload)
        FlowSessionBridgeStorage.flush(store)
    }

    /// Publishes only forward progress for one utterance: a terminal status
    /// cannot regress to non-terminal, and non-nil revisions must increase.
    public static func writeResult(_ result: FlowResult, defaults: UserDefaults? = nil) {
        let store = FlowSessionBridgeStorage.resolvedDefaults(defaults)
        if let existing = FlowSessionBridgeStorage.decode(
            FlowResult.self,
            from: store.data(forKey: FlowSessionKeys.flowResultPayload)
        ), existing.sessionId == result.sessionId,
           existing.utteranceId == result.utteranceId,
           isTerminal(existing.status),
           !isTerminal(result.status) {
            return
        }
        if let existing = FlowSessionBridgeStorage.decode(
            FlowResult.self,
            from: store.data(forKey: FlowSessionKeys.flowResultPayload)
        ), existing.sessionId == result.sessionId,
           existing.utteranceId == result.utteranceId,
           let existingRevision = existing.revision,
           let incomingRevision = result.revision,
           incomingRevision <= existingRevision {
            return
        }
        if let data = FlowSessionBridgeStorage.encode(result) {
            store.set(data, forKey: FlowSessionKeys.flowResultPayload)
        }
        FlowSessionBridgeStorage.flush(store)
        FlowSessionDarwin.postTranscriptionChanged()
    }

    public static func latestResult(defaults: UserDefaults? = nil) -> FlowResult? {
        let store = FlowSessionBridgeStorage.resolvedDefaults(defaults)
        return FlowSessionBridgeStorage.decode(
            FlowResult.self,
            from: store.data(forKey: FlowSessionKeys.flowResultPayload)
        )
    }

    public static func clearResult(defaults: UserDefaults? = nil) {
        let store = FlowSessionBridgeStorage.resolvedDefaults(defaults)
        store.removeObject(forKey: FlowSessionKeys.flowResultPayload)
        FlowSessionBridgeStorage.flush(store)
    }

    public static func writeAck(_ ack: FlowAck, defaults: UserDefaults? = nil) {
        let store = FlowSessionBridgeStorage.resolvedDefaults(defaults)
        if let data = FlowSessionBridgeStorage.encode(ack) {
            store.set(data, forKey: FlowSessionKeys.flowAckPayload)
        }
        FlowSessionBridgeStorage.flush(store)
        FlowSessionDarwin.postTranscriptionChanged()
    }

    public static func latestAck(defaults: UserDefaults? = nil) -> FlowAck? {
        let store = FlowSessionBridgeStorage.resolvedDefaults(defaults)
        return FlowSessionBridgeStorage.decode(
            FlowAck.self,
            from: store.data(forKey: FlowSessionKeys.flowAckPayload)
        )
    }

    public static func setPendingKeyboardUtteranceId(
        _ id: UUID?,
        defaults: UserDefaults? = nil
    ) {
        let store = FlowSessionBridgeStorage.resolvedDefaults(defaults)
        if let id {
            store.set(id.uuidString, forKey: FlowSessionKeys.pendingKeyboardUtteranceId)
        } else {
            store.removeObject(forKey: FlowSessionKeys.pendingKeyboardUtteranceId)
        }
        FlowSessionBridgeStorage.flush(store)
    }

    public static func pendingKeyboardUtteranceId(defaults: UserDefaults? = nil) -> UUID? {
        let store = FlowSessionBridgeStorage.resolvedDefaults(defaults)
        guard let raw = store.string(forKey: FlowSessionKeys.pendingKeyboardUtteranceId) else {
            return nil
        }
        return UUID(uuidString: raw)
    }

    private static func isTerminal(_ status: FlowResult.Status) -> Bool {
        status == .final || status == .error || status == .aborted || status == .timeout
    }
}
