// ClipboardReplyFeedbackStore.swift
// OSGKeyboard · Shared
//
// Keeps a bounded, device-local record of explicit clipboard-reply choices.
// These model-generated candidates are comparative preference evidence, not
// user-authored corpus. The store is intentionally excluded from iCloud sync.

import Foundation

public struct ClipboardReplyCandidateSnapshot: Codable, Equatable, Identifiable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case ordinary
        case formal
        case playful
    }

    public let id: UUID
    public let kind: Kind
    public let text: String
    public let emotion: String

    public init(
        id: UUID = UUID(),
        kind: Kind,
        text: String,
        emotion: String
    ) {
        self.id = id
        self.kind = kind
        self.text = text
        self.emotion = emotion
    }
}

public struct ClipboardReplyFeedbackRecord: Codable, Equatable, Identifiable, Sendable {
    public enum Outcome: String, Codable, Sendable {
        case awaitingSelection
        case selected
        case discarded
    }

    public let id: UUID
    public let createdAt: Date
    public let sourceText: String
    public let candidates: [ClipboardReplyCandidateSnapshot]
    public let styleID: String?
    public var selectedCandidateID: UUID?
    public var answerID: UUID?
    public var outcome: Outcome
    public var finalText: String?
    public var finalRevision: Int64?

    public init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        sourceText: String,
        candidates: [ClipboardReplyCandidateSnapshot],
        styleID: String?,
        selectedCandidateID: UUID? = nil,
        answerID: UUID? = nil,
        outcome: Outcome = .awaitingSelection,
        finalText: String? = nil,
        finalRevision: Int64? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.sourceText = sourceText
        self.candidates = candidates
        self.styleID = styleID
        self.selectedCandidateID = selectedCandidateID
        self.answerID = answerID
        self.outcome = outcome
        self.finalText = finalText
        self.finalRevision = finalRevision
    }

    public var selectedCandidate: ClipboardReplyCandidateSnapshot? {
        guard let selectedCandidateID else { return nil }
        return candidates.first { $0.id == selectedCandidateID }
    }
}

@MainActor
public final class ClipboardReplyFeedbackStore {
    public static let shared = ClipboardReplyFeedbackStore()

    public static let maximumRecords = 100
    public static let retentionInterval: TimeInterval = 30 * 24 * 60 * 60
    public static let maximumSourceCharacters = 4_000
    public static let maximumCandidateCharacters = 1_500
    public static let maximumPayloadBytes = 512 * 1_024

    private static let storageKey = "clipboard.replyFeedback.v1"

    private let defaults: UserDefaults?

    public init(defaults: UserDefaults? = AppGroup.defaultsIfAvailable) {
        self.defaults = defaults
    }

    public func records(now: Date = Date()) -> [ClipboardReplyFeedbackRecord] {
        guard let defaults,
              let data = defaults.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode(
                  [ClipboardReplyFeedbackRecord].self,
                  from: data
              ) else {
            return []
        }
        let result = sanitized(decoded, now: now)
        if result != decoded {
            persist(result, now: now)
        }
        return result
    }

    /// Converts local records into the bounded comparative schema accepted by
    /// Personal Style V2. Awaiting rows are excluded because they contain no
    /// user decision.
    public func learningExamples(
        now: Date = Date()
    ) -> [PolishStyleReplyLearningExample] {
        records(now: now).compactMap { record in
            guard record.outcome != .awaitingSelection,
                  let ordinary = record.candidates.first(where: {
                      $0.kind == .ordinary
                  }) else {
                return nil
            }
            let selection: PolishStyleReplySelection
            if record.outcome == .discarded {
                selection = .discarded
            } else {
                guard let selected = record.selectedCandidate else { return nil }
                selection = learningSelection(for: selected.kind)
            }
            return PolishStyleReplyLearningExample(
                receivedMessage: record.sourceText,
                ordinaryCandidate: ordinary.text,
                formalCandidate: record.candidates.first(where: {
                    $0.kind == .formal
                })?.text,
                playfulCandidate: record.candidates.first(where: {
                    $0.kind == .playful
                })?.text,
                selection: selection,
                finalEdit: record.finalText,
                createdAt: record.createdAt,
                styleID: record.styleID
            )
        }
    }

    /// Starts a comparative feedback record after reply candidates have been
    /// generated. Returns nil when the source or any candidate is sensitive.
    @discardableResult
    public func begin(
        sourceText: String,
        candidates: [ClipboardReplyCandidateSnapshot],
        styleID: String?,
        now: Date = Date()
    ) -> UUID? {
        guard let source = acceptedBoundedText(
            sourceText,
            maximumCharacters: Self.maximumSourceCharacters
        ) else {
            return nil
        }
        let kinds = Set(candidates.map(\.kind))
        guard !candidates.isEmpty,
              candidates.count == kinds.count else {
            return nil
        }
        let sanitizedCandidates = candidates.compactMap { candidate
            -> ClipboardReplyCandidateSnapshot? in
            guard let text = acceptedBoundedText(
                candidate.text,
                maximumCharacters: Self.maximumCandidateCharacters
            ) else {
                return nil
            }
            return ClipboardReplyCandidateSnapshot(
                id: candidate.id,
                kind: candidate.kind,
                text: text,
                emotion: String(candidate.emotion.prefix(48))
            )
        }
        guard sanitizedCandidates.count == candidates.count else { return nil }

        let record = ClipboardReplyFeedbackRecord(
            createdAt: now,
            sourceText: source,
            candidates: sanitizedCandidates,
            styleID: normalizedStyleID(styleID)
        )
        var next = records(now: now)
        next.insert(record, at: 0)
        persist(next, now: now)
        return record.id
    }

    public func recordSelection(
        recordID: UUID,
        candidateID: UUID,
        answerID: UUID
    ) {
        var next = records()
        guard let index = next.firstIndex(where: { $0.id == recordID }),
              next[index].candidates.contains(where: { $0.id == candidateID }) else {
            return
        }
        next[index].selectedCandidateID = candidateID
        next[index].answerID = answerID
        next[index].outcome = .selected
        persist(next)
    }

    public func recordDiscard(recordID: UUID) {
        var next = records()
        guard let index = next.firstIndex(where: { $0.id == recordID }),
              next[index].outcome == .awaitingSelection else {
            return
        }
        next[index].outcome = .discarded
        persist(next)
    }

    /// Records only edits that OSGKeyboard can associate with the exact AI
    /// answer ID. Arbitrary host-app edits are intentionally not inferred.
    public func recordFinalEdit(
        answerID: UUID,
        text: String,
        revision: Int64
    ) {
        guard revision > 0,
              let finalText = acceptedBoundedText(
                  text,
                  maximumCharacters: Self.maximumCandidateCharacters
              ) else {
            return
        }
        var next = records()
        guard let index = next.firstIndex(where: { $0.answerID == answerID }),
              next[index].outcome == .selected else {
            return
        }
        next[index].finalText = finalText
        next[index].finalRevision = revision
        persist(next)
    }

    public func clear() {
        defaults?.removeObject(forKey: Self.storageKey)
    }

    private func acceptedBoundedText(
        _ raw: String,
        maximumCharacters: Int
    ) -> String? {
        guard let accepted = ClipboardHistoryPolicy.acceptedText(from: raw) else {
            return nil
        }
        return String(accepted.prefix(maximumCharacters))
    }

    private func normalizedStyleID(_ raw: String?) -> String? {
        let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? nil : String(value.prefix(128))
    }

    private func learningSelection(
        for kind: ClipboardReplyCandidateSnapshot.Kind
    ) -> PolishStyleReplySelection {
        switch kind {
        case .ordinary:
            return .ordinary
        case .formal:
            return .formal
        case .playful:
            return .playful
        }
    }

    private func sanitized(
        _ records: [ClipboardReplyFeedbackRecord],
        now: Date
    ) -> [ClipboardReplyFeedbackRecord] {
        let cutoff = now.addingTimeInterval(-Self.retentionInterval)
        return Array(
            records
                .filter { $0.createdAt >= cutoff && $0.createdAt <= now }
                .sorted { $0.createdAt > $1.createdAt }
                .prefix(Self.maximumRecords)
        )
    }

    private func persist(
        _ records: [ClipboardReplyFeedbackRecord],
        now: Date = Date()
    ) {
        guard let defaults else { return }
        var next = sanitized(records, now: now)
        var encoded = try? JSONEncoder().encode(next)
        while (encoded?.count ?? 0) > Self.maximumPayloadBytes, !next.isEmpty {
            next.removeLast()
            encoded = try? JSONEncoder().encode(next)
        }
        guard !next.isEmpty, let encoded else {
            defaults.removeObject(forKey: Self.storageKey)
            return
        }
        defaults.set(encoded, forKey: Self.storageKey)
    }
}
