// PolishingService.swift
// OSGKeyboard · Keyboard Extension
//
// Takes raw ASR transcript and runs it through the user's configured LLM
// to produce polished, well-punctuated text. Falls back to the raw transcript
// if the LLM call fails or times out.

import Foundation
import OSGKeyboardShared

public actor PolishingService {

    public enum PolishError: Error {
        case noTranscript
        case timeout
    }

    private let store: AppGroupStore
    private let timeout: TimeInterval

    public init(store: AppGroupStore = AppGroupStore(), timeout: TimeInterval = 8) {
        self.store = store
        self.timeout = timeout
    }

    public func polish(_ raw: String) async throws -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw PolishError.noTranscript }

        let client = store.makeClient()
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
