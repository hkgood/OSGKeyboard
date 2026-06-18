// PolishingService.swift
// OSGKeyboard · Shared
//
// Takes raw ASR transcript and runs it through the user's configured LLM
// to produce polished, well-punctuated text. Falls back to the raw transcript
// if the LLM call fails or times out.
//
// Mode-aware: when `modeId == "off"` the service short-circuits and returns
// the trimmed input without touching the network. This is the runtime
// guarantee behind the keyboard's "Off · 关闭" mode.

import Foundation

public actor PolishingService {

    public enum PolishError: Error, Equatable {
        case noTranscript
        case timeout
        case modeOff
    }

    private let store: AppGroupStore
    private let timeout: TimeInterval
    /// Optional injected client (mostly for testing). When nil we build
    /// one from `store.makeClient()` per call.
    private let injectedClient: LLMClient?

    /// Default `timeout` is `LLMClient.requestTimeout + 1` second so the
    /// safety-net `withThrowingTaskGroup` never wins the race against
    /// the URL request itself; if the request times out cleanly the
    /// network error reaches us first. The +1 is the single point of
    /// slack between the two clocks — keep it here, not in `LLMClient`.
    public init(
        store: AppGroupStore = AppGroupStore(),
        client: LLMClient? = nil,
        timeout: TimeInterval? = nil
    ) {
        self.store = store
        self.injectedClient = client
        self.timeout = timeout ?? (LLMClientFactory.defaultRequestTimeout + 1)
    }

    public func polish(_ raw: String) async throws -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw PolishError.noTranscript }

        // Mode-aware short-circuit. When the user has selected "Off", the
        // keyboard must never hit the network — we return the trimmed
        // input as-is. This is the same value the view controller would
        // produce if it skipped `polish()` entirely, but having the
        // guarantee at the service layer means future call sites (CLI,
        // tests, alternate keyboards) inherit it for free.
        if store.modeId == "off" {
            return trimmed
        }

        let client = injectedClient ?? store.makeClient()
        let prompt = store.systemPrompt

        return try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                try await client.polish(trimmed, systemPrompt: prompt)
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(self.timeout * 1_000_000_000))
                throw PolishError.timeout
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
}