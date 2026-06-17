// KeyboardViewController.swift
// OSGKeyboard · Keyboard Extension
//
// The principal class for the Custom Keyboard Extension. Manages the
// recording pipeline: AudioCapture -> ASR -> LLM polish -> insertText.

import UIKit
import SwiftUI
import OSGKeyboardShared
import AVFoundation

@objc(KeyboardViewController)
public final class KeyboardViewController: UIInputViewController {

    // MARK: - State

    @MainActor
    private enum Phase: Equatable {
        case idle
        case recording
        case processing
        case error(String)
    }

    // MARK: - Services

    private let audio = AudioCaptureService()
    private lazy var asr: ASRService = ASRServiceFactory.create()
    private let polisher = PolishingService()

    // MARK: - Pipeline state

    private var recordStream: AsyncStream<AudioBufferSnapshot>?
    private var recordContinuation: Task<Void, Never>?
    private var asrTask: Task<Void, Never>?
    private var lastTranscript: String = ""

    // MARK: - UI

    private var hosting: UIHostingController<KeyboardRootView>!
    private var levelTimer: Timer?
    private var currentLevel: Double = 0

    // MARK: - Lifecycle

    public override func viewDidLoad() {
        super.viewDidLoad()
        installSwiftUI()
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        requestMicPermissionIfNeeded()
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        cancelPipeline()
    }

    public override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        cancelPipeline()
    }

    // MARK: - SwiftUI bridge

    private func installSwiftUI() {
        let root = KeyboardRootView(
            phase: .idle,
            level: 0,
            onPressBegan: { [weak self] in self?.pressBegan() },
            onPressEnded:  { [weak self] in self?.pressEnded()  },
            onTap:         { [weak self] in self?.handleTap()   },
            onOpenSettings:{ [weak self] in self?.openHostApp() }
        )
        let host = UIHostingController(rootView: root)
        host.view.backgroundColor = .clear
        addChild(host)
        view.addSubview(host.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        host.didMove(toParent: self)
        self.hosting = host
    }

    private func update(phase: Phase) {
        let snapshot = phase
        let rootPhase: KeyboardRootView.Phase = {
            switch snapshot {
            case .idle:        return .idle
            case .recording:   return .recording
            case .processing:  return .processing
            case .error(let m): return .error(m)
            }
        }()
        hosting.rootView = KeyboardRootView(
            phase: rootPhase,
            level: currentLevel,
            onPressBegan: { [weak self] in self?.pressBegan() },
            onPressEnded:  { [weak self] in self?.pressEnded()  },
            onTap:         { [weak self] in self?.handleTap()   },
            onOpenSettings:{ [weak self] in self?.openHostApp() }
        )
    }

    // MARK: - Press handlers

    private func pressBegan() {
        guard case .idle = currentPhase() else { return }
        requestMicPermissionIfNeeded { [weak self] granted in
            guard let self else { return }
            guard granted else {
                Task { @MainActor in self.update(phase: .error("Microphone denied. Enable in Settings.")) }
                return
            }
            self.startPipeline()
        }
    }

    private func pressEnded() {
        guard case .recording = currentPhase() else { return }
        stopPipelineAndPolish()
    }

    private func handleTap() {
        // Tap = "switch to next keyboard" (system convention)
        advanceToNextInputMode()
    }

    private func openHostApp() {
        guard let url = URL(string: "osgkeyboard://settings") else { return }
        var responder: UIResponder? = self
        while let r = responder {
            if let app = r as? UIApplication {
                app.open(url)
                return
            }
            responder = r.next
        }
        // Fallback: open settings page
        if let url = URL(string: UIApplication.openSettingsURLString) {
            var r: UIResponder? = self
            while let r2 = r {
                if let app = r2 as? UIApplication {
                    app.open(url); return
                }
                r = r2.next
            }
        }
    }

    // MARK: - Pipeline

    private func startPipeline() {
        update(phase: .recording)
        let stream = audio.start()
        recordStream = stream

        // 1) ASR pipeline
        let events = asr.transcribe(stream: stream)
        asrTask = Task { [weak self] in
            guard let self else { return }
            for await event in events {
                switch event {
                case .partial(let s):
                    // optionally show partial in status bar (keep simple — silent)
                    _ = s
                case .final(let s):
                    await MainActor.run { self.lastTranscript = s }
                case .error(let msg):
                    await MainActor.run { self.update(phase: .error("ASR: \(msg)")) }
                }
            }
        }

        // 2) Mock level meter (real impl would tap the buffer)
        startLevelMeter()
    }

    private func stopPipelineAndPolish() {
        stopLevelMeter()
        Task { await audio.stop() }
        asrTask?.cancel()

        let snapshot = lastTranscript
        guard !snapshot.isEmpty else {
            update(phase: .idle)
            return
        }

        update(phase: .processing)

        Task { [weak self] in
            guard let self else { return }
            do {
                let polished = try await self.polisher.polish(snapshot)
                await MainActor.run {
                    self.textDocumentProxy.insertText(polished)
                    self.lastTranscript = ""
                    self.update(phase: .idle)
                }
            } catch {
                // fallback: insert raw transcript
                await MainActor.run {
                    self.textDocumentProxy.insertText(snapshot)
                    self.lastTranscript = ""
                    let msg = (error as? LocalizedError)?.errorDescription ?? "Polishing failed, inserted raw."
                    self.update(phase: .error(msg))
                    // auto-clear error back to idle after 2s
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        if case .error = self.currentPhase() {
                            self.update(phase: .idle)
                        }
                    }
                }
            }
        }
    }

    private func cancelPipeline() {
        asrTask?.cancel()
        asrTask = nil
        Task { await audio.stop() }
        stopLevelMeter()
        lastTranscript = ""
    }

    // MARK: - Permission

    private func requestMicPermissionIfNeeded(completion: ((Bool) -> Void)? = nil) {
        let session = AVAudioSession.sharedInstance()
        switch session.recordPermission {
        case .granted:
            completion?(true)
        case .denied:
            completion?(false)
        case .undetermined:
            session.requestRecordPermission { granted in
                DispatchQueue.main.async { completion?(granted) }
            }
        @unknown default:
            completion?(false)
        }
    }

    // MARK: - Level meter (mock — tap could be replaced with real RMS from AVAudioEngine)

    private func startLevelMeter() {
        stopLevelMeter()
        currentLevel = 0
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            guard let self else { return }
            // Simple pseudo-level — random walk around 0.5 while "recording"
            let delta = Double.random(in: -0.18...0.18)
            self.currentLevel = max(0.15, min(0.95, self.currentLevel + delta))
            // refresh UI
            Task { @MainActor in
                self.update(phase: .recording)
            }
        }
    }

    private func stopLevelMeter() {
        levelTimer?.invalidate()
        levelTimer = nil
        currentLevel = 0
    }

    // MARK: - Helpers

    @MainActor
    private func currentPhase() -> Phase {
        // We don't track phase as a stored property to avoid @MainActor overhead on every read.
        // Instead, derive it from state of services — for simplicity we mirror via update().
        // This shim returns .idle when no record is in flight.
        return recordStream == nil ? .idle : .recording
    }
}
