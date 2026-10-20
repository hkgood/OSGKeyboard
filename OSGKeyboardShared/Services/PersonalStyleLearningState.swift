// PersonalStyleLearningState.swift
// OSGKeyboard · Shared
//
// Device-local memory that lets a personal style be relearned incrementally:
// the compacted evidence of the last saved generation and the corpus it has
// already absorbed. Dictation history keeps only a rolling window, so this is
// the only place older learning survives. It is never synced — a device
// without a matching record simply relearns from scratch.

import Foundation

/// Compacted stage-one evidence carried into the next generation.
public struct PolishStyleLearningPriorEvidence: Codable, Equatable, Sendable {
    public struct Domain: Codable, Equatable, Sendable {
        public let traits: [PolishStyleLearningEvidence.Trait]
        public let contradictions: [PolishStyleLearningEvidence.Contradiction]
    }

    public let asr: Domain
    public let reply: Domain
    /// Newest learned example timestamp. Only later examples count as new.
    public let learnedThrough: Date
    public let cumulativeASRExampleCount: Int
    public let cumulativeASREffectiveCharacterCount: Int
    public let cumulativeReplyExampleCount: Int
    public let cumulativeReplyFinalEditCount: Int
}

/// A reviewed pack plus the evidence to persist once the user saves it.
public struct PolishStyleLearningResult: Sendable {
    public let pack: PolishStylePack
    /// Nil when the generator produced no reusable evidence (fixtures).
    public let prior: PolishStyleLearningPriorEvidence?

    public init(pack: PolishStylePack, prior: PolishStyleLearningPriorEvidence?) {
        self.pack = pack
        self.prior = prior
    }
}

@MainActor
public final class PersonalStyleLearningStateStore {
    public static let shared = PersonalStyleLearningStateStore()

    private struct Record: Codable {
        let packID: String
        let generatedAt: Date
        let prior: PolishStyleLearningPriorEvidence
    }

    private static let storageKey = "personalStyle.learningState.v1"
    /// Cloud-merged metadata may round dates, so match within one second.
    private static let generatedAtTolerance: TimeInterval = 1

    private let defaults: UserDefaults?

    public init(defaults: UserDefaults? = AppGroup.defaultsIfAvailable) {
        self.defaults = defaults
    }

    /// Returns the prior only when it belongs to exactly this saved
    /// generation. A pack replaced elsewhere (another device, an older build)
    /// has a different `generatedAt` and falls back to full relearning.
    public func prior(for pack: PolishStylePack) -> PolishStyleLearningPriorEvidence? {
        guard let generatedAt = pack.learningMetadata?.generatedAt,
              let record = load(),
              record.packID == pack.id,
              abs(record.generatedAt.timeIntervalSince(generatedAt))
                <= Self.generatedAtTolerance else {
            return nil
        }
        return record.prior
    }

    /// Only one personal style is learned at a time, so a save replaces any
    /// earlier record.
    public func save(_ prior: PolishStyleLearningPriorEvidence, for pack: PolishStylePack) {
        guard let defaults,
              let generatedAt = pack.learningMetadata?.generatedAt,
              let data = try? JSONEncoder().encode(
                  Record(packID: pack.id, generatedAt: generatedAt, prior: prior)
              ) else {
            return
        }
        defaults.set(data, forKey: Self.storageKey)
    }

    public func clear() {
        defaults?.removeObject(forKey: Self.storageKey)
    }

    private func load() -> Record? {
        guard let data = defaults?.data(forKey: Self.storageKey) else { return nil }
        return try? JSONDecoder().decode(Record.self, from: data)
    }
}
