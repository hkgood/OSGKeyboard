// FlowBudgetAndMergeTests.swift
// OSGKeyboardTests
//
// Guards the cross-cutting invariants introduced by the reliability
// overhaul: timeout budgets derived from a single source, LWW clock
// clamping, and mutation-rebase for the speech history store.

import XCTest
@testable import OSGKeyboardShared

final class FlowBudgetAndMergeTests: XCTestCase {

    // MARK: - Timeout budget invariant

    /// The keyboard's post-stop watchdog must outlast the host's worst case
    /// (ASR drain wait + LLM polish cap) with real margin — otherwise the
    /// keyboard reports a timeout for transcriptions that are still going
    /// to succeed, and hand-tuned constants have drifted below the host
    /// maximum before.
    func testKeyboardResultTimeoutOutlastsHostWorstCase() {
        for engineMode in ["local", "cloud"] {
            let hostWorstCase = (engineMode == "local"
                ? FlowSessionKeys.localASRWaitTimeout
                : FlowSessionKeys.cloudASRWaitTimeout)
                + FlowSessionKeys.maxPolishTimeout
            let keyboardTimeout = FlowSessionKeys.keyboardResultTimeout(engineMode: engineMode)
            XCTAssertGreaterThanOrEqual(
                keyboardTimeout,
                hostWorstCase + 10,
                "keyboard watchdog (\(engineMode)) must exceed host worst case with margin"
            )
        }
    }

    // MARK: - SyncedField future-clock clamping

    func testMergePrefersGenuinelyNewerRemote() {
        let older = SyncedField(value: "a", updatedAt: Date(timeIntervalSinceNow: -100), deviceID: "A")
        let newer = SyncedField(value: "b", updatedAt: Date(timeIntervalSinceNow: -10), deviceID: "B")
        XCTAssertEqual(SyncedField.merge(local: older, remote: newer).value, "b")
        XCTAssertEqual(SyncedField.merge(local: newer, remote: older).value, "b")
    }

    /// A device with a clock years in the future must not win every merge
    /// forever: its timestamp is clamped to "now" for comparison, so an
    /// edit carrying a trusted (within-skew) later stamp still beats it —
    /// with unclamped LWW the year-ahead stamp would win against everything
    /// until that wall-clock date actually arrived.
    func testMergeClampsAbsurdFutureRemoteTimestamp() {
        let farFuture = Date().addingTimeInterval(365 * 24 * 3600)
        let brokenClock = SyncedField(value: "broken", updatedAt: farFuture, deviceID: "B")
        // Sane edit one minute ahead of now: inside the trusted skew window,
        // so it is NOT clamped — while the broken stamp collapses to ~now.
        let local = SyncedField(value: "sane", updatedAt: Date().addingTimeInterval(60), deviceID: "A")
        XCTAssertEqual(
            SyncedField.merge(local: local, remote: brokenClock).value,
            "sane",
            "a year-ahead stamp must lose to a trusted, genuinely newer edit"
        )
        XCTAssertEqual(
            SyncedField.merge(local: brokenClock, remote: local).value,
            "sane",
            "clamping must be symmetric regardless of which side is remote"
        )
    }

    /// The winner's untrusted future stamp must be REWRITTEN to now in the
    /// merged result — otherwise the stored far-future stamp keeps beating
    /// every later genuine edit until that wall-clock date arrives.
    func testMergeFlattensUntrustedWinnerStamp() {
        let farFuture = Date().addingTimeInterval(365 * 24 * 3600)
        let broken = SyncedField(value: "broken", updatedAt: farFuture, deviceID: "B")
        let old = SyncedField(value: "old", updatedAt: Date(timeIntervalSinceNow: -9999), deviceID: "A")
        let merged = SyncedField.merge(local: old, remote: broken)
        XCTAssertEqual(merged.value, "broken", "newer (clamped) edit still wins this merge")
        XCTAssertLessThan(
            merged.updatedAt.timeIntervalSinceNow, 60,
            "the far-future stamp must be flattened so later real edits can outrank it"
        )
    }

    func testMergeTrustsModestFutureSkew() {
        // Small forward skew (minutes) is normal clock drift and stays trusted.
        let slightlyAhead = SyncedField(value: "ahead", updatedAt: Date().addingTimeInterval(120), deviceID: "A")
        let past = SyncedField(value: "past", updatedAt: Date(timeIntervalSinceNow: -3600), deviceID: "B")
        XCTAssertEqual(SyncedField.merge(local: past, remote: slightlyAhead).value, "ahead")
    }

    // MARK: - History push byte budget

    /// A history that outgrew the KVS byte budget must be trimmed (oldest
    /// entries first) for upload, not fail forever — automatic pushes are
    /// fire-and-forget, so a throwing encode would silently kill sync with
    /// no recovery path short of clearing all history.
    @MainActor
    func testOversizedHistoryPushTrimsOldestEntriesToFitBudget() throws {
        let sync = SpeechHistoryCloudSync(
            kvs: FakeUbiquitousKeyValueStore(),
            makeStore: { AppGroupStore(defaults: self.makeDefaults()) },
            historyDefaults: { self.makeDefaults() }
        )

        // ~300 entries × ~2.4 KB ≈ 720 KB encoded — over the 400 KB budget.
        let filler = String(repeating: "很长的听写内容 long dictation text ", count: 80)
        let now = Date()
        var history = SyncedSpeechHistory.empty
        history.entries = (0..<300).map { index in
            SpeechHistoryEntry(
                text: "\(filler)#\(index)",
                createdAt: now.addingTimeInterval(TimeInterval(-index)),
                engineMode: "local"
            )
        }

        let data = try sync.encodeFittingBudget(history)
        XCTAssertLessThanOrEqual(data.count, SpeechHistoryCloudSync.maxPayloadBytes)

        let decoded = try sync.decode(data)
        XCTAssertFalse(decoded.entries.isEmpty)
        // Newest entries must survive the trim.
        XCTAssertTrue(decoded.entries.contains { $0.text.hasSuffix("#0") })
        XCTAssertFalse(decoded.entries.contains { $0.text.hasSuffix("#299") })
    }

    // MARK: - Insertion word-boundary hygiene

    func testInsertionSeparatorAddsSpaceBetweenLatinWords() {
        XCTAssertEqual(
            DictationTextComposer.insertionSeparator(previousContext: "Hello", insertion: "world"),
            " "
        )
        XCTAssertEqual(
            DictationTextComposer.insertionSeparator(previousContext: "version 2", insertion: "is out"),
            " "
        )
    }

    func testInsertionSeparatorSkipsWhitespaceCJKAndPunctuationBoundaries() {
        XCTAssertEqual(DictationTextComposer.insertionSeparator(previousContext: "Hello ", insertion: "world"), "")
        XCTAssertEqual(DictationTextComposer.insertionSeparator(previousContext: "line\n", insertion: "next"), "")
        XCTAssertEqual(DictationTextComposer.insertionSeparator(previousContext: "你好", insertion: "世界"), "")
        XCTAssertEqual(DictationTextComposer.insertionSeparator(previousContext: "说英文", insertion: "now"), "")
        XCTAssertEqual(DictationTextComposer.insertionSeparator(previousContext: "see (", insertion: "note"), "")
        XCTAssertEqual(DictationTextComposer.insertionSeparator(previousContext: "wait", insertion: ", then go"), "")
        XCTAssertEqual(DictationTextComposer.insertionSeparator(previousContext: nil, insertion: "fresh"), "")
        XCTAssertEqual(DictationTextComposer.insertionSeparator(previousContext: "", insertion: "fresh"), "")
    }

    // MARK: - SpeechHistoryStore rebase-before-mutation

    private func makeDefaults() -> UserDefaults {
        let suite = "group.com.osgkeyboard.shared.tests.history.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    /// Cloud pulls write merged history to disk and only *schedule* the
    /// in-memory reload. A mutation racing that reload must not wipe what
    /// the merge brought in.
    @MainActor
    func testAppendDoesNotEraseEntriesMergedToDiskBehindItsBack() {
        let defaults = makeDefaults()
        let store = SpeechHistoryStore(defaults: defaults)

        store.append(text: "本地第一条", engineMode: "local")
        XCTAssertEqual(store.entries.count, 1)

        // Simulate a cloud merge landing on disk without the store's
        // in-memory payload being reloaded yet.
        var onDisk = SpeechHistoryStorage.load(from: defaults)
        let remoteEntry = SpeechHistoryEntry(text: "远端合并进来的一条", engineMode: "cloud")
        onDisk.entries.append(remoteEntry)
        onDisk.updatedAt = Date()
        SpeechHistoryStorage.save(onDisk, to: defaults)

        // Mutate through the store — pre-fix this overwrote the disk state
        // with the stale in-memory payload, deleting the remote entry.
        store.append(text: "本地第二条", engineMode: "local")

        let persisted = SpeechHistoryStorage.load(from: defaults)
        XCTAssertTrue(
            persisted.entries.contains { $0.id == remoteEntry.id },
            "append must rebase on the persisted state instead of clobbering the cloud merge"
        )
        XCTAssertTrue(persisted.entries.contains { $0.text == "本地第二条" })
        XCTAssertTrue(persisted.entries.contains { $0.text == "本地第一条" })
    }

    @MainActor
    func testDeleteAfterExternalDiskMergeStillTombstones() {
        let defaults = makeDefaults()
        let store = SpeechHistoryStore(defaults: defaults)
        store.append(text: "要删除的一条", engineMode: "local")
        guard let target = store.entries.first else {
            return XCTFail("expected an entry")
        }

        // External merge adds an unrelated entry on disk.
        var onDisk = SpeechHistoryStorage.load(from: defaults)
        onDisk.entries.append(SpeechHistoryEntry(text: "外部条目", engineMode: "cloud"))
        onDisk.updatedAt = Date()
        SpeechHistoryStorage.save(onDisk, to: defaults)

        store.delete(id: target.id)

        let persisted = SpeechHistoryStorage.load(from: defaults)
        XCTAssertFalse(persisted.entries.contains { $0.id == target.id })
        XCTAssertNotNil(persisted.deletedEntryIDs[target.id], "delete must record a tombstone")
        XCTAssertTrue(persisted.entries.contains { $0.text == "外部条目" }, "external entry must survive")
    }
}
