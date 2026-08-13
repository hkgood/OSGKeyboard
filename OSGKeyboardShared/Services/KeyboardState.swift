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
import UIKit

@MainActor
public final class KeyboardState: ObservableObject {
    public init() {}

    /// Full-height clipboard UI layered over the active keyboard surface.
    public enum ClipboardKeyboardOverlay: Equatable {
        case none
        case enableGuide
        case historyPanel
    }

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

    /// Keyboard chrome surface. Voice is the default product mode; typing is
    /// a secondary QWERTY / pinyin surface for quick corrections.
    public enum Surface: String, CaseIterable, Identifiable, Sendable {
        case voice
        case typing
        case ai

        public var id: String { rawValue }
    }

    @Published public var phase: Phase = .idle
    /// Active chrome. Forced to `.voice` while recording / processing.
    @Published public var surface: Surface = .voice
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
    /// AI mode always needs an LLM even when local ASR keeps voice dictation usable.
    @Published public var aiServiceAvailable: Bool = true
    /// One-line helper shown above the mic while `micDisabled == true`.
    @Published public var micDisabledHint: String = ""
    /// "local" → on-device ASR only. "cloud" → cloud ASR + LLM polish.
    /// Boot value must match the privacy-safe app default (`local`) so the
    /// keyboard never assumes the audio-uploading engine before the App
    /// Group config has been read.
    @Published public var engineMode: String = "local"
    /// Derived: translation is on iff a target
    /// locale has been selected (mirrors `ProviderConfig.translationEnabled`
    /// so the chip / pipeline read the same source of truth).
    public var translationEnabled: Bool {
        translationTargetLocaleId != TranslationLanguageCatalog.offLocaleId
    }
    /// Target locale id the translate-and-polish prompt should
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
    /// Opt-in clipboard history capture (mirrored from App Group).
    @Published public var clipboardHistoryEnabled: Bool = false
    /// Opt-in clipboard suggestion strip (requires history enabled).
    @Published public var clipboardCandidateBarEnabled: Bool = false
    /// Skills-tab order for clipboard chips (max 8). Empty → hint carousel.
    @Published public var enabledClipboardSkillIDs: [String] = AIAgentSkillLayout.defaultEnabledIDs
    /// Export skill currently waiting on the LLM. Nil for transform skills.
    @Published public var pendingClipboardSkillID: String?
    /// In-keyboard toast (e.g. no todos). Does not leave the host app.
    @Published public var skillTipText: String?
    /// Host field is a password / secure entry — never read pasteboard.
    @Published public var isSecureTextEntry: Bool = false
    /// Secure fields hide every clipboard-history entry point.
    public var canShowClipboardEntry: Bool {
        !isSecureTextEntry
    }
    /// Full-keyboard clipboard overlay (enable guide or history list).
    @Published public var clipboardOverlay: ClipboardKeyboardOverlay = .none
    /// Suggestion strip above keys (newest clipboard item).
    @Published public var clipboardSuggestionText: String?
    /// Pasteboard changeCount associated with the current suggestion (for dismiss).
    @Published public var clipboardSuggestionChangeCount: Int?
    /// Typing-grid haptic strength (off / light / strong).
    @Published public var keyboardHapticIntensity: KeyboardHapticIntensity = .default
    /// Single source of truth for selecting iPad-scale keyboard metrics.
    /// The view controller resolves this from device idiom + horizontal size
    /// class so SwiftUI and the UIKit height constraint cannot disagree.
    @Published public var usesIPadLayoutMetrics: Bool = false
    /// The custom system-keyboard switch is iPad-only. iPhone relies on the
    /// system-provided switch below the keyboard instead of showing a duplicate.
    @Published public var showsSystemGlobeKey: Bool = false
    /// Width the controller sized the keyboard to. Both the UIKit height
    /// constraint and the SwiftUI key grid pick their metrics from this one
    /// value so they can never disagree and clip the bottom row.
    @Published public var layoutWidth: CGFloat = 0
    /// `true` while a cursor-drag pad is being pressed — drives the hint
    /// shown above the mic.
    @Published public var cursorDragActive: Bool = false
    /// `true` when the last voice insertion is still at the caret and can
    /// be undone (suffix-checked against `documentContextBeforeInput`).
    @Published public var undoAvailable: Bool = false
    /// `true` while an undone voice insertion can be re-applied (redo buffer).
    @Published public var redoAvailable: Bool = false
    /// `true` when the host field has a non-empty selection (copy enabled).
    @Published public var copyAvailable: Bool = false
    /// `true` when the host field has a non-empty selection (cut enabled).
    @Published public var cutAvailable: Bool = false
    /// Closed state machine for long-press editing of the last insertion.
    @Published public var editSession: EditSessionState = .inactive
    /// AI conversation UI state for the keyboard surface. The host owns the actual messages.
    @Published public var aiSession: AISessionState = .inactive
    @Published public var editCanReplaceOriginal: Bool = false
    /// Short idle feedback (availability, expiry, missing LLM).
    @Published public var editHint: String?
    /// Availability hints use the green accent; failures keep warning styling.
    @Published public var editHintIsPositive: Bool = false
    /// Whether translate-and-polish is armed for the current engine.
    public var isTranslationEffective: Bool {
        translationEnabled
    }

    /// Convenience shorthand used by the pipeline and views.
    public var isLocalEngine: Bool { engineMode == "local" }

    /// Applies the non-persistent secure-field UI policy immediately.
    public func setSecureTextEntry(_ isSecure: Bool) {
        isSecureTextEntry = isSecure
        guard isSecure else { return }
        clipboardSuggestionText = nil
        clipboardSuggestionChangeCount = nil
        clipboardOverlay = .none
    }

    // MARK: - Host-app onboarding gate

    /// Mirrored from App Group / Keychain. Setup UI lives only in the host
    /// app; the keyboard uses this flag to gate voice (mic / Flow cold-start)
    /// and prompt a jump back to the app when incomplete.
    @Published public var hasCompletedOnboarding: Bool = false

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

    // Action hooks — injected by the view controller at install time.
    public var beginRecording:      () -> Void = {}
    public var endRecording:        () -> Void = {}
    public var tapMic:              () -> Void = {}
    /// Starts/cancels a bounded host-audio prime from the user's mic touch.
    public var setMicTouchActive:   (Bool) -> Void = { _ in }
    /// Discards the complete normal-dictation round, including late ASR/LLM output.
    public var cancelVoiceInput:    () -> Void = {}
    public var beginEditLastInput: () -> Void = {}
    public var stopEditListening: () -> Void = {}
    public var confirmEditResult: () -> Void = {}
    public var closeEditMode: () -> Void = {}
    public var tapAIMic: () -> Void = {}
    public var cancelAIInput: () -> Void = {}
    public var sendAIAnswer: () -> Void = {}
    /// Sends a tapped idle hint card as the AI question (skip microphone).
    public var submitAIHint: (AIHintCard) -> Void = { _ in }
    /// Sends a clipboard skill (reply / summarize / translate / export).
    public var submitAIClipboardSkill: (AIClipboardSkill) -> Void = { _ in }
    /// Writes extract-todos titles and opens the host to run the Shortcut.
    public var runClipboardExportSkill: (String, [String]) -> Void = { _, _ in }
    public var openSettings:        () -> Void = {}
    /// Opens the host app straight to input-resource deployment. Used by the
    /// typing surface when Rime resources have not been deployed yet.
    public var openInputMethodSetup: () -> Void = {}
    /// Opens the host app Settings → Clipboard page (enable history toggle).
    public var openClipboardSettings: () -> Void = {}
    /// Top-bar clipboard button: guide when history off, else history panel.
    public var openClipboardPanel: () -> Void = {}
    public var dismissClipboardOverlay: () -> Void = {}
    public var insertClipboardText: (String) -> Void = { _ in }
    public var dismissClipboardSuggestion: () -> Void = {}
    public var clearClipboardHistory: () -> Void = {}
    public var deleteClipboardHistoryEntry: (UUID) -> Void = { _ in }
    /// Notify that the user inserted text (hides suggestion strip).
    public var noteUserDidInputText: () -> Void = {}
    /// System globe (🌐) key target. Kept weak to avoid a state → controller
    /// ownership cycle; UIKit's standard all-touch-events action provides both
    /// tap-to-advance and long-press input-mode selection.
    public weak var inputModeController: UIInputViewController?
    public var startFlowSession:    () -> Void = {}
    public var setMode:             (InputMode) -> Void = { _ in }
    public var setLocale:           (String) -> Void = { _ in }
    public var setEngineMode:        (String) -> Void = { _ in }
    /// Only the locale picker remains; `enabled`
    /// is derived from the locale id, so there's no separate toggle to
    /// persist. Wired in `KeyboardViewController.installStateActions`.
    public var setTranslationTargetLocaleId: (String) -> Void = { _ in }
    public var insertNewline:       () -> Void = {}
    public var insertSpace:         () -> Void = {}
    public var deleteBackward:      () -> Void = {}
    /// Undo the last voice insertion when `undoAvailable` is true.
    public var undoLastInsertion:   () -> Void = {}
    /// Redo the last undone voice insertion when `redoAvailable` is true.
    public var redoLastInsertion:   () -> Void = {}
    /// Copy the current text selection to the pasteboard.
    public var copySelection:       () -> Void = {}
    /// Cut the current text selection (copy + delete).
    public var cutSelection:        () -> Void = {}
    public var moveCursorHorizontal: (Int) -> Void = { _ in }
    public var moveCursorVertical:   (Int) -> Void = { _ in }
    /// Cursor-drag pad press lifecycle — updates `cursorDragActive` and
    /// lets the view controller reset vertical-navigation stickiness.
    public var setCursorDragActive:  (Bool) -> Void = { _ in }
    /// Switch voice ↔ typing. No-ops when voice pipeline is active.
    public var setSurface: (Surface) -> Void = { _ in }

    /// Recording / processing must stay on the voice surface.
    public var locksTypingSurface: Bool {
        if editSession.isActive { return true }
        if aiSession.isBusy { return true }
        switch phase {
        case .requestingPermissions, .recording, .processing:
            return true
        default:
            return false
        }
    }

    public var canEnterTypingSurface: Bool { !locksTypingSurface }

    public var canCancelAIInput: Bool {
        surface == .ai && aiSession.isBusy
    }

    /// Normal dictation can be discarded from microphone startup through
    /// ASR / polish, including the abort-wait after Cancel until the host
    /// acks (coordinator keeps `phase == .processing` for that window).
    public var canCancelVoiceInput: Bool {
        guard !editSession.isActive else { return false }
        switch phase {
        case .requestingPermissions, .recording, .processing:
            return true
        case .idle, .error, .denied:
            return false
        }
    }

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
        case .discardedEmpty:
            return .noSpeechDetected
        }
    }
}