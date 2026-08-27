// ClipboardReplyFeedbackStoreTests.swift
// OSGKeyboardTests

@testable import OSGKeyboardShared
import XCTest

@MainActor
final class ClipboardReplyFeedbackStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var store: ClipboardReplyFeedbackStore!

    override func setUp() {
        super.setUp()
        suiteName = "group.com.osgkeyboard.reply-feedback.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        store = ClipboardReplyFeedbackStore(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testSelectionAndVerifiedFinalEditAreRecorded() throws {
        let candidates = makeCandidates()
        let recordID = try XCTUnwrap(
            store.begin(
                sourceText: "周六下午去看展吗？",
                candidates: candidates,
                styleID: "user.personal"
            )
        )
        let answerID = UUID()

        store.recordSelection(
            recordID: recordID,
            candidateID: candidates[2].id,
            answerID: answerID
        )
        store.recordFinalEdit(
            answerID: answerID,
            text: "可以呀，几点出发？🙂",
            revision: 1
        )

        let record = try XCTUnwrap(store.records().first)
        XCTAssertEqual(record.outcome, .selected)
        XCTAssertEqual(record.selectedCandidate?.kind, .playful)
        XCTAssertEqual(record.answerID, answerID)
        XCTAssertEqual(record.finalText, "可以呀，几点出发？🙂")
        XCTAssertEqual(record.finalRevision, 1)
    }

    func testUnverifiedOrUnrelatedEditIsIgnored() throws {
        let candidates = makeCandidates()
        let recordID = try XCTUnwrap(
            store.begin(
                sourceText: "今晚要不要一起吃饭？",
                candidates: candidates,
                styleID: nil
            )
        )
        let answerID = UUID()
        store.recordSelection(
            recordID: recordID,
            candidateID: candidates[0].id,
            answerID: answerID
        )

        store.recordFinalEdit(answerID: UUID(), text: "无关修改", revision: 1)
        store.recordFinalEdit(answerID: answerID, text: "零版本", revision: 0)

        let record = try XCTUnwrap(store.records().first)
        XCTAssertNil(record.finalText)
        XCTAssertNil(record.finalRevision)
    }

    func testSensitiveSourceOrCandidateIsRejected() {
        let candidates = makeCandidates()

        XCTAssertNil(
            store.begin(
                sourceText: "123456",
                candidates: candidates,
                styleID: nil
            )
        )
        var unsafeCandidates = candidates
        unsafeCandidates[0] = ClipboardReplyCandidateSnapshot(
            kind: .ordinary,
            text: "Bearer abcdefghijklmnopqrstuvwxyz",
            emotion: "neutral"
        )
        XCTAssertNil(
            store.begin(
                sourceText: "普通消息",
                candidates: unsafeCandidates,
                styleID: nil
            )
        )
        XCTAssertTrue(store.records().isEmpty)
    }

    func testDuplicateCandidateKindsAreRejected() {
        let duplicate = [
            ClipboardReplyCandidateSnapshot(
                kind: .ordinary,
                text: "第一条",
                emotion: "neutral"
            ),
            ClipboardReplyCandidateSnapshot(
                kind: .ordinary,
                text: "第二条",
                emotion: "warm"
            )
        ]

        XCTAssertNil(
            store.begin(
                sourceText: "普通消息",
                candidates: duplicate,
                styleID: nil
            )
        )
    }

    func testRecordsAreCappedAndExpiredLocally() {
        let now = Date()
        for offset in 0..<(ClipboardReplyFeedbackStore.maximumRecords + 5) {
            _ = store.begin(
                sourceText: "消息\(offset)",
                candidates: makeCandidates(suffix: "\(offset)"),
                styleID: nil,
                now: now.addingTimeInterval(TimeInterval(offset))
            )
        }

        XCTAssertEqual(
            store.records(
                now: now.addingTimeInterval(
                    TimeInterval(ClipboardReplyFeedbackStore.maximumRecords + 5)
                )
            ).count,
            ClipboardReplyFeedbackStore.maximumRecords
        )

        XCTAssertTrue(
            store.records(
                now: now.addingTimeInterval(
                    ClipboardReplyFeedbackStore.retentionInterval + 1_000
                )
            ).isEmpty
        )
    }

    func testDiscardDoesNotCreatePositiveSelectionEvidence() throws {
        let recordID = try XCTUnwrap(
            store.begin(
                sourceText: "你怎么看？",
                candidates: makeCandidates(),
                styleID: nil
            )
        )

        store.recordDiscard(recordID: recordID)

        let record = try XCTUnwrap(store.records().first)
        XCTAssertEqual(record.outcome, .discarded)
        XCTAssertNil(record.selectedCandidateID)
        XCTAssertNil(record.answerID)
        XCTAssertEqual(store.learningExamples().first?.selection, .discarded)
    }

    func testAIHistoryRevisionBackfillsVerifiedFinalText() throws {
        let candidates = makeCandidates()
        let recordID = try XCTUnwrap(
            store.begin(
                sourceText: "这版可以直接发吗？",
                candidates: candidates,
                styleID: "user.personal"
            )
        )
        let answerID = UUID()
        store.recordSelection(
            recordID: recordID,
            candidateID: candidates[0].id,
            answerID: answerID
        )
        let history = SpeechHistoryStore(
            defaults: defaults,
            replyFeedbackStore: store
        )
        _ = history.applyHistoryMutation(
            HistoryMutation(
                action: .append,
                entryID: answerID,
                text: candidates[0].text,
                source: .ai
            )
        )

        _ = history.applyHistoryMutation(
            HistoryMutation(
                action: .update,
                entryID: answerID,
                expectedRevision: 0,
                text: "我再看一下这版，确认后回复你。"
            )
        )

        let record = try XCTUnwrap(store.records().first)
        XCTAssertEqual(record.finalText, "我再看一下这版，确认后回复你。")
        XCTAssertEqual(record.finalRevision, 1)
    }

    func testSingleOrdinaryAcceptanceRemainsWeakLearningEvidence() throws {
        let candidate = ClipboardReplyCandidateSnapshot(
            kind: .ordinary,
            text: "我先看一下，再回复你。",
            emotion: "neutral"
        )
        let recordID = try XCTUnwrap(
            store.begin(
                sourceText: "这个方案可以吗？",
                candidates: [candidate],
                styleID: nil
            )
        )
        store.recordSelection(
            recordID: recordID,
            candidateID: candidate.id,
            answerID: candidate.id
        )

        let example = try XCTUnwrap(store.learningExamples().first)
        XCTAssertEqual(example.selection, .ordinary)
        XCTAssertEqual(example.ordinaryCandidate, candidate.text)
        XCTAssertNil(example.formalCandidate)
        XCTAssertNil(example.playfulCandidate)
    }

    private func makeCandidates(
        suffix: String = ""
    ) -> [ClipboardReplyCandidateSnapshot] {
        [
            ClipboardReplyCandidateSnapshot(
                kind: .ordinary,
                text: "普通回复\(suffix)",
                emotion: "neutral"
            ),
            ClipboardReplyCandidateSnapshot(
                kind: .formal,
                text: "正式回复\(suffix)",
                emotion: "professional"
            ),
            ClipboardReplyCandidateSnapshot(
                kind: .playful,
                text: "趣味回复\(suffix) 🙂",
                emotion: "playful"
            )
        ]
    }
}
