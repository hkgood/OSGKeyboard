// SpeechHistoryEntry.swift
// OSGKeyboard · Shared
//
// A single voice transcription in the cross-device history log.

import Foundation

public struct SpeechHistoryEntry: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let text: String
    public let createdAt: Date
    /// iOS Flow engine mode; nil on macOS captures.
    public let engineMode: String?

    public init(
        id: UUID = UUID(),
        text: String,
        createdAt: Date = Date(),
        engineMode: String? = nil
    ) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
        self.engineMode = engineMode
    }

    /// First-line preview for compact list rows (macOS history sidebar).
    public var previewTitle: String {
        let firstLine = text.split(separator: "\n").first.map(String.init) ?? text
        return firstLine.count > 36 ? String(firstLine.prefix(36)) + "…" : firstLine
    }
}
