// LibrimeEngine.swift
// OSGKeyboard · Shared
//
// Production Chinese IME backed by librime. Runtime access stays on the
// main actor because UIInputViewController and its text proxy are main-only;
// expensive schema deployment is performed by the host app beforehand.

import Foundation

@MainActor
public final class LibrimeEngine: RimeEngineBridging {
    public private(set) var composition: TypingComposition = .empty
    public private(set) var isReady = false
    public private(set) var schema: TypingInputSchema

    private var language: TypingInputLanguage = .chinese
    private var bridge: OSGRimeBridge?
    private let configurationProvider: () -> TypingInputConfigurationSnapshot
    private let candidateLimit: Int

    public init(
        schema: TypingInputSchema = .fullPinyin,
        candidateLimit: Int = 160,
        configurationProvider: @escaping () -> TypingInputConfigurationSnapshot = {
            TypingInputConfiguration.shared.snapshot
        }
    ) {
        self.schema = schema
        self.candidateLimit = candidateLimit
        self.configurationProvider = configurationProvider
    }

    public func prepare() async throws {
        if isReady { return }
        guard RimeResourceInstaller.isReady else {
            throw RimeResourceError.resourcesNotInstalled
        }

        let paths = try RimeResourcePaths.resolve()
        let runtime = OSGRimeBridge(
            sharedDataDirectory: paths.sharedData.path,
            userDataDirectory: paths.userData.path,
            distributionVersion: RimeResourceInstaller.resourceVersion
        )
        try runtime.start()

        let configured = configurationProvider()
        schema = configured.schema
        guard runtime.selectSchema(schema.rawValue) else {
            runtime.stopSession()
            throw LibrimeEngineError.schemaUnavailable(schema.rawValue)
        }
        _ = runtime.setASCIIMode(language == .english)
        bridge = runtime
        isReady = true
        _ = refresh()
    }

    public func teardown() {
        bridge?.clearComposition()
        bridge?.stopSession()
        bridge = nil
        composition = .empty
        isReady = false
    }

    public func setLanguage(_ language: TypingInputLanguage) {
        self.language = language
        _ = bridge?.setASCIIMode(language == .english)
        if language == .english {
            bridge?.clearComposition()
            composition = .empty
        } else {
            _ = refresh()
        }
    }

    @discardableResult
    public func setSchema(_ schema: TypingInputSchema) -> Bool {
        guard let bridge else {
            self.schema = schema
            return false
        }
        bridge.clearComposition()
        guard bridge.selectSchema(schema.rawValue) else { return false }
        self.schema = schema
        composition = .empty
        return true
    }

    public func processCharacter(_ character: Character) -> String? {
        guard language == .chinese,
              let scalar = character.asciiValue,
              bridge?.processKeyCode(Int32(scalar), modifiers: 0) == true else {
            return nil
        }
        return refresh()
    }

    public func processBackspace() -> String? {
        guard bridge?.processKeyCode(OSGRimeKeyBackSpace, modifiers: 0) == true else {
            return nil
        }
        return refresh()
    }

    public func processSpace() -> String? {
        guard bridge?.processKeyCode(32, modifiers: 0) == true else {
            return " "
        }
        return refresh()
    }

    public func processReturn() -> String? {
        guard bridge?.processKeyCode(OSGRimeKeyReturn, modifiers: 0) == true else {
            return "\n"
        }
        return refresh()
    }

    public func selectCandidate(at index: Int) -> String {
        guard bridge?.selectCandidate(at: index) == true else { return "" }
        return refresh() ?? ""
    }

    public func flushPreedit() -> String {
        let raw = bridge?.rawInput() ?? ""
        bridge?.clearComposition()
        composition = .empty
        return raw
    }

    public func clearComposition() {
        bridge?.clearComposition()
        composition = .empty
    }

    /// Copies librime-owned memory into Sendable Swift value types and returns
    /// any commit emitted by the preceding key operation.
    @discardableResult
    private func refresh() -> String? {
        guard let snapshot = bridge?.snapshot(withCandidateLimit: candidateLimit) else {
            composition = .empty
            return nil
        }
        let preedit = snapshot.preedit
        composition = TypingComposition(
            preedit: preedit,
            candidates: snapshot.candidates.enumerated().map { displayIndex, candidate in
                TypingCandidate(
                    id: "\(preedit)|\(displayIndex)|\(candidate.index)|\(candidate.text)",
                    text: candidate.text,
                    annotation: candidate.comment.isEmpty ? nil : candidate.comment,
                    engineIndex: Int(candidate.index)
                )
            }
        )
        return snapshot.commitText.isEmpty ? nil : snapshot.commitText
    }
}

public enum LibrimeEngineError: LocalizedError {
    case schemaUnavailable(String)

    public var errorDescription: String? {
        switch self {
        case .schemaUnavailable(let id):
            return "输入方案不可用：\(id)"
        }
    }
}

private extension Character {
    var asciiValue: UInt8? {
        guard let scalar = unicodeScalars.first,
              unicodeScalars.count == 1,
              scalar.value <= UInt8.max else {
            return nil
        }
        return UInt8(scalar.value)
    }
}
