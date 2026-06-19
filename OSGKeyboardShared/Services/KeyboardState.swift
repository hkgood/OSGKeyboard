// KeyboardState.swift
// OSGKeyboard · Shared
//
// View-model for the keyboard extension. Lives in Shared (not the
// extension target) so unit tests can import it directly without the
// `app-extension` linking headaches. The keyboard view controller
// (`KeyboardViewController`) re-exports the same type as a typealias so
// existing call sites (`KeyboardViewController.State`) keep compiling.

import Foundation
import Combine
import SwiftUI

@MainActor
public final class KeyboardState: ObservableObject {
    public init() {}

    /// Pipeline phase. Errors are structured so the UI layer can choose
    /// the right icon / copy for each failure mode without
    /// reverse-parsing a free-form string.
    public enum Phase: Equatable {
        case idle
        case requestingPermissions
        case recording
        case processing
        case error(ErrorKind, message: String? = nil)
        case denied(Reason)

        /// Why the pipeline failed. `message` is a short, user-facing
        /// hint (e.g. "请检查主 App 设置"); the structured kind is what
        /// drives icon / colour.
        public enum ErrorKind: Equatable {
            case micDenied
            case speechDenied
            case asr(String)
            case llm(LLMError)
            case appGroupUnavailable
            case unknown(String)
        }

        public enum Reason: Equatable { case mic, speech }
    }

    public enum InputMode: String, CaseIterable, Identifiable {
        case off
        case transcribe
        case polish

        public var id: String { rawValue }

        public var labelKey: String {
            switch self {
            case .off:        return "mode.off"
            case .transcribe: return "mode.transcribe"
            case .polish:     return "mode.polish"
            }
        }
    }

    @Published public var phase: Phase = .idle
    @Published public var level: Double = 0
    @Published public var mode: InputMode = .polish
    @Published public var localeId: String = "auto"
    @Published public var lastTranscript: String = ""
    /// `true` if the active ASR session is running on-device for the
    /// current locale. With iOS 26's `SpeechAnalyzer` this is always
    /// `true` — kept on the state object because the UI's status
    /// badge still wants a single source of truth to read from.
    @Published public var onDeviceSupported: Bool = false
    /// Seconds remaining in the current utterance (Flow tap-to-talk).
    @Published public var utteranceRemainingSeconds: Int = Int(FlowSessionKeys.maxUtteranceDuration)
    /// Whether the host app's Flow voice session is currently valid.
    @Published public var flowSessionActive: Bool = false
    /// "local" → ASR only, no LLM. "cloud" → ASR + optional LLM polish.
    @Published public var engineMode: String = "cloud"

    /// Convenience shorthand used by the pipeline and views.
    public var isLocalEngine: Bool { engineMode == "local" }

    // Action hooks — injected by the view controller at install time.
    public var beginRecording:      () -> Void = {}
    public var endRecording:        () -> Void = {}
    public var tapMic:              () -> Void = {}
    public var openSettings:        () -> Void = {}
    public var startFlowSession:    () -> Void = {}
    public var setMode:             (InputMode) -> Void = { _ in }
    public var setLocale:           (String) -> Void = { _ in }
    public var setEngineMode:        (String) -> Void = { _ in }
    public var insertNewline:       () -> Void = {}
    public var insertSpace:         () -> Void = {}
    public var deleteBackward:      () -> Void = {}

    // MARK: - Preview helpers (DEBUG only)

    #if DEBUG
    public static var previewIdle: KeyboardState {
        let s = KeyboardState()
        s.phase = .idle
        s.level = 0
        s.mode = .polish
        s.localeId = "zh-Hans"
        s.lastTranscript = ""
        return s
    }
    public static var previewRecording: KeyboardState {
        let s = KeyboardState()
        s.phase = .recording
        s.level = 0.65
        s.mode = .polish
        s.localeId = "zh-Hans"
        s.lastTranscript = "你好,我想说一段测试"
        return s
    }
    public static var previewProcessing: KeyboardState {
        let s = KeyboardState()
        s.phase = .processing
        s.level = 0
        s.mode = .polish
        s.localeId = "zh-Hans"
        s.lastTranscript = ""
        return s
    }
    #endif
}