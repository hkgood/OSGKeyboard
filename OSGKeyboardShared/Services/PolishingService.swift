// PolishingService.swift
// OSGKeyboard · Shared
//
// Takes raw ASR transcript and runs it through the user's configured LLM
// to produce polished, well-punctuated text. Falls back to the raw transcript
// if the LLM call fails or times out.
//
// Engine matrix:
//   - `engineMode == "cloud"`  → always polish (cloud engine's whole point).
//   - `engineMode == "local"`,
//     `localModeCloudPolishEnabled == false` → ASR-only, return raw.
//   - `engineMode == "local"`,
//     `localModeCloudPolishEnabled == true`  → polish via the user's LLM
//     (DeepSeek by default). The local engine gains stronger accuracy on
//     noisy / dialectal Chinese at the cost of one cloud round-trip.
//     If the user hasn't entered an API key the call falls back to the
//     raw transcript and surfaces a warning so the keyboard can show
//     the "fill in your key" hint.

import Foundation

public actor PolishingService {

    public enum PolishError: Error, Equatable {
        case noTranscript
        case timeout
        /// v0.2.0: local engine + cloud-polish-on, but the user hasn't
        /// saved an API key in the Keychain. Caller surfaces an Alert
        /// telling them to fill it in; we deliver the raw transcript
        /// so no data is lost.
        case missingAPIKey
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

        // Local engine: ASR-only unless the user opted into cloud
        // polish via `localModeCloudPolishEnabled`. The cloud polish
        // path still requires an API key; if the Keychain is empty we
        // fall back to the raw transcript and throw `missingAPIKey`
        // so the UI can surface the "fill in your key" hint.
        if store.engineMode == "local" {
            guard store.localModeCloudPolishEnabled else { return trimmed }
            guard !store.apiKey.isEmpty else {
                throw PolishError.missingAPIKey
            }
            return try await polishRemote(trimmed)
        }

        return try await polishRemote(trimmed)
    }

    private func polishRemote(_ trimmed: String) async throws -> String {
        let client = injectedClient ?? store.makeClient()
        let prompt = store.systemPrompt
        let budget = effectiveTimeout(for: trimmed)

        return try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                try await client.polish(trimmed, systemPrompt: prompt)
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(budget * 1_000_000_000))
                throw PolishError.timeout
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    /// Scale polish budget with transcript length (3-minute Flow utterances).
    private func effectiveTimeout(for text: String) -> TimeInterval {
        let scaled = timeout + (Double(text.count) / 200.0) * 2.0
        return min(max(scaled, timeout), 120)
    }
}
