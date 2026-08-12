// FlowSessionBridge+Lifecycle.swift
// OSGKeyboard · Shared

import Foundation

extension FlowSessionBridge {
    public static func writeReadySnapshot(_ snapshot: FlowReadySnapshot, defaults: UserDefaults? = nil) {
        let store = FlowSessionBridgeStorage.resolvedDefaults(defaults)
        if let data = FlowSessionBridgeStorage.encode(snapshot) {
            store.set(data, forKey: FlowSessionKeys.flowReadyPayload)
        }
        if snapshot.ready {
            store.set(true, forKey: FlowSessionKeys.flowHostReady)
            if let readyAt = snapshot.readyAt {
                store.set(readyAt, forKey: FlowSessionKeys.flowHostReadyAt)
            }
        } else {
            // Keep the not-ready payload. The keyboard needs `reason`
            // (recording / processing / waitingForAudioProof / …) to tell
            // "host is busy" apart from "host is still starting". Deleting
            // the payload here forced every mid-utterance ready=false into
            // a permanent orange `preparingSession` state.
            clearHostReady(defaults: store, notify: false)
        }
        // PiP sessions are persistent; clear expiry left by older Live Activity builds.
        store.removeObject(forKey: FlowSessionKeys.flowSessionExpires)
        // Only a genuinely live host — ready, or actively serving an
        // utterance — may refresh the heartbeat here. A host stuck in a
        // failed cold start would otherwise keep "reviving" itself on every
        // engine-state flap, flickering the keyboard between reachable and
        // dead and postponing zombie-state cleanup indefinitely.
        let provesHostAlive = snapshot.ready
            || snapshot.reason == .recording
            || snapshot.reason == .processing
        if provesHostAlive {
            store.set(snapshot.heartbeatAt, forKey: FlowSessionKeys.flowHeartbeat)
        }
        FlowSessionBridgeStorage.flush(store)
        FlowSessionDarwin.postHostReadyChanged()
    }

    public static func readySnapshot(defaults: UserDefaults? = nil) -> FlowReadySnapshot? {
        let store = FlowSessionBridgeStorage.resolvedDefaults(defaults)
        return FlowSessionBridgeStorage.decode(
            FlowReadySnapshot.self,
            from: store.data(forKey: FlowSessionKeys.flowReadyPayload)
        )
    }

    // MARK: - Session lifecycle (host app)

    /// PiP keep-alive: session stays valid until explicit teardown.
    public static func markSessionActivePersistent(
        sessionId: UUID? = nil,
        defaults: UserDefaults? = nil
    ) {
        let store = FlowSessionBridgeStorage.resolvedDefaults(defaults)
        let now = Date().timeIntervalSince1970
        store.set(true, forKey: FlowSessionKeys.flowSessionActive)
        store.removeObject(forKey: FlowSessionKeys.flowSessionExpires)
        store.set(now, forKey: FlowSessionKeys.lastActivityAt)
        writeHeartbeat(defaults: store)
        clearTranscription(defaults: store)
        store.removeObject(forKey: FlowSessionKeys.flowCommandPayload)
        store.removeObject(forKey: FlowSessionKeys.flowCommandJournalPayload)
        store.removeObject(forKey: FlowSessionKeys.flowResultPayload)
        store.removeObject(forKey: FlowSessionKeys.flowAckPayload)
        store.removeObject(forKey: FlowSessionKeys.flowStartTransactionPayload)
        store.removeObject(forKey: FlowSessionKeys.pendingKeyboardUtteranceId)
        if let sessionId {
            let snapshot = FlowReadySnapshot(
                sessionId: sessionId,
                ready: false,
                reason: .starting,
                heartbeatAt: now,
                engineMode: AppGroupConfiguration.load(fromAvailable: store).engineMode,
                localeId: AppGroupConfiguration.load(fromAvailable: store).localeId,
                sessionExpiresAt: nil,
                hostGeneration: store.string(forKey: FlowSessionKeys.hostGeneration)
            )
            if let data = FlowSessionBridgeStorage.encode(snapshot) {
                store.set(data, forKey: FlowSessionKeys.flowReadyPayload)
            }
        } else {
            store.removeObject(forKey: FlowSessionKeys.flowReadyPayload)
        }
        FlowSessionBridgeStorage.flush(store)
    }

    public static func markSessionInactive(defaults: UserDefaults? = nil) {
        let store = FlowSessionBridgeStorage.resolvedDefaults(defaults)
        store.set(false, forKey: FlowSessionKeys.flowSessionActive)
        store.removeObject(forKey: FlowSessionKeys.flowSessionExpires)
        store.removeObject(forKey: FlowSessionKeys.flowHeartbeat)
        clearTranscription(defaults: store)
        store.removeObject(forKey: FlowSessionKeys.flowCommandPayload)
        store.removeObject(forKey: FlowSessionKeys.flowCommandJournalPayload)
        store.removeObject(forKey: FlowSessionKeys.flowResultPayload)
        store.removeObject(forKey: FlowSessionKeys.flowAckPayload)
        store.removeObject(forKey: FlowSessionKeys.flowStartTransactionPayload)
        store.removeObject(forKey: FlowSessionKeys.pendingKeyboardUtteranceId)
        store.removeObject(forKey: FlowSessionKeys.flowReadyPayload)
        clearHostReady(defaults: store, notify: false)
        FlowSessionBridgeStorage.flush(store)
    }

    public static func writeHeartbeat(defaults: UserDefaults? = nil) {
        let store = FlowSessionBridgeStorage.resolvedDefaults(defaults)
        let now = Date().timeIntervalSince1970
        store.set(now, forKey: FlowSessionKeys.flowHeartbeat)
        if store.bool(forKey: FlowSessionKeys.flowHostReady) {
            store.set(now, forKey: FlowSessionKeys.flowHostReadyAt)
        }
        FlowSessionBridgeStorage.flush(store)
    }

    // MARK: - Host return (scheme D)

    public static func setPendingHostBundleId(_ bundleId: String?, defaults: UserDefaults? = nil) {
        let store = FlowSessionBridgeStorage.resolvedDefaults(defaults)
        if let bundleId, !bundleId.isEmpty {
            store.set(bundleId, forKey: FlowSessionKeys.pendingHostBundleId)
        } else {
            store.removeObject(forKey: FlowSessionKeys.pendingHostBundleId)
        }
        FlowSessionBridgeStorage.flush(store)
    }

    public static func pendingHostBundleId(defaults: UserDefaults? = nil) -> String? {
        let store = FlowSessionBridgeStorage.resolvedDefaults(defaults)
        return store.string(forKey: FlowSessionKeys.pendingHostBundleId)
    }

    public static func clearPendingHostBundleId(defaults: UserDefaults? = nil) {
        setPendingHostBundleId(nil, defaults: defaults)
    }

    /// True when a recent keyboard `startflow` arm should not be repeated.
    public static func isPiPArmInCooldown(defaults: UserDefaults? = nil) -> Bool {
        let store = FlowSessionBridgeStorage.resolvedDefaults(defaults)
        let last = store.double(forKey: FlowSessionKeys.lastPiPArmAttemptAt)
        guard last > 0 else { return false }
        return Date().timeIntervalSince1970 - last < FlowSessionKeys.pipArmCooldown
    }

    public static func markPiPArmAttempt(defaults: UserDefaults? = nil) {
        let store = FlowSessionBridgeStorage.resolvedDefaults(defaults)
        store.set(Date().timeIntervalSince1970, forKey: FlowSessionKeys.lastPiPArmAttemptAt)
        FlowSessionBridgeStorage.flush(store)
    }

    // MARK: - Session validity (keyboard)

    /// True while the persistent PiP session contract is active.
    /// Does **not** mean the host can accept utterances — use `isHostReady()`.
    public static func isSessionActive(defaults: UserDefaults? = nil) -> Bool {
        let store = FlowSessionBridgeStorage.resolvedDefaults(defaults)
        return store.bool(forKey: FlowSessionKeys.flowSessionActive)
    }

    /// Seconds since the host last wrote `flowHeartbeat`; nil when never written.
    public static func heartbeatStaleness(defaults: UserDefaults? = nil) -> TimeInterval? {
        let store = FlowSessionBridgeStorage.resolvedDefaults(defaults)
        let heartbeat = store.double(forKey: FlowSessionKeys.flowHeartbeat)
        guard heartbeat > 0 else { return nil }
        return Date().timeIntervalSince1970 - heartbeat
    }

    /// True when the host app recently wrote a heartbeat (foreground or
    /// actively processing). Use for zombie / disconnect detection — **not**
    /// for mic-ready UI; prefer `isHostReady()`.
    public static func isHostReachable(defaults: UserDefaults? = nil) -> Bool {
        let store = FlowSessionBridgeStorage.resolvedDefaults(defaults)
        guard isSessionActive(defaults: store) else { return false }
        guard let staleness = heartbeatStaleness(defaults: store) else { return false }
        return staleness <= FlowSessionKeys.heartbeatStaleInterval
    }

    // MARK: - Host process generation

    /// Host app: rotate the per-process generation token. Call exactly once,
    /// as early as possible in the host launch path. Returns the previous
    /// generation (nil on first-ever launch) so the caller can log it.
    ///
    /// Rationale: `applicationWillTerminate` is best-effort — it never runs
    /// when a *suspended* app is force-quit (the common case after a failed
    /// cold start). Instead of anchoring cleanup on a termination callback
    /// that may not fire, each launch proves the previous process is dead and
    /// voids whatever session state it left behind.
    @discardableResult
    public static func rotateHostGeneration(defaults: UserDefaults? = nil) -> String? {
        let store = FlowSessionBridgeStorage.resolvedDefaults(defaults)
        let previous = store.string(forKey: FlowSessionKeys.hostGeneration)
        store.set(UUID().uuidString, forKey: FlowSessionKeys.hostGeneration)
        FlowSessionBridgeStorage.flush(store)
        return previous
    }

    public static func currentHostGeneration(defaults: UserDefaults? = nil) -> String? {
        let store = FlowSessionBridgeStorage.resolvedDefaults(defaults)
        return store.string(forKey: FlowSessionKeys.hostGeneration)
    }

    /// Host launch reconciliation: clear every piece of persisted session
    /// state a previous (dead) generation left behind. Unlike
    /// `clearFlowState()` this keeps `pendingHostBundleId` — on a keyboard
    /// `startflow` cold launch the scene delegate stores the host bundle id
    /// *before* the SwiftUI hierarchy (and thus the session manager) exists,
    /// and wiping it here would break the return-to-host affordance.
    public static func clearFlowStateOnHostLaunch(defaults: UserDefaults? = nil) {
        let store = FlowSessionBridgeStorage.resolvedDefaults(defaults)
        store.set(false, forKey: FlowSessionKeys.flowSessionActive)
        store.removeObject(forKey: FlowSessionKeys.flowSessionExpires)
        store.removeObject(forKey: FlowSessionKeys.flowHeartbeat)
        store.removeObject(forKey: FlowSessionKeys.keyboardRecordingState)
        store.removeObject(forKey: FlowSessionKeys.flowCommandPayload)
        store.removeObject(forKey: FlowSessionKeys.flowCommandJournalPayload)
        store.removeObject(forKey: FlowSessionKeys.flowResultPayload)
        store.removeObject(forKey: FlowSessionKeys.flowAckPayload)
        store.removeObject(forKey: FlowSessionKeys.flowStartTransactionPayload)
        store.removeObject(forKey: FlowSessionKeys.pendingKeyboardUtteranceId)
        store.removeObject(forKey: FlowSessionKeys.flowReadyPayload)
        clearTranscription(defaults: store)
        store.removeObject(forKey: FlowSessionKeys.audioLevels)
        store.removeObject(forKey: FlowSessionKeys.lastActivityAt)
        clearHostReady(defaults: store, notify: false)
        // Previous generation may have died mid Rime/CLM/ASR with hostHeavy=1.
        clearHostHeavy(defaults: store)
        FlowSessionBridgeStorage.flush(store)
    }

    // MARK: - Host ready contract (host app → keyboard)

    /// Host app: publish whether Flow can accept a new utterance right now.
    public static func setHostReady(
        _ ready: Bool,
        defaults: UserDefaults? = nil,
        notify: Bool = true
    ) {
        let store = FlowSessionBridgeStorage.resolvedDefaults(defaults)
        if ready {
            let now = Date().timeIntervalSince1970
            store.set(true, forKey: FlowSessionKeys.flowHostReady)
            store.set(now, forKey: FlowSessionKeys.flowHostReadyAt)
            writeHeartbeat(defaults: store)
        } else {
            clearHostReady(defaults: store, notify: false)
        }
        FlowSessionBridgeStorage.flush(store)
        if notify {
            FlowSessionDarwin.postHostReadyChanged()
        }
    }

    /// Host is compiling CLM / deploying Rime / warming ASR — extension must
    /// avoid stacking typing-engine RSS on top.
    public static func setHostHeavy(_ heavy: Bool, defaults: UserDefaults? = nil) {
        let store = FlowSessionBridgeStorage.resolvedDefaults(defaults)
        if heavy {
            store.set(true, forKey: FlowSessionKeys.hostHeavy)
            store.set(Date().timeIntervalSince1970, forKey: FlowSessionKeys.hostHeavyAt)
        } else {
            clearHostHeavy(defaults: store)
        }
        FlowSessionBridgeStorage.flush(store)
        OSGDiag.log("hostHeavy=\(heavy ? 1 : 0) \(OSGDiag.memoryTag())", category: "flow")
    }

    /// True only while the host recently marked itself busy. A sticky `true`
    /// left by a dead host (no `setHostHeavy(false)`) expires after
    /// `hostHeavyMaxAge` so typing 中文/EN is not silently blocked forever.
    public static func isHostHeavy(defaults: UserDefaults? = nil) -> Bool {
        let store = FlowSessionBridgeStorage.resolvedDefaults(defaults)
        guard store.bool(forKey: FlowSessionKeys.hostHeavy) else { return false }
        let markedAt = store.double(forKey: FlowSessionKeys.hostHeavyAt)
        // Legacy writes had the bool but no timestamp — treat as stale so a
        // pre-fix sticky flag cannot brick typing after upgrade.
        guard markedAt > 0 else {
            clearHostHeavy(defaults: store)
            FlowSessionBridgeStorage.flush(store)
            OSGDiag.log("hostHeavy stale missingAt — cleared \(OSGDiag.memoryTag())", category: "flow")
            return false
        }
        let age = Date().timeIntervalSince1970 - markedAt
        guard age >= 0, age <= FlowSessionKeys.hostHeavyMaxAge else {
            clearHostHeavy(defaults: store)
            FlowSessionBridgeStorage.flush(store)
            OSGDiag.log(
                "hostHeavy stale age=\(Int(age))s — cleared \(OSGDiag.memoryTag())",
                category: "flow"
            )
            return false
        }
        return true
    }

    private static func clearHostHeavy(defaults: UserDefaults) {
        defaults.set(false, forKey: FlowSessionKeys.hostHeavy)
        defaults.removeObject(forKey: FlowSessionKeys.hostHeavyAt)
    }

    /// True when the host has published a fresh ready contract (stricter than heartbeat alone).
    public static func isHostReady(defaults: UserDefaults? = nil) -> Bool {
        let store = FlowSessionBridgeStorage.resolvedDefaults(defaults)
        if let snapshot = readySnapshot(defaults: store) {
            guard snapshot.ready else { return false }
            // Snapshot written by a dead host generation → void immediately,
            // without waiting out the heartbeat-zombie window.
            if let snapshotGeneration = snapshot.hostGeneration,
               let currentGeneration = store.string(forKey: FlowSessionKeys.hostGeneration),
               snapshotGeneration != currentGeneration {
                return false
            }
            guard isHostReachable(defaults: store) else { return false }
            if let readyAt = snapshot.readyAt {
                let skew = abs(snapshot.heartbeatAt - readyAt)
                guard skew <= FlowSessionKeys.hostReadyMaxHeartbeatSkew else { return false }
            }
            return true
        }
        guard isHostReachable(defaults: store) else { return false }
        return store.bool(forKey: FlowSessionKeys.flowHostReady)
    }

    private static func clearHostReady(defaults: UserDefaults, notify: Bool) {
        defaults.removeObject(forKey: FlowSessionKeys.flowHostReady)
        defaults.removeObject(forKey: FlowSessionKeys.flowHostReadyAt)
        if notify {
            FlowSessionDarwin.postHostReadyChanged()
        }
    }

    /// True when the session contract flag is still set but the host heartbeat
    /// proves the process is gone (reboot, force-quit, long suspend).
    public static func isHostStale(
        staleAfter: TimeInterval = FlowSessionKeys.heartbeatZombieInterval,
        defaults: UserDefaults? = nil
    ) -> Bool {
        let store = FlowSessionBridgeStorage.resolvedDefaults(defaults)
        guard isSessionActive(defaults: store) else { return false }
        guard let staleness = heartbeatStaleness(defaults: store) else { return true }
        return staleness > staleAfter
    }

    /// Clears orphaned App Group Flow state when the host is provably dead.
    @discardableResult
    public static func clearIfHostStale(
        staleAfter: TimeInterval = FlowSessionKeys.heartbeatZombieInterval,
        defaults: UserDefaults? = nil
    ) -> Bool {
        guard isHostStale(staleAfter: staleAfter, defaults: defaults) else { return false }
        clearFlowState(defaults: defaults)
        return true
    }

    /// Clear pending result/error before a new utterance.
    public static func clearPendingTranscription(defaults: UserDefaults? = nil) {
        let store = FlowSessionBridgeStorage.resolvedDefaults(defaults)
        clearTranscription(defaults: store)
        FlowSessionBridgeStorage.flush(store)
    }

    public static func clearFlowState(defaults: UserDefaults? = nil) {
        let store = FlowSessionBridgeStorage.resolvedDefaults(defaults)
        store.set(false, forKey: FlowSessionKeys.flowSessionActive)
        store.removeObject(forKey: FlowSessionKeys.flowSessionExpires)
        store.removeObject(forKey: FlowSessionKeys.flowHeartbeat)
        store.removeObject(forKey: FlowSessionKeys.keyboardRecordingState)
        store.removeObject(forKey: FlowSessionKeys.transcriptionLanguage)
        store.removeObject(forKey: FlowSessionKeys.flowCommandPayload)
        store.removeObject(forKey: FlowSessionKeys.flowCommandJournalPayload)
        store.removeObject(forKey: FlowSessionKeys.flowResultPayload)
        store.removeObject(forKey: FlowSessionKeys.flowAckPayload)
        store.removeObject(forKey: FlowSessionKeys.flowStartTransactionPayload)
        store.removeObject(forKey: FlowSessionKeys.pendingKeyboardUtteranceId)
        store.removeObject(forKey: FlowSessionKeys.flowReadyPayload)
        clearTranscription(defaults: store)
        store.removeObject(forKey: FlowSessionKeys.audioLevels)
        store.removeObject(forKey: FlowSessionKeys.pendingHostBundleId)
        store.removeObject(forKey: FlowSessionKeys.lastActivityAt)
        clearHostReady(defaults: store, notify: false)
        clearHostHeavy(defaults: store)
        FlowSessionBridgeStorage.flush(store)
    }

    private static func clearTranscription(defaults: UserDefaults) {
        defaults.removeObject(forKey: FlowSessionKeys.transcriptionResult)
        defaults.removeObject(forKey: FlowSessionKeys.transcriptionPartial)
        defaults.removeObject(forKey: FlowSessionKeys.transcriptionPolishWarning)
        defaults.removeObject(forKey: FlowSessionKeys.transcriptionError)
        defaults.removeObject(forKey: FlowSessionKeys.transcriptionErrorKind)
    }
}
