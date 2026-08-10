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
    public let text: String
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
        createdAt: Date = Date(),
        modifiedAt: Date? = nil,
        revision: Int64 = 0,
        engineMode: String? = nil,
        source: Source = .dictation
    ) {
        self.id = id
        self.text = text
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
