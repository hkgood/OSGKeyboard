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
import OSGKeyboardShared

@objc(KeyboardViewController)
@MainActor
public final class KeyboardViewController: UIInputViewController {

    // MARK: - View model

    /// Typealias so existing call sites (`KeyboardViewController.State`)
    /// keep compiling unchanged. The actual class lives in
    /// `OSGKeyboardShared` so unit tests can `@testable import` it
    /// without dragging in the `app-extension` linking surface.
    public typealias State = KeyboardState

    // MARK: - State

    private let state = State()
    private let audio = AudioCaptureService()
    private let asr: ASRService = ASRServiceFactory.make()
    private let polisher = PolishingService()
    private let permissions = PermissionManager()
    private let persistor = AppGroupPersistor()

    private var session: AudioCaptureService.Session?
    private var asrTask: Task<Void, Never>?
    private var levelTask: Task<Void, Never>?

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
        loadPersistedConfig()
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

    private func loadPersistedConfig() {
        switch persistor.load(into: state) {
        case .loaded:
            break
        case .unavailable:
            state.phase = .error(.appGroupUnavailable, message: "App Group 未配置")
        }
    }

    // MARK: - Press handlers

    private func pressBegan() {
        // Allow re-entry from `.denied` and from a finished/cleared
        // `.error` so the user can simply press the mic again after
        // returning from Settings with permission granted — they
        // shouldn't have to wait for an auto-clear timer.
        switch state.phase {
        case .idle, .denied, .error:
            break
        default:
            return
        }
        guard state.mode != .off else { return }
        // Set the intermediate phase SYNCHRONOUSLY so a rapid second
        // press (before the first Task has had a chance to flip phase to
        // .recording) is rejected by the guard above. This fixes the race
        // where the user double-tapped the mic and we started two
        // pipelines at once.
        state.phase = .requestingPermissions
        Task { @MainActor [weak self] in
            guard let self else { return }
            let micGranted = await self.permissions.requestMicPermission()
            guard micGranted else {
                self.state.phase = .denied(.mic)
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
            let speechGranted = await self.permissions.requestSpeechPermission()
            guard speechGranted else {
                self.state.phase = .denied(.speech)
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
                case .capability(let onDevice):
                    self.state.onDeviceSupported = onDevice
                case .partial(let s):
                    lastPartial = s
                    self.state.lastTranscript = s
                case .final(let s):
                    let transcript = s.isEmpty ? lastPartial : s
                    self.handleFinalTranscript(transcript)
                case .error(let m):
                    self.state.phase = .error(.asr(m))
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
        // Reset the on-device flag so the StatusBadge stops showing the
        // cloud-fallback indicator between recordings.
        state.onDeviceSupported = false
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
            } catch let error as LLMError {
                switch error {
                case .noAPIKey:
                    // Don't silently insert the raw transcript — the user
                    // thinks they're getting polished text when really no
                    // key is configured. Show a precise, actionable error.
                    self.state.phase = .error(.llm(error), message: "未配置 API Key · 请在主 App 设置中填写")
                    self.scheduleAutoClearError()
                case .http(401):
                    self.state.phase = .error(.llm(error), message: "API Key 无效 (401) · 请检查主 App 设置")
                    self.scheduleAutoClearError()
                case .http(429), .rateLimited:
                    self.state.phase = .error(.llm(error), message: "API 限流 (429) · 请稍后再试")
                    self.scheduleAutoClearError()
                case .cancelled:
                    // User-initiated cancellation (e.g. mode switch mid-
                    // polish). Do NOT re-insert the original transcript —
                    // the user has already moved on and the partial is
                    // considered discarded.
                    self.state.phase = .idle
                    self.state.lastTranscript = ""
                    return
                default:
                    // Other LLMError variants (transport / decoding /
                    // invalidURL) fall back to raw transcript + generic
                    // error badge, same as the catch-all below.
                    self.textDocumentProxy.insertText(trimmed)
                    self.state.lastTranscript = ""
                    let msg = error.errorDescription ?? "Polishing failed — inserted raw."
                    self.state.phase = .error(.llm(error), message: msg)
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
                self.state.phase = .error(.unknown(msg), message: msg)
                self.scheduleAutoClearError()
            }
        }
    }

    // MARK: - Persistence

    private func persistMode(_ m: State.InputMode) {
        let isRecording = state.phase == .recording
        state.mode = m
        persistor.persist(mode: m)
        if isRecording {
            if m == .off {
                // Switching to .off while recording: drop the partial
                // (no insertion, no LLM). User has explicitly disabled
                // the keyboard, so we honour that immediately.
                stopPipeline()
                state.phase = .idle
                state.lastTranscript = ""
            } else if m == .transcribe {
                // Switching to .transcribe while in .polish: end the
                // recording, the partial will flow through
                // handleFinalTranscript which inserts the raw text in
                // .transcribe mode (no LLM call).
                pressEnded()
            }
        }
    }

    private func persistLocale(_ id: String) {
        state.localeId = id
        persistor.persist(localeId: id)
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
            // Only transient errors auto-clear. `.denied` is sticky: the
            // user needs the message long enough to read it AND decide
            // whether to tap "去设置" or tap the mic to retry. They
            // dismiss it implicitly by doing either of those things.
            switch self.state.phase {
            case .error:
                self.state.phase = .idle
            default:
                break
            }
        }
    }
}
