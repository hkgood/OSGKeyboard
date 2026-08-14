// RimeEngineBridging.swift
// OSGKeyboard · Shared
//
// Engine façade for the typing surface. `LibrimeEngine` is the production
// implementation; the protocol keeps SwiftUI independent of the C runtime.

import Foundation

/// Input language for the typing surface (not ASR locale).
public enum TypingInputLanguage: String, CaseIterable, Identifiable, Sendable {
    case chinese
    case english

    public var id: String { rawValue }

    public var shortLabel: String {
        switch self {
        case .chinese: return "中"
        case .english: return "英"
        }
    }
}

/// Role of an English QuickType slot. Chinese candidates stay `.completion`.
public enum TypingCandidateRole: String, Equatable, Sendable {
    /// The word currently being typed. Space does not replace it.
    case verbatim
    /// The unique slot Space will apply when autocorrect is armed.
    case correction
    /// Prefix completion; tap to accept, Space ignores it.
    case completion
    /// Next-word prediction after a committed word; tap to insert.
    case nextWord
}

/// One candidate row item after composing.
public struct TypingCandidate: Identifiable, Equatable, Sendable {
    public let id: String
    public let text: String
    public let annotation: String?
    /// Absolute engine index for Chinese selection (may differ from display order).
    public let engineIndex: Int
    public let role: TypingCandidateRole
    /// Unknown verbatim shown in quotes, matching the system / KeyboardKit contract.
    public let isQuoted: Bool

    public init(
        id: String = UUID().uuidString,
        text: String,
        annotation: String? = nil,
        engineIndex: Int = 0,
        role: TypingCandidateRole = .completion,
        isQuoted: Bool = false
    ) {
        self.id = id
        self.text = text
        self.annotation = annotation
        self.engineIndex = engineIndex
        self.role = role
        self.isQuoted = isQuoted
    }
}

/// Snapshot the UI observes while composing.
public struct TypingComposition: Equatable, Sendable {
    public var preedit: String
    /// Raw key sequence from the engine (ASCII). Prefer this over `preedit`
    /// for spelling / next-key logic — preedit may include separators.
    public var rawInput: String
    public var candidates: [TypingCandidate]

    public init(
        preedit: String = "",
        rawInput: String = "",
        candidates: [TypingCandidate] = []
    ) {
        self.preedit = preedit
        self.rawInput = rawInput
        self.candidates = candidates
    }

    public static let empty = TypingComposition()
}

/// Bridge between key events and IME state. Keep this small so Phase 2
/// can swap KeyboardKit-style shells or librime without UI rewrites.
@MainActor
public protocol RimeEngineBridging: AnyObject {
    var composition: TypingComposition { get }
    var isReady: Bool { get }
    var schema: TypingInputSchema { get }

    /// Load dictionaries / open session. Safe to call repeatedly.
    func prepare() async throws
    /// Drop heavy caches (leave typing mode / memory warning).
    func teardown()

    func setLanguage(_ language: TypingInputLanguage)
    @discardableResult
    func setSchema(_ schema: TypingInputSchema) -> Bool
    /// Process one key and return newly committed text, if any.
    func processCharacter(_ character: Character) -> String?
    func processBackspace() -> String?
    func processSpace() -> String?
    func processReturn() -> String?
    /// Commit candidate at index; returns text to insert (empty if invalid).
    func selectCandidate(at index: Int) -> String
    /// Force-commit current preedit as raw latin (or empty).
    func flushPreedit() -> String
    func clearComposition()
}
