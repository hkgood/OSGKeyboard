// CloudASRConnectionCheck.swift
// OSGKeyboard · HostSupport
//
// Settings "validate connection" probe shared by iOS and macOS.

import Foundation
#if canImport(OSGKeyboardShared)
import OSGKeyboardShared
#endif

public enum CloudASRConnectionCheck {
    /// Overall wall-clock budget for a connection check. The probe requests set
    /// `URLRequest.timeoutInterval` (~90 s), but that is an *idle* timeout that
    /// resets on every byte and never fires when a provider accepts the socket
    /// then stalls or trickles a keep-alive — leaving the settings spinner
    /// turning forever. This hard deadline guarantees the check returns.
    public static let probeTimeout: TimeInterval = 30

    /// Verifies the active cloud ASR client can connect + authenticate.
    ///
    /// Each backend decides how to probe (see `CloudASRTranscribing`):
    /// HTTP/batch providers transcribe a short silence clip and treat an
    /// empty transcript as success; Bailian / Volcengine / OpenAI Realtime
    /// handshake (and auth) only — silence clips make streaming backends fail.
    public static func validate(store: any ConfigurationStore) async throws {
        let client = CloudASRClientFactory.make(store: store)
        do {
            try await HardTimeout.run(seconds: probeTimeout) {
                try await client.probeConnection()
            }
        } catch is HardTimeoutError {
            throw CloudASRError.timedOut
        }
    }
}
