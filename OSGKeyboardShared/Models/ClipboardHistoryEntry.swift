// ClipboardHistoryEntry.swift
// OSGKeyboard · Shared
//
// One persisted clipboard history row (plain text / Unicode emoji only).

import Foundation

public struct ClipboardHistoryEntry: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var text: String
    public var createdAt: Date
    /// Pasteboard changeCount when this row was captured (best-effort).
    public var changeCount: Int?

    public init(
        id: UUID = UUID(),
        text: String,
        createdAt: Date = Date(),
        changeCount: Int? = nil
    ) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
        self.changeCount = changeCount
    }
}
