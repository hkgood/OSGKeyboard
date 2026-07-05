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
    /// When true, the mic is intentionally disabled (e.g. cloud engine
    /// selected but the provider-specific API key is missing).
    @Published public var micDisabled: Bool = false
    /// One-line helper shown above the mic while `micDisabled == true`.
    @Published public var micDisabledHint: String = ""
    /// "local" → on-device ASR only. "cloud" → ASR + LLM polish.
    @Published public var engineMode: String = "cloud"
    /// Which on-device ASR engine to use when `engineMode == "local"`.
    /// Mirrored from `ProviderConfig.localASRBackend` for UI display
    /// and for `state` consumers that want a single source of truth.
    @Published public var localASRBackend: LocalASRBackend = .speechAnalyzer
    /// v0.2.0: kept for source compatibility with the previous Qwen3
    /// CoreML local engine. Always `true` now — iOS `SpeechAnalyzer`
    /// ships with iOS 26 and has no per-user weights to download or
    /// preload. Existing read sites will see `true` and behave the
    /// same as the "stack ready" branch did.
    @Published public var localModelsReady: Bool = true
    /// v0.2.0: kept for source compatibility with the previous Qwen3
    /// CoreML local engine. Always `false` now — there are no weights
    /// for the host app to preload.
    @Published public var localModelsLoaded: Bool = false
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
    /// v0.2.0: mirrored from App Group — kept for source compatibility.
    /// Local engine always runs built-in polish; the flag is ignored.
    @Published public var localModeCloudPolishEnabled: Bool = true
    /// Mirrored from App Group — swaps delete / return on the bottom row.
    @Published public var handednessPreference: HandednessPreference = .left
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

    // Action hooks — injected by the view controller at install time.
    public var beginRecording:      () -> Void = {}
    public var endRecording:        () -> Void = {}
    public var tapMic:              () -> Void = {}
    public var openSettings:        () -> Void = {}
    public var startFlowSession:    () -> Void = {}
    public var setMode:             (InputMode) -> Void = { _ in }
    public var setLocale:           (String) -> Void = { _ in }
    public var setEngineMode:        (String) -> Void = { _ in }
    public var setLocalASRBackend:  (LocalASRBackend) -> Void = { _ in }
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