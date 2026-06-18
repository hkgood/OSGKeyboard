// KeyboardViewController.swift
// OSGKeyboard · Keyboard Extension
//
// Principal class for the Custom Keyboard Extension. Hosts a single
// SwiftUI tree (`KeyboardRootView`) and drives the recording pipeline:
//
//     AudioCaptureService ──► ASRService ──► PolishingService ──► insertText
//
// Design notes:
//   • The class is `@MainActor` — every UI mutation and `textDocumentProxy`
//     call must happen on main, and Swift 6 strict concurrency forces this.
//   • State is a single `State` ObservableObject; SwiftUI observes it via
//     `@ObservedObject` so we never re-create the hosting root on each tick.
//   • `phase` is a real stored property (no derivation) — the previous
//     "derive from recordStream" shim locked out every press after the first.
//   • Microphone permission is requested *inside* pressBegan, but we still
//     start the rest of the press flow optimistically; if permission is
//     denied we surface a short error and drop back to idle cleanly.

import UIKit
import SwiftUI
import AVFoundation
import Speech
import OSGKeyboardShared

@objc(KeyboardViewController)
@MainActor
public final class KeyboardViewController: UIInputViewController {

    // MARK: - View model

    @MainActor
    public final class State: ObservableObject {
        public init() {}
        public enum Phase: Equatable {
            case idle
            case recording
            case processing
            case error(String)
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

        // Action hooks — injected by the view controller at install time.
        var beginRecording: () -> Void = {}
        var endRecording:   () -> Void = {}
        var tapMic:         () -> Void = {}     // tap on the mic area (advances keyboard)
        var openSettings:   () -> Void = {}
        var setMode:        (InputMode) -> Void = { _ in }
        var setLocale:      (String) -> Void = { _ in }
        var insertNewline:  () -> Void = {}
        var insertSpace:    () -> Void = {}
        var deleteBackward: () -> Void = {}

        // MARK: - Preview helpers

        #if DEBUG
        static var previewIdle: State {
            let s = State()
            s.phase = .idle
            s.level = 0
            s.mode = .polish
            s.localeId = "zh-Hans"
            s.lastTranscript = ""
            return s
        }
        static var previewRecording: State {
            let s = State()
            s.phase = .recording
            s.level = 0.65
            s.mode = .polish
            s.localeId = "zh-Hans"
            s.lastTranscript = "你好,我想说一段测试"
            return s
        }
        static var previewProcessing: State {
            let s = State()
            s.phase = .processing
            s.level = 0
            s.mode = .polish
            s.localeId = "zh-Hans"
            s.lastTranscript = ""
            return s
        }
        #endif
    }

    // MARK: - State

    private let state = State()
    private let audio = AudioCaptureService()
    private let asr: ASRService = ASRServiceFactory.make()
    private let polisher = PolishingService()

    private var session: AudioCaptureService.Session?
    private var asrTask: Task<Void, Never>?
    private var levelTask: Task<Void, Never>?
    private var didRequestMicOnce: Bool = false

    private var hosting: UIHostingController<KeyboardRootView>!

    // MARK: - Lifecycle

    public override func viewDidLoad() {
        super.viewDidLoad()
        // iOS 18 keyboard extension MUST opt in to self-sizing, otherwise
        // our SwiftUI `frame(height:)` is ignored and the keyboard is
        // cropped by the system chrome (Spotlight bar, home indicator).
        inputView?.allowsSelfSizing = true
        installStateActions()
        installSwiftUI()
        loadPersistedLocale()
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        cancelPipeline()
    }

    public override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        cancelPipeline()
    }

    public override func textDidChange(_ textInput: (any UITextInput)?) {
        super.textDidChange(textInput)
        // Hook for future per-app mode switching (e.g. password field → .off).
    }

    // MARK: - Wiring

    private func installStateActions() {
        state.beginRecording  = { [weak self] in self?.pressBegan() }
        state.endRecording    = { [weak self] in self?.pressEnded() }
        state.tapMic          = { [weak self] in self?.advanceToNextInputMode() }
        state.openSettings    = { [weak self] in self?.openHostApp() }
        state.setMode         = { [weak self] m in self?.persistMode(m) }
        state.setLocale       = { [weak self] l in self?.persistLocale(l) }
        state.insertNewline   = { [weak self] in self?.textDocumentProxy.insertText("\n") }
        state.insertSpace     = { [weak self] in self?.textDocumentProxy.insertText(" ") }
        state.deleteBackward  = { [weak self] in self?.textDocumentProxy.deleteBackward() }
    }

    private func installSwiftUI() {
        let root = KeyboardRootView(state: state)
        let host = UIHostingController(rootView: root)
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false
        addChild(host)
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            // Pin the host view to a fixed height matching KeyboardRootView.totalHeight.
            // Without this, iOS lets the system chrome (Spotlight, home
            // indicator) bleed into our content. With it, our content area
            // is fully reserved and the keyboard feels intentional.
            host.view.heightAnchor.constraint(equalToConstant: KeyboardRootView.totalHeight)
        ])
        host.didMove(toParent: self)
        self.hosting = host
    }

    private func loadPersistedLocale() {
        let store = AppGroupStore()
        let id = store.localeId
        state.localeId = id
        state.mode = State.InputMode(rawValue: store.modeId) ?? .polish
        #if DEBUG
        // Print a masked view of the live App Group config so we can see
        // from the device console exactly what the keyboard extension
        // actually sees (and whether it agrees with the main App).
        let key = store.apiKey
        let masked: String
        if key.count > 8 {
            masked = "\(key.prefix(4))…\(key.suffix(4)) (\(key.count) chars)"
        } else if key.isEmpty {
            masked = "<empty>"
        } else {
            masked = "<\(key.count) chars>"
        }
        print("""
        🔍 [KeyboardViewController.loadPersistedLocale]
           providerId = \(store.providerId)
           baseURL    = \(store.baseURL)
           apiKey     = \(masked)
           model      = \(store.model)
           modeId     = \(store.modeId)
           localeId   = \(store.localeId)
        """)
        #endif
    }

    // MARK: - Press handlers

    private func pressBegan() {
        guard state.phase == .idle else { return }
        guard state.mode != .off else { return }
        // We optimistically enter `.recording`; the capture session will yield
        // frames on its own queue, so even if mic permission takes a beat the
        // user already feels the press registered.
            Task { @MainActor [weak self] in
            guard let self else { return }
            let micGranted = await self.requestMicPermission()
            guard micGranted else {
                self.state.phase = .error("麦克风被拒绝,请到「设置」中允许")
                self.scheduleAutoClearError()
                return
            }
            // iOS 18 SFSpeechRecognizer path: we explicitly ask for Speech
            // recognition permission. Without this call + the
            // NSSpeechRecognitionUsageDescription key in Info.plist the
            // recogniser silently returns .denied and the user hears
            // nothing back.
            // iOS 26 SpeechAnalyzer path (planned for the next release)
            // does not expose an explicit request API — the framework
            // prompts via the same plist key on first use.
            let speechGranted = await self.requestSpeechPermission()
            guard speechGranted else {
                self.state.phase = .error("语音识别被拒绝,请到「设置」中允许")
                self.scheduleAutoClearError()
                return
            }
            self.startPipeline()
        }
    }

    private func pressEnded() {
        guard state.phase == .recording else { return }
        stopPipeline()
    }

    // MARK: - Pipeline

    private func startPipeline() {
        let session = audio.start()
        self.session = session
        state.phase = .recording
        state.level = 0
        state.lastTranscript = ""

        let locale = resolveLocale(state.localeId)
        let events = asr.transcribe(stream: session.audio, locale: locale)

        asrTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var lastPartial: String = ""
            for await event in events {
                switch event {
                case .partial(let s):
                    lastPartial = s
                    self.state.lastTranscript = s
                case .final(let s):
                    let transcript = s.isEmpty ? lastPartial : s
                    self.handleFinalTranscript(transcript)
                case .error(let m):
                    self.state.phase = .error("ASR: \(m)")
                    self.scheduleAutoClearError()
                }
            }
        }

        levelTask = Task { @MainActor [weak self] in
            for await level in session.levels {
                guard let self else { return }
                // Smooth a little extra to feel natural.
                self.state.level = Double(self.state.level) * 0.6 + Double(level.meter) * 0.4
            }
        }
    }

    private func stopPipeline() {
        session?.stop()
        session = nil
        asrTask?.cancel();   asrTask = nil
        levelTask?.cancel(); levelTask = nil
    }

    private func cancelPipeline() {
        stopPipeline()
        asr.cancel()
        if state.phase == .recording || state.phase == .processing {
            state.phase = .idle
        }
        state.level = 0
    }

    private func handleFinalTranscript(_ transcript: String) {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            state.phase = .idle
            return
        }
        // In `.transcribe` mode, skip the LLM and insert raw.
        if state.mode == .transcribe {
            textDocumentProxy.insertText(trimmed)
            state.lastTranscript = ""
            state.phase = .idle
            return
        }
        // `.polish` (default): call the LLM.
        state.phase = .processing
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let polished = try await self.polisher.polish(trimmed)
                self.textDocumentProxy.insertText(polished)
                self.state.lastTranscript = ""
                self.state.phase = .idle
            } catch LLMError.noAPIKey {
                // Don't silently insert the raw transcript — the user
                // thinks they're getting polished text when really no
                // key is configured. Show a precise, actionable error.
                self.state.phase = .error("未配置 API Key · 请在主 App 设置中填写")
                self.scheduleAutoClearError()
            } catch let error as LLMError {
                switch error {
                case .http(401):
                    self.state.phase = .error("API Key 无效 (401) · 请检查主 App 设置")
                    self.scheduleAutoClearError()
                case .http(429), .rateLimited:
                    self.state.phase = .error("API 限流 (429) · 请稍后再试")
                    self.scheduleAutoClearError()
                default:
                    // Other LLMError variants (transport / decoding /
                    // invalidURL / cancelled) fall back to raw transcript
                    // + generic error badge, same as the catch-all below.
                    self.textDocumentProxy.insertText(trimmed)
                    self.state.lastTranscript = ""
                    let msg = error.errorDescription ?? "Polishing failed — inserted raw."
                    self.state.phase = .error(msg)
                    self.scheduleAutoClearError()
                }
            } catch {
                // Network / timeout / decoding — fall back to the raw
                // transcript so the user still gets their text, with a
                // visible error badge.
                self.textDocumentProxy.insertText(trimmed)
                self.state.lastTranscript = ""
                let msg = (error as? LocalizedError)?.errorDescription
                    ?? "Polishing failed — inserted raw."
                self.state.phase = .error(msg)
                self.scheduleAutoClearError()
            }
        }
    }

    // MARK: - Persistence

    private func persistMode(_ m: State.InputMode) {
        state.mode = m
        AppGroupStore().setModeId(m.rawValue)
    }

    private func persistLocale(_ id: String) {
        state.localeId = id
        AppGroupStore().setLocaleId(id)
    }

    // MARK: - Permissions

    private func requestMicPermission() async -> Bool {
        if #available(iOS 17.0, *) {
            switch AVAudioApplication.shared.recordPermission {
            case .granted: return true
            case .denied:  return false
            case .undetermined:
                if !didRequestMicOnce {
                    didRequestMicOnce = true
                    return await AVAudioApplication.requestRecordPermission()
                }
                return false
            @unknown default: return false
            }
        } else {
            let session = AVAudioSession.sharedInstance()
            switch session.recordPermission {
            case .granted: return true
            case .denied:  return false
            case .undetermined:
                if !didRequestMicOnce {
                    didRequestMicOnce = true
                    return await withCheckedContinuation { cont in
                        session.requestRecordPermission { cont.resume(returning: $0) }
                    }
                }
                return false
            @unknown default: return false
            }
        }
    }

    /// Request Speech Recognition permission. Returns true if granted
    /// (or already authorised). For the iOS 18 SFSpeechRecognizer path
    /// this is required before recognition can begin; for the iOS 26
    /// SpeechAnalyzer path the framework prompts on first use.
    private func requestSpeechPermission() async -> Bool {
        await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { status in
                switch status {
                case .authorized: cont.resume(returning: true)
                case .denied, .restricted, .notDetermined:
                    cont.resume(returning: false)
                @unknown default:
                    cont.resume(returning: false)
                }
            }
        }
    }

    // MARK: - Open host app

    private func openHostApp() {
        let urlString = "osgkeyboard://settings"
        if let url = URL(string: urlString) {
            var responder: UIResponder? = self
            while let r = responder {
                if let app = r as? UIApplication {
                    app.open(url)
                    return
                }
                responder = r.next
            }
        }
        if let url = URL(string: UIApplication.openSettingsURLString) {
            var responder: UIResponder? = self
            while let r = responder {
                if let app = r as? UIApplication {
                    app.open(url); return
                }
                responder = r.next
            }
        }
    }

    // MARK: - Helpers

    private func resolveLocale(_ id: String) -> Locale {
        if id == "auto" { return .current }
        return Locale(identifier: id)
    }

    private func scheduleAutoClearError() {
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            guard let self else { return }
            if case .error = self.state.phase {
                self.state.phase = .idle
            }
        }
    }
}
