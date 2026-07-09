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
        case .dashboard: return "square.grid.2x2"
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
    @Published var isProcessing = false
    @Published var transcript = ""
    @Published var statusMessage = ""
    @Published var audioLevel: Float = 0
    @Published var sessionSeconds: Int = 0
    @Published var foregroundAppName: String?
    @Published var dictionaryRevision = 0

    @Published var autoPasteEnabled: Bool
    @Published var hotkeyEnabled: Bool

    @Published var config: ProviderConfig

    let defaults: UserDefaults
    private let recorder = MacAudioRecorder()
    private let hotkeyService = MacHotkeyService()
    private var levelTimer: Timer?
    private var sessionTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    let usageStatistics: UsageStatisticsStore
    let speechHistory = SpeechHistoryStore.shared

    private enum StoredKeys {
        static let autoPaste = "mac.autoPasteEnabled"
        static let hotkey = "mac.hotkeyEnabled"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.config = ProviderConfig(defaults: defaults)
        self.usageStatistics = UsageStatisticsStore(defaults: defaults)
        self.autoPasteEnabled = defaults.object(forKey: StoredKeys.autoPaste) as? Bool ?? true
        self.hotkeyEnabled = defaults.object(forKey: StoredKeys.hotkey) as? Bool ?? true

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
        warmUpQwen3IfNeeded()
    }

    /// Pre-load MLX weights + Metal shaders so the first dictation is fast.
    func warmUpQwen3IfNeeded() {
        guard config.engineMode == "local",
              let model = MacLocalASRService.selectedModelDefinition(),
              model.backend == .mlx,
              MacLocalASRService.isModelInstalled(model) else { return }
        let path = MacLocalASRPreferences.qwen3ModelPath
        Task.detached(priority: .utility) {
            _ = try? await MacQwen3ASREngine.shared.prepareIfNeeded(modelPath: path)
        }
    }

    func reloadConfigFromCloud() {
        config.reloadFromPersistedStorage()
        statusMessage = MacL10n.string("mac.status.ready", language: config.uiLanguage)
        warmUpQwen3IfNeeded()
    }

    func refreshDictionaryFromCloud() {
        dictionaryRevision += 1
    }

    // MARK: - Derived

    var selectableProviders: [LLMProvider] {
        LLMProvider.presets.filter {
            $0.isUserSelectable && $0.cloudASRStrategy != .localFallback
        }
    }

    var dictionaryTermCount: Int {
        _ = dictionaryRevision
        return AppGroupStore(defaults: defaults).personalDictionary.entries.count
    }

    var currentWordCount: Int {
        transcript.split { $0 == " " || $0 == "\n" || $0 == "\t" }.count
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
        if let model = MacLocalASRService.selectedModelDefinition() {
            return MacLocalASRService.isModelInstalled(model)
        }
        return MacLocalASRPreferences.qwen3ModelIsInstalled()
    }

    /// Context-aware warning when local engine is selected but the active model is not ready.
    var localModelWarningMessage: String? {
        _ = localModelRevision
        guard config.engineMode == "local" else { return nil }
        if localModelReady { return nil }
        guard let model = MacLocalASRService.selectedModelDefinition() else {
            return MacL10n.string("mac.settings.localModelFallbackApple", language: config.uiLanguage)
        }
        if model.installKind == .manual {
            return MacL10n.string("mac.settings.mlxModelMissing", language: config.uiLanguage)
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

    var qwen3ModelInstalled: Bool {
        MacLocalASRPreferences.qwen3ModelIsInstalled()
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

    func setEngineMode(_ mode: String) {
        config.engineMode = mode
        if mode == "local" { warmUpQwen3IfNeeded() }
    }

    // MARK: - Recording

    func toggleRecording() {
        if isRecording { finishRecording() } else { beginRecording() }
    }

    func beginRecording() {
        guard !isProcessing else { return }
        let store = AppGroupStore(defaults: defaults)
        MacAppContextService.captureAndPersist(to: store)
        refreshForegroundAppName()

        do {
            try recorder.start()
            isRecording = true
            transcript = ""
            statusMessage = MacL10n.string("mac.status.listening", language: config.uiLanguage)
            startTimers()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func finishRecording() {
        guard isRecording else { return }
        isRecording = false
        isProcessing = true
        statusMessage = MacL10n.string("mac.status.transcribing", language: config.uiLanguage)
        stopTimers()
        audioLevel = 0
        let samples = recorder.stop()
        let store = AppGroupStore(defaults: defaults)

        Task { [weak self] in
            guard let self else { return }
            do {
                let text = try await MacDictationPipeline.run(samples: samples, store: store)
                self.transcript = text
                let pasted = try self.deliver(text)
                self.recordUsage(for: text)
                self.speechHistory.append(text: text)
                self.statusMessage = self.statusAfterDelivery(pasted: pasted)
            } catch {
                self.statusMessage = error.localizedDescription
            }
            self.isProcessing = false
        }
    }

    private func deliver(_ text: String) throws -> Bool {
        try MacTextInsertionService.insert(text, autoPaste: autoPasteEnabled)
    }

    private func statusAfterDelivery(pasted: Bool) -> String {
        let lang = config.uiLanguage
        if autoPasteEnabled, pasted {
            return MacL10n.string("mac.status.copiedAndPasted", language: lang)
        }
        if autoPasteEnabled, !pasted {
            return MacL10n.string("mac.status.copied", language: lang)
        }
        return MacL10n.string("mac.status.copied", language: lang)
    }

    private func wireHotkeyService() {
        hotkeyService.onPressBegan = { [weak self] in
            self?.beginRecording()
        }
        hotkeyService.onPressEnded = { [weak self] in
            self?.finishRecording()
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

    func refreshForegroundAppName() {
        foregroundAppName = MacAppContextService.frontmostApplicationName()
    }
}
