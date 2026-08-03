// TypingSessionController.swift
// OSGKeyboard · Shared
//
// Owns the typing-surface engine + layout provider. Injected into the
// keyboard extension; torn down when leaving typing mode.

import Foundation
import Combine

@MainActor
public final class TypingSessionController: ObservableObject {
    @Published public private(set) var language: TypingInputLanguage = .chinese
    @Published public private(set) var page: TypingKeyPage = .letters
    @Published public private(set) var shiftActive: Bool = false
    @Published public private(set) var capsLock: Bool = false
    @Published public private(set) var composition: TypingComposition = .empty
    @Published public private(set) var engineReady: Bool = false
    @Published public private(set) var schema: TypingInputSchema
    @Published public var lastError: String?

    public let layout: TypingLayoutProviding
    private let engine: RimeEngineBridging
    private var prepared = false

    public init(
        engine: RimeEngineBridging = LibrimeEngine(),
        layout: TypingLayoutProviding = StandardTypingLayout()
    ) {
        self.engine = engine
        self.layout = layout
        schema = engine.schema
    }

    public var keyRows: [[String]] {
        var rows = layout.rows(for: page, shiftActive: shiftActive || capsLock)
        if page == .letters,
           language == .chinese,
           schema != .fullPinyin,
           rows.indices.contains(2),
           rows[2].first == "⇧" {
            // Microsoft/Sogou use semicolon for "ing"; Chinese composition
            // does not need Shift, so keep the standard row width stable.
            rows[2][0] = ";"
        }
        return rows
    }

    public func enterTypingMode() {
        TypingInputConfiguration.shared.reload()
        Task { await prepareIfNeeded() }
    }

    public func leaveTypingMode() {
        engine.teardown()
        prepared = false
        engineReady = false
        composition = .empty
        page = .letters
        shiftActive = false
        capsLock = false
    }

    public func toggleLanguage() -> String {
        let next: TypingInputLanguage = language == .chinese ? .english : .chinese
        return setLanguage(next)
    }

    /// Selects a specific language for the shared voice / Chinese / English
    /// capsule. Any active preedit is returned so callers can commit it
    /// before switching modes.
    public func setLanguage(_ newLanguage: TypingInputLanguage) -> String {
        guard language != newLanguage else { return "" }
        let raw = composition.preedit.isEmpty ? "" : engine.flushPreedit()
        language = newLanguage
        engine.setLanguage(newLanguage)
        composition = engine.composition
        page = .letters
        return raw
    }

    /// Flushes raw preedit, selects the next built-in scheme, and returns the
    /// raw text that the caller should insert before switching.
    public func cycleSchema() -> String {
        let raw = composition.preedit.isEmpty ? "" : engine.flushPreedit()
        let schemas = TypingInputSchema.allCases
        let current = schemas.firstIndex(of: schema) ?? 0
        let next = schemas[(current + 1) % schemas.count]
        if engine.setSchema(next) {
            schema = next
            TypingInputConfiguration.shared.schema = next
        }
        composition = engine.composition
        return raw
    }

    public func setPage(_ page: TypingKeyPage) {
        self.page = page
        shiftActive = false
    }

    /// Handle a visible key label. Returns text the proxy should insert now
    /// (may be empty when composing Chinese).
    public func handleKey(_ label: String) -> String {
        switch label {
        case "⇧":
            if shiftActive {
                capsLock = true
                shiftActive = false
            } else if capsLock {
                capsLock = false
            } else {
                shiftActive = true
            }
            return ""
        case "⌫":
            if language == .chinese, !engine.composition.preedit.isEmpty {
                let committed = engine.processBackspace() ?? ""
                composition = engine.composition
                return committed
            }
            return "\u{8}" // sentinel: caller deletes backward
        case "123":
            setPage(.numbers)
            return ""
        case "#+=":
            setPage(.symbols)
            return ""
        case "ABC", "abc":
            setPage(.letters)
            return ""
        default:
            break
        }

        if page != .letters {
            // Number/symbol: insert directly
            let out = label
            if !capsLock { shiftActive = false }
            return out
        }

        guard let ch = label.first else { return "" }

        if language == .english {
            let out = String(ch)
            if !capsLock { shiftActive = false }
            return out
        }

        // Chinese letters → compose
        let committed = engine.processCharacter(ch) ?? ""
        composition = engine.composition
        if !capsLock { shiftActive = false }
        return committed
    }

    public func handleSpace() -> String {
        if language == .english { return " " }
        let text = engine.processSpace() ?? " "
        composition = engine.composition
        return text
    }

    public func handleReturn() -> String {
        if language == .english { return "\n" }
        let text = engine.processReturn() ?? "\n"
        composition = engine.composition
        return text
    }

    public func selectCandidate(at index: Int) -> String {
        let text = engine.selectCandidate(at: index)
        composition = engine.composition
        return text
    }

    private func prepareIfNeeded() async {
        guard !prepared else { return }
        do {
            try await engine.prepare()
            engine.setLanguage(language)
            prepared = true
            engineReady = engine.isReady
            schema = engine.schema
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            engineReady = false
        }
    }
}
