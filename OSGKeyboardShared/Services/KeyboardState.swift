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
            /// Keyboard extension lacks Full Access for host-app jumps.
            case fullAccessRequired
            /// Auto-jump to the host app failed; user must open it manually.
            case manualOpenRequired
            /// Host delivered raw transcript; polish step failed or was skipped.
            case polishDegraded(String)
            /// Host ASR finished with no usable speech.
            case noSpeechDetected
            /// Host ASR was interrupted before a final transcript arrived.
            case recognitionInterrupted
            /// Host could not start background audio capture.
            case hostAudioUnavailable
            /// Host ASR or pipeline failed with a user-facing message.
            case hostTranscriptionFailed(String)
            /// Flow result did not arrive before the keyboard watchdog expired.
            case flowResultTimeout
            /// Host Flow session ended while the keyboard was idle.
            case flowSessionExpired
            case unknown(String)
        }

        public enum Reason: Equatable { case mic, speech }
    }

    /// Voice input always runs through polish; legacy off/transcribe modes removed.
    public enum InputMode: String, CaseIterable, Identifiable {
        case polish

        public var id: String { rawValue }

        public var labelKey: String { "mode.polish" }
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
    /// Whether the host app's Flow voice session is live and reachable (fresh
    /// heartbeat). Do not use the App Group session flag alone for UI gating.
    /// Prefer `micVoiceAvailability` for mic color and tap behavior.
    @Published public var flowSessionActive: Bool = false
    /// Unified mic color / tap / hint source for the keyboard extension.
    @Published public var micVoiceAvailability: MicVoiceAvailability = .unavailable(.hostNotReady)
    /// When true, the mic is intentionally disabled (e.g. cloud engine
    /// selected but the provider-specific API key is missing).
    @Published public var micDisabled: Bool = false
    /// One-line helper shown above the mic while `micDisabled == true`.
    @Published public var micDisabledHint: String = ""
    /// "local" → on-device ASR only. "cloud" → cloud ASR + LLM polish.
    /// Boot value must match the privacy-safe app default (`local`) so the
    /// keyboard never assumes the audio-uploading engine before the App
    /// Group config has been read.
    @Published public var engineMode: String = "local"
    /// v0.2.1 follow-up: derived — translation is on iff a target
    /// locale has been selected (mirrors `ProviderConfig.translationEnabled`
    /// so the chip / pipeline read the same source of truth).
    public var translationEnabled: Bool {
        translationTargetLocaleId != TranslationLanguageCatalog.offLocaleId
    }
    /// v0.2.1: target locale id the translate-and-polish prompt should
    /// produce (e.g. `"en"`, `"ja"`). Mirrored from `ProviderConfig`.
    /// Defaults to `offLocaleId` so the keyboard boots in the "off"
    /// state on first install.
    @Published public var translationTargetLocaleId: String = TranslationLanguageCatalog.offLocaleId
    /// Mirrored from App Group — swaps delete / space on the bottom row.
    @Published public var handednessPreference: HandednessPreference = .left
    /// Mirrors the host field's return-key intent. The action stays a newline
    /// insert; host apps decide whether that submits or creates a line break.
    @Published public var returnKeyRole: ReturnKeyRole = .newline
    /// Press-and-drag pads beside the mic for four-way caret movement.
    @Published public var cursorDragNavigationEnabled: Bool = true
    /// `true` while a cursor-drag pad is being pressed — drives the hint
    /// shown above the mic.
    @Published public var cursorDragActive: Bool = false
    /// Whether translate-and-polish is armed for the current engine.
    public var isTranslationEffective: Bool {
        translationEnabled
    }

    /// Whether the keyboard top-bar translation chip should render.
    public var isTranslationChipVisible: Bool { true }

    /// Convenience shorthand used by the pipeline and views.
    public var isLocalEngine: Bool { engineMode == "local" }

    // MARK: - First-launch onboarding (mirrored from ProviderConfig)

    /// Drives the in-keyboard onboarding overlay. When `false`, the
    /// keyboard shows a step-by-step overlay instead of the normal UI;
    /// when `true`, normal UI renders. Mirrored from `ProviderConfig`
    /// so the keyboard never has to instantiate the main-app config.
    @Published public var hasCompletedOnboarding: Bool = false
    /// Step the user is currently on (0-based). The overlay reads this
    /// to render the right page; main-app `ProviderConfig` is the
    /// source of truth and the keyboard mirrors it.
    @Published public var onboardingPage: Int = 0
    /// `true` when the user tapped something (mic, settings) right
    /// before a forced jump to the host app. The keyboard reads this
    /// on return and auto-resumes the action so the user does not have
    /// to tap the same button twice.
    @Published public var pendingResumeAction: ResumeAction = .none

    /// Action the keyboard should auto-trigger after a host-app jump
    /// completes. Set just before `openHostApp`, consumed (set back to
    /// `.none`) after the action fires once.
    public enum ResumeAction: Equatable {
        case none
        case startRecording
        case openSettings
    }

    public enum ReturnKeyRole: Equatable {
        case newline
        case send

        public var titleKey: String {
            switch self {
            case .newline: return "common.newline"
            case .send:    return "common.send"
            }
        }
    }

    // MARK: - Temporary Flow debug (remove after orange-mic investigation)

    /// Mirrored from `KeyboardFlowCoordinator` for the on-screen debug panel.
    @Published public var debugPendingFlowStart: Bool = false
    @Published public var debugFlowRecording: Bool = false
    @Published public var debugAwaitingFlowResult: Bool = false
    @Published public var debugHasFullAccess: Bool = false

    /// Snapshot for the keyboard debug panel.
    public func makeFlowDebugRows(hasFullAccess: Bool) -> [FlowDebugRow] {
        debugHasFullAccess = hasFullAccess
        let micLabel: String = {
            switch micVoiceAvailability {
            case .ready: return "ready"
            case .recording: return "recording"
            case .processing: return "processing"
            case .unavailable(let reason):
                switch reason {
                case .hostNotReady: return "unavailable(hostNotReady)"
                case .preparingSession: return "unavailable(preparingSession)"
                case .noFullAccess: return "unavailable(noFullAccess)"
                case .appGroupUnavailable: return "unavailable(appGroupUnavailable)"
                case .missingAPIKey: return "unavailable(missingAPIKey)"
                }
            }
        }()
        let localRows: [FlowDebugRow] = [
            FlowDebugRow("mic", micLabel),
            FlowDebugRow("phase", String(describing: phase)),
            FlowDebugRow("pendingStart", debugPendingFlowStart ? "1" : "0"),
            FlowDebugRow("kb.recording", debugFlowRecording ? "1" : "0"),
            FlowDebugRow("kb.awaiting", debugAwaitingFlowResult ? "1" : "0"),
            FlowDebugRow("fullAccess", hasFullAccess ? "1" : "0"),
            FlowDebugRow("micDisabled", micDisabled ? "1" : "0"),
            FlowDebugRow("flowSessionPub", flowSessionActive ? "1" : "0"),
            FlowDebugRow("engine", engineMode)
        ]
        return localRows + FlowDebugAppGroupSnapshot.rows()
    }

    // Action hooks — injected by the view controller at install time.
    public var beginRecording:      () -> Void = {}
    public var endRecording:        () -> Void = {}
    public var tapMic:              () -> Void = {}
    public var openSettings:        () -> Void = {}
    public var startFlowSession:    () -> Void = {}
    public var setMode:             (InputMode) -> Void = { _ in }
    public var setLocale:           (String) -> Void = { _ in }
    public var setEngineMode:        (String) -> Void = { _ in }
    /// v0.2.1 follow-up: only the locale picker remains — `enabled`
    /// is derived from the locale id, so there's no separate toggle to
    /// persist. Wired in `KeyboardViewController.installStateActions`.
    public var setTranslationTargetLocaleId: (String) -> Void = { _ in }
    public var advanceOnboarding:   () -> Void = {}
    public var completeOnboarding:   () -> Void = {}
    public var requestMicPermission:   () -> Void = {}
    public var requestSpeechPermission: () -> Void = {}
    public var openSystemSettings:   () -> Void = {}
    public var insertNewline:       () -> Void = {}
    public var insertSpace:         () -> Void = {}
    public var deleteBackward:      () -> Void = {}
    public var moveCursorHorizontal: (Int) -> Void = { _ in }
    public var moveCursorVertical:   (Int) -> Void = { _ in }
    /// Cursor-drag pad press lifecycle — updates `cursorDragActive` and
    /// lets the view controller reset vertical-navigation stickiness.
    public var setCursorDragActive:  (Bool) -> Void = { _ in }

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

extension KeyboardState.Phase.ErrorKind {
    /// Maps a host-app Flow transcription failure into a keyboard error kind.
    public static func fromFlowTranscription(_ error: FlowTranscriptionError) -> Self {
        switch error.kind {
        case .noSpeech:
            return .noSpeechDetected
        case .recognitionInterrupted:
            return .recognitionInterrupted
        case .audioUnavailable:
            return .hostAudioUnavailable
        case .asrFailed, .generic:
            return .hostTranscriptionFailed(error.message)
        }
    }
}