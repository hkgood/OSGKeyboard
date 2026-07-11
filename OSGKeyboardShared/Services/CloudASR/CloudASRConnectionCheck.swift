// CloudASRConnectionCheck.swift
// OSGKeyboard · Shared
//
// Settings "validate connection" probe shared by iOS and macOS.

import Foundation

public enum CloudASRConnectionCheck {
    /// Verifies the active cloud ASR client can connect + authenticate.
    ///
    /// Each backend decides how to probe (see `CloudASRTranscribing`):
    /// HTTP/batch providers transcribe a short silence clip and treat an
    /// empty transcript as success; DashScope realtime only handshakes to
    /// `task-started` (pushing fake audio makes it fail with `emptyAudio`).
    public static func validate(store: any ConfigurationStore) async throws {
        let client = CloudASRClientFactory.make(store: store)
        try await client.probeConnection()
    }
}
