// MacDictationViewModel.swift
// OSGKeyboard · Mac
//
// Drives the whole macOS window: navigation, recording, hotkey, iCloud-backed
// settings, foreground-app context, and text insertion.

import AppKit
import Combine
import SwiftUI

/// Top-level navigation destinations, mirroring the iOS app's tabs.
enum MacSection: String, CaseIterable, Identifiable {
    case dashboard
    case history
    case dictionary
    case settings

    var id: String { rawValue }

    func title(language: AppUILanguage) -> String {
        switch self {
        case .dashboard: return MacL10n.string("mac.section.dashboard", language: language)
        case .history: return MacL10n.string("mac.section.history", language: language)
        case .dictionary: return MacL10n.string("mac.section.dictionary", language: language)
        case .settings: return MacL10n.string("mac.section.settings", language: language)
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard: return "house"
        case .history: return "clock.arrow.circlepath"
        case .dictionary: return "character.book.closed"
        case .settings: return "gearshape"
        }
    }
}

@MainActor
final class MacDictationViewModel: ObservableObject {
    /// Shared instance so the SwiftUI window and the AppKit menu-bar popover
    /// (see `MacAppDelegate`) drive the exact same recording / settings state.
    static let shared = MacDictationViewModel()

    @Published var selectedSection: MacSection = .dashboard

    @Published var isRecording = false
    /// True while microphone permission / engine start is in flight.
    /// Drives the overlay so the HUD appears on Option-down immediately,
    /// instead of waiting for the async `beginRecording` to finish.
    @Published private(set) var isPreparingToRecord = false
    @Published var isProcessing = false
    /// True once live ASR has surfaced at least one partial during this take.
    @Published private(set) var isStreamingPartial = false
    /// Live text for the *current* take (drives the floating HUD). Reset on
    /// every new Option press.
    @Published var transcript = ""
    /// Running overview of every finalized take this app run — the Home card
    /// accumulates sessions here so earlier utterances are never overwritten.
    @Published private(set) var overviewTranscript = ""
    @Published var statusMessage = ""
    @Published var audioLevel: Float = 0
    @Published var sessionSeconds: Int = 0
    @Published var foregroundAppName: String?
    @Published var dictionaryRevision = 0

    @Published var autoPasteEnabled: Bool
    @Published var hotkeyEnabled: Bool
    @Published var hotkeyTrigger: MacHotkeyTrigger

    @Published var config: ProviderConfig

    let defaults: UserDefaults
    private let recorder = MacAudioRecorder()
    private let hotkeyService = MacHotkeyService()
    private var levelTimer: Timer?
    private var sessionTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    /// In-flight `beginRecording` started by the hotkey — cancelled if the
    /// key is released before the engine is ready (avoids a stuck session).
    private var hotkeyBeginTask: Task<Void, Never>?
    /// Live chunked / streaming ASR while recording (cloud or MLX local).
    /// Finished in `finishRecording` so partials can become the final draft.
    private var liveCaptureTask: Task<MacLiveASRCaptureResult, Never>?
    private var liveFinishContinuation: AsyncStream<Void>.Continuation?

    let usageStatistics: UsageStatisticsStore
    let speechHistory = SpeechHistoryStore.shared

    private enum StoredKeys {
        static let autoPaste = "mac.autoPasteEnabled"
        static let hotkey = "mac.hotkeyEnabled"
        static let hotkeyTrigger = MacHotkeyTrigger.storageKey
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.config = ProviderConfig(defaults: defaults)
        self.usageStatistics = UsageStatisticsStore(defaults: defaults)
        self.autoPasteEnabled = defaults.object(forKey: StoredKeys.autoPaste) as? Bool ?? true
        // Global hotkey is always on — the settings toggle was removed, so any
        // previously-stored "off" value is intentionally ignored.
        self.hotkeyEnabled = true
        self.hotkeyTrigger = MacHotkeyTrigger(
            rawValue: defaults.string(forKey: StoredKeys.hotkeyTrigger) ?? ""
        ) ?? .rightOption

        MacICloudSyncBootstrap.configure(defaults: defaults)
        statusMessage = MacL10n.string("mac.status.ready", language: config.uiLanguage)
        wireHotkeyService()
        forwardNestedObjectChanges()
    }

    /// `config` is a nested `ObservableObject`; without forwarding its
    /// `objectWillChange`, SwiftUI views that observe only the view model
    /// won't refresh when settings (e.g. engine mode / provider) change.
    private func forwardNestedObjectChanges() {
        config.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
        usageStatistics.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    func onAppear() async {
        await MacICloudSyncBootstrap.pullIfEnabled()
        refreshForegroundAppName()
    }

    func reloadConfigFromCloud() {
        config.reloadFromPersistedStorage()
        statusMessage = MacL10n.string("mac.status.ready", language: config.uiLanguage)
    }

    func refreshDictionaryFromCloud() {
        dictionaryRevision += 1
    }

    // MARK: - Derived

    var polishSelectableProviders: [LLMProvider] {
        LLMProvider.userSelectablePresets
    }

    var asrSelectableProviders: [LLMProvider] {
        LLMProvider.asrSelectablePresets
    }

    var selectableProviders: [LLMProvider] {
        asrSelectableProviders
    }

    var dictionaryTermCount: Int {
        _ = dictionaryRevision
        return AppGroupStore(defaults: defaults).personalDictionary.entries.count
    }

    var currentWordCount: Int {
        transcript.split { $0 == " " || $0 == "\n" || $0 == "\t" }.count
    }

    /// Text the Home overview card shows: all finalized takes plus the live
    /// current take appended at the end while recording / processing.
    var homePreviewText: String {
        let live = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        if live.isEmpty { return overviewTranscript }
        if overviewTranscript.isEmpty { return live }
        return overviewTranscript + "\n" + live
    }

    var hasHomePreview: Bool { !homePreviewText.isEmpty }

    /// Clears the Home overview (the running session log), leaving any live take.
    func clearOverview() {
        overviewTranscript = ""
    }

    var isCloudMode: Bool { config.engineMode == "cloud" }

    var languageLabel: String {
        let id = config.localeId.isEmpty ? "zh-CN" : config.localeId
        return Locale.current.localizedString(forIdentifier: id) ?? id
    }

    var sessionTimeLabel: String {
        let minutes = sessionSeconds / 60
        let seconds = sessionSeconds % 60
        if minutes > 0 { return "\(minutes)m \(seconds)s" }
        return "\(seconds)s"
    }

    var localModelReady: Bool {
        _ = localModelRevision
        guard let model = MacLocalASRService.selectedModelDefinition() else { return false }
        return MacLocalASRService.isModelInstalled(model)
    }

    /// Context-aware warning when local engine is selected but the active model is not ready.
    var localModelWarningMessage: String? {
        _ = localModelRevision
        guard config.engineMode == "local" else { return nil }
        if localModelReady { return nil }
        guard let model = MacLocalASRService.selectedModelDefinition() else {
            return MacL10n.string("mac.settings.localModelFallbackApple", language: config.uiLanguage)
        }
        return MacL10n.format(
            "mac.settings.selectedModelMissing",
            language: config.uiLanguage,
            model.displayName
        )
    }

    @Published private(set) var localModelRevision = 0

    func bumpLocalModelRevision() {
        localModelRevision += 1
        objectWillChange.send()
    }

    // MARK: - Preferences

    func setAutoPasteEnabled(_ enabled: Bool) {
        autoPasteEnabled = enabled
        defaults.set(enabled, forKey: StoredKeys.autoPaste)
    }

    func setHotkeyEnabled(_ enabled: Bool) {
        hotkeyEnabled = enabled
        defaults.set(enabled, forKey: StoredKeys.hotkey)
        hotkeyService.setEnabled(enabled)
        if enabled { hotkeyService.start() } else { hotkeyService.stop() }
    }

    func setHotkeyTrigger(_ trigger: MacHotkeyTrigger) {
        hotkeyTrigger = trigger
        defaults.set(trigger.rawValue, forKey: StoredKeys.hotkeyTrigger)
        hotkeyService.trigger = trigger
    }

    func setEngineMode(_ mode: String) {
        config.engineMode = mode
    }

    // MARK: - Recording

    func toggleRecording() {
        if isRecording || isPreparingToRecord {
            cancelOrFinishRecording()
        } else {
            Task { await beginRecording() }
        }
    }

    func beginRecording() async {
        guard !isProcessing, !isRecording, !isPreparingToRecord else { return }
        isPreparingToRecord = true
        let store = AppGroupStore(defaults: defaults)
        MacAppContextService.captureAndPersist(to: store)
        refreshForegroundAppName()

        do {
            try await recorder.start()
            // Hotkey may have been released while we awaited mic permission /
            // engine start — abandon cleanly instead of latching a stuck session.
            isPreparingToRecord = false
            if Task.isCancelled {
                _ = recorder.stop()
                return
            }
            isRecording = true
            transcript = ""
            isStreamingPartial = false
            statusMessage = MacL10n.string("mac.status.listening", language: config.uiLanguage)
            startTimers()
            startLiveCaptureIfSupported(store: store)
            // Tiny race: Option released between the cancel check and
            // `isRecording = true`. Treat it as end-of-hold and finish.
            if Task.isCancelled {
                finishRecording()
            }
        } catch {
            isPreparingToRecord = false
            if !Task.isCancelled {
                statusMessage = error.localizedDescription
            }
        }
    }

    func finishRecording() {
        guard isRecording else { return }
        isRecording = false
        isProcessing = true
        let hadLivePartial = isStreamingPartial
        statusMessage = MacL10n.string(
            hadLivePartial ? "mac.status.polishing" : "mac.status.transcribing",
            language: config.uiLanguage
        )
        stopTimers()
        audioLevel = 0
        let store = AppGroupStore(defaults: defaults)
        let usesDeferredStop = MacDictationPipeline.supportsLivePartials(store: store)
            && store.engineMode == "local"
            && MacLocalASRService.usesMLXLiveStreaming()
        let samples: [Float]
        if usesDeferredStop {
            liveFinishContinuation?.yield(())
            samples = []
        } else {
            liveFinishContinuation?.finish()
            liveFinishContinuation = nil
            samples = recorder.stop()
        }
        let liveTask = liveCaptureTask
        liveCaptureTask = nil

        Task { [weak self] in
            guard let self else { return }
            do {
                let result: MacDictationResult
                let capturedSamples: [Float]
                if let liveTask {
                    let capture = await Self.awaitLiveCapture(liveTask)
                    if usesDeferredStop {
                        capturedSamples = self.recorder.stop()
                    } else {
                        capturedSamples = samples
                    }
                    let trimmedLive = capture.raw.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !capture.shouldFallbackToBatch, !trimmedLive.isEmpty {
                        if self.transcript.isEmpty {
                            self.transcript = trimmedLive
                        }
                        result = try await MacDictationPipeline.polishCapturedASR(
                            raw: capture.raw,
                            store: store,
                            localBias: capture.localBias,
                            chunkWarning: capture.chunkWarning
                        )
                    } else {
                        result = try await MacDictationPipeline.run(
                            samples: capturedSamples,
                            store: store,
                            onPartial: { [weak self] partial in
                                Task { @MainActor in
                                    self?.transcript = partial
                                }
                            }
                        )
                    }
                } else {
                    capturedSamples = usesDeferredStop ? self.recorder.stop() : samples
                    result = try await MacDictationPipeline.run(
                        samples: capturedSamples,
                        store: store,
                        onPartial: { [weak self] partial in
                            Task { @MainActor in
                                self?.transcript = partial
                            }
                        }
                    )
                }
                self.transcript = result.text
                let pasted = try await self.deliver(result.text)
                self.recordUsage(for: result.text)
                self.speechHistory.append(text: result.text)
                self.appendToOverview(result.text)
                self.statusMessage = self.statusAfterDelivery(
                    pasted: pasted,
                    polishWarning: result.polishWarning,
                    chunkWarning: result.chunkWarning
                )
            } catch {
                self.statusMessage = error.localizedDescription
            }
            // The finalized take now lives in the overview; clear the live take
            // so the HUD flashes its completion state and the next press starts
            // fresh without overwriting the Home overview.
            self.transcript = ""
            self.isStreamingPartial = false
            self.isProcessing = false
            self.liveFinishContinuation?.finish()
            self.liveFinishContinuation = nil
        }
    }

    private func startLiveCaptureIfSupported(store: AppGroupStore) {
        guard MacDictationPipeline.supportsLivePartials(store: store) else { return }
        let stream = recorder.makeSnapshotStream()
        let (finishStream, finishContinuation) = AsyncStream<Void>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        liveFinishContinuation = finishContinuation
        liveCaptureTask = Task { [weak self] in
            await MacDictationPipeline.captureLive(
                stream: stream,
                finishSignal: finishStream,
                store: store,
                onPartial: { [weak self] partial in
                    Task { @MainActor in
                        guard let self else { return }
                        guard self.isRecording || self.isProcessing else { return }
                        let trimmed = partial.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        self.transcript = partial
                        self.isStreamingPartial = true
                    }
                }
            )
        }
    }

    private func cancelLiveCapture() {
        liveFinishContinuation?.finish()
        liveFinishContinuation = nil
        liveCaptureTask?.cancel()
        liveCaptureTask = nil
        isStreamingPartial = false
    }

    /// Hard timeout so a hung realtime ASR drain cannot leave `isProcessing` stuck.
    private static func awaitLiveCapture(
        _ task: Task<MacLiveASRCaptureResult, Never>
    ) async -> MacLiveASRCaptureResult {
        await HardTimeout.value(
            seconds: FlowSessionKeys.cloudASRWaitTimeout,
            operation: { await task.value },
            onTimeout: {
                task.cancel()
                return MacLiveASRCaptureResult(
                    raw: "",
                    chunkWarning: nil,
                    localBias: nil,
                    shouldFallbackToBatch: true
                )
            }
        )
    }

    /// Stops an in-flight prepare, or finishes an active recording.
    private func cancelOrFinishRecording() {
        if isRecording {
            finishRecording()
            return
        }
        if isPreparingToRecord {
            hotkeyBeginTask?.cancel()
            hotkeyBeginTask = nil
            // If the button-triggered prepare wasn't tracked by hotkeyBeginTask,
            // still clear the preparing flag and stop any engine that raced in.
            isPreparingToRecord = false
            cancelLiveCapture()
            _ = recorder.stop()
        }
    }

    private func deliver(_ text: String) async throws -> Bool {
        try await MacTextInsertionService.insert(text, autoPaste: autoPasteEnabled)
    }

    private func statusAfterDelivery(
        pasted: Bool,
        polishWarning: String? = nil,
        chunkWarning: String? = nil
    ) -> String {
        let lang = config.uiLanguage
        let base: String
        if autoPasteEnabled, pasted {
            base = MacL10n.string("mac.status.copiedAndPasted", language: lang)
        } else if autoPasteEnabled, !pasted {
            base = MacL10n.string("mac.status.copied", language: lang)
        } else {
            base = MacL10n.string("mac.status.copied", language: lang)
        }

        if let polishWarning, !polishWarning.isEmpty {
            return MacL10n.format("mac.status.deliveryWithNote", language: lang, base, polishWarning)
        }
        if let chunkWarning, !chunkWarning.isEmpty {
            return MacL10n.format("mac.status.deliveryWithNote", language: lang, base, chunkWarning)
        }
        return base
    }

    private func wireHotkeyService() {
        hotkeyService.trigger = hotkeyTrigger
        hotkeyService.onPressBegan = { [weak self] in
            guard let self else { return }
            self.hotkeyBeginTask?.cancel()
            self.hotkeyBeginTask = Task { [weak self] in
                await self?.beginRecording()
            }
        }
        hotkeyService.onPressEnded = { [weak self] in
            guard let self else { return }
            // Cancel a still-preparing start so a quick Option tap never
            // latches recording. If recording already began, finish it.
            if self.isRecording {
                self.hotkeyBeginTask = nil
                self.finishRecording()
            } else {
                self.hotkeyBeginTask?.cancel()
                self.hotkeyBeginTask = nil
            }
        }
        if hotkeyEnabled { hotkeyService.start() }
    }

    private func startTimers() {
        sessionSeconds = 0
        let levelTimer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.audioLevel = self.recorder.level() }
        }
        let sessionTimer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.sessionSeconds += 1 }
        }
        RunLoop.main.add(levelTimer, forMode: .common)
        RunLoop.main.add(sessionTimer, forMode: .common)
        self.levelTimer = levelTimer
        self.sessionTimer = sessionTimer
    }

    private func stopTimers() {
        levelTimer?.invalidate()
        sessionTimer?.invalidate()
        levelTimer = nil
        sessionTimer = nil
    }

    private func appendToOverview(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        overviewTranscript = overviewTranscript.isEmpty
            ? trimmed
            : overviewTranscript + "\n" + trimmed
    }

    private func recordUsage(for text: String) {
        usageStatistics.recordUtterance(
            text: text,
            duration: TimeInterval(sessionSeconds),
            wasTranslation: config.isTranslationEffective
        )
    }

    func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    func selectProvider(_ provider: LLMProvider) {
        config.apply(preset: provider)
    }

    func selectAsrProvider(_ provider: LLMProvider) {
        config.applyAsr(preset: provider)
    }

    func refreshForegroundAppName() {
        foregroundAppName = MacAppContextService.frontmostApplicationName()
    }
}
