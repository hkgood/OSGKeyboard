// SpeechHistoryEntry.swift
// OSGKeyboard · Shared
//
// A single voice transcription in the cross-device history log.

import Foundation

public struct SpeechHistoryEntry: Codable, Identifiable, Equatable, Sendable {
    public enum Source: String, Codable, Equatable, Sendable {
        case dictation
        case ai
    }

    public let id: UUID
    /// Final text delivered to the host app and shown in history.
    public let text: String
    /// ASR transcript after deterministic correction but before LLM polishing.
    /// Stored for future speaking-style learning and intentionally not shown.
    public let prePolishText: String?
    /// Translation outputs must not be treated as same-language style examples.
    public let wasTranslation: Bool
    /// Style active when the final text was produced; nil for legacy or AI rows.
    public let polishStyleID: String?
    /// SHA-256 key into `SyncedSpeechHistory.polishStylePromptSnapshots`.
    /// Deduplication preserves the exact prompt without repeating it per row.
    public let polishStylePromptFingerprint: String?
    public let createdAt: Date
    /// Last content mutation. Legacy rows default to `createdAt`.
    public let modifiedAt: Date
    /// Monotonic per-entry revision used to merge edits across devices.
    public let revision: Int64
    /// iOS Flow engine mode; nil on macOS captures.
    public let engineMode: String?
    /// Origin of the inserted text. Legacy rows decode as normal dictation.
    public let source: Source

    public init(
        id: UUID = UUID(),
        text: String,
        prePolishText: String? = nil,
        wasTranslation: Bool = false,
        polishStyleID: String? = nil,
        polishStylePromptFingerprint: String? = nil,
        createdAt: Date = Date(),
        modifiedAt: Date? = nil,
        revision: Int64 = 0,
        engineMode: String? = nil,
        source: Source = .dictation
    ) {
        self.id = id
        self.text = text
        let trimmedPrePolishText = prePolishText?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.prePolishText = trimmedPrePolishText?.isEmpty == false
            ? trimmedPrePolishText
            : nil
        self.wasTranslation = wasTranslation
        self.polishStyleID = polishStyleID
        self.polishStylePromptFingerprint = polishStylePromptFingerprint
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt ?? createdAt
        self.revision = revision
        self.engineMode = engineMode
        self.source = source
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        text = try container.decode(String.self, forKey: .text)
        prePolishText = try container.decodeIfPresent(String.self, forKey: .prePolishText)
        wasTranslation = try container.decodeIfPresent(Bool.self, forKey: .wasTranslation) ?? false
        polishStyleID = try container.decodeIfPresent(String.self, forKey: .polishStyleID)
        polishStylePromptFingerprint = try container.decodeIfPresent(
            String.self,
            forKey: .polishStylePromptFingerprint
        )
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        modifiedAt = try container.decodeIfPresent(Date.self, forKey: .modifiedAt) ?? createdAt
        revision = try container.decodeIfPresent(Int64.self, forKey: .revision) ?? 0
        engineMode = try container.decodeIfPresent(String.self, forKey: .engineMode)
        source = try container.decodeIfPresent(Source.self, forKey: .source) ?? .dictation
    }

    /// First-line preview for compact list rows (macOS history sidebar).
    public var previewTitle: String {
        let firstLine = text.split(separator: "\n").first.map(String.init) ?? text
        return firstLine.count > 36 ? String(firstLine.prefix(36)) + "…" : firstLine
    }
}
