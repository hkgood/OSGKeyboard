// CloudASRConnectionCheck.swift
// OSGKeyboard · Shared
//
// Settings "validate connection" probe shared by iOS and macOS.

import Foundation
#if canImport(OSGKeyboardShared)
import OSGKeyboardShared
#endif

public enum CloudASRConnectionCheck {
    /// Verifies the active cloud ASR client can connect + authenticate.
    ///
    /// Each backend decides how to probe (see `CloudASRTranscribing`):
    /// HTTP/batch providers transcribe a short silence clip and treat an
    /// empty transcript as success; Bailian / Volcengine / OpenAI Realtime
    /// handshake (and auth) only — silence clips make streaming backends fail.
    public static func validate(store: any ConfigurationStore) async throws {
        let client = CloudASRClientFactory.make(store: store)
        try await client.probeConnection()
    }
}
