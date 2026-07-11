// CustomLanguageModelManager.swift
// OSGKeyboard · Shared
//
// Prepares the bundled SFCustomLanguageModelData asset on device and shares
// the compiled LM + Vocab through the App Group container. Both the host app
// and keyboard extension read the same prepared configuration for
// DictationTranscriber content hints.

import Foundation
import Speech
import os

public final class CustomLanguageModelManager: @unchecked Sendable {

    public static let shared = CustomLanguageModelManager()

    public enum PrepareState: Equatable, Sendable {
        case idle
        case preparing
        case ready
        case failed(String)
    }

    struct BundledManifest: Decodable {
        let version: String
        let bin_bytes: Int
        let identifier: String
    }

    private enum Storage {
        static let subdirectory = "CustomLanguageModel/v1"
        static let fingerprintKey = "customLM.preparedFingerprint"
        static let preparedAtKey = "customLM.preparedAt"
        static let lastFailureAtKey = "customLM.lastFailureAt"
        static let attemptCountKey = "customLM.attemptCount"
        static let maxRetryAttempts = 3
        /// Backoff after failure attempts 1, 2, and 3 (seconds).
        static let backoffIntervals: [TimeInterval] = [30, 120, 600]
    }

    private let lock = OSAllocatedUnfairLock()
    private var cachedConfiguration: SFSpeechLanguageModel.Configuration?
    private var state: PrepareState = .idle
    private var prepareTask: Task<Void, Never>?

    private init() {}

    // MARK: - Public API

    /// Returns a prepared configuration for Chinese locales when available.
    public func configurationForTranscription(locale: Locale) -> SFSpeechLanguageModel.Configuration? {
        guard Self.isChineseLocale(locale) else { return nil }
        return lock.withLock { () -> SFSpeechLanguageModel.Configuration? in
            if let cachedConfiguration {
                return cachedConfiguration
            }
            if let loaded = Self.loadCachedConfigurationFromDisk() {
                cachedConfiguration = loaded
                state = .ready
                return loaded
            }
            return nil
        }
    }

    public func currentState() -> PrepareState {
        lock.withLock { state }
    }

    /// Fire-and-forget preparation for the host app. Safe to call repeatedly.
    /// Retries after exponential backoff when a prior attempt failed.
    public func prepareInBackgroundIfNeeded() {
        #if os(iOS)
        guard AppGroup.isAvailable else { return }
        #endif

        let shouldStart = lock.withLock { () -> Bool in
            if case .preparing = state { return false }
            if cachedConfiguration != nil { return false }
            if let loaded = Self.loadCachedConfigurationFromDisk() {
                cachedConfiguration = loaded
                state = .ready
                Self.clearRetryState()
                return false
            }
            if prepareTask != nil { return false }

            if case .failed = state {
                guard Self.canRetryAfterFailure() else { return false }
            } else if !Self.canRetryAfterFailure() {
                return false
            }

            state = .preparing
            return true
        }
        guard shouldStart else { return }

        prepareTask = Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            defer {
                self.lock.withLock { self.prepareTask = nil }
            }
            do {
                _ = try await self.prepareIfNeeded()
            } catch {
                Self.recordFailure()
                self.lock.withLock {
                    self.state = .failed(error.localizedDescription)
                }
                Self.log(
                    "prepare failed (attempt \(Self.storedAttemptCount())): \(error.localizedDescription)"
                )
            }
        }
    }

    /// Prepares the bundled training asset into the App Group container.
    @discardableResult
    public func prepareIfNeeded() async throws -> SFSpeechLanguageModel.Configuration? {
        if let existing = configurationForTranscription(locale: Locale(identifier: "zh-Hans")) {
            lock.withLock { state = .ready }
            Self.clearRetryState()
            return existing
        }

        guard Self.canRetryAfterFailure() else {
            throw PrepareError.retryBudgetExhausted
        }

        guard let manifest = Self.bundledManifest() else {
            throw PrepareError.missingManifest
        }
        guard let assetURL = Self.bundledTrainingAssetURL() else {
            throw PrepareError.missingTrainingAsset
        }
        guard let preparedDir = Self.preparedDirectoryURL() else {
            throw PrepareError.missingAppGroupContainer
        }

        let fingerprint = Self.fingerprint(for: manifest)
        if Self.storedFingerprint() == fingerprint,
           let cached = Self.loadCachedConfigurationFromDisk() {
            lock.withLock {
                cachedConfiguration = cached
                state = .ready
            }
            Self.clearRetryState()
            return cached
        }

        lock.withLock { state = .preparing }

        let languageModelURL = preparedDir.appendingPathComponent("LM")
        let vocabularyURL = preparedDir.appendingPathComponent("Vocab")
        try Self.removeItemIfExists(at: languageModelURL)
        try Self.removeItemIfExists(at: vocabularyURL)

        let configuration = SFSpeechLanguageModel.Configuration(
            languageModel: languageModelURL,
            vocabulary: vocabularyURL
        )

        Self.log("preparing custom LM (\(manifest.bin_bytes) byte asset)…")
        try await Self.prepareLanguageModel(assetURL: assetURL, configuration: configuration)

        guard FileManager.default.fileExists(atPath: languageModelURL.path),
              FileManager.default.fileExists(atPath: vocabularyURL.path) else {
            throw PrepareError.missingPreparedArtifacts
        }

        Self.persistenceDefaults.set(fingerprint, forKey: Storage.fingerprintKey)
        Self.persistenceDefaults.set(Date().timeIntervalSince1970, forKey: Storage.preparedAtKey)
        Self.clearRetryState()

        lock.withLock {
            cachedConfiguration = configuration
            state = .ready
        }

        Self.log("custom LM ready at \(preparedDir.path)")
        return configuration
    }

    // MARK: - DictationTranscriber factory (iOS host app)

    #if os(iOS)
    public static func makeDictationTranscriber(
        locale: Locale,
        lmConfiguration: SFSpeechLanguageModel.Configuration?
    ) -> DictationTranscriber {
        let preset = DictationTranscriber.Preset.progressiveLongDictation
        guard let lmConfiguration, isChineseLocale(locale) else {
            return DictationTranscriber(locale: locale, preset: preset)
        }

        let contentHints = preset.contentHints.union([
            .customizedLanguage(modelConfiguration: lmConfiguration),
        ])
        return DictationTranscriber(
            locale: locale,
            contentHints: contentHints,
            transcriptionOptions: preset.transcriptionOptions,
            reportingOptions: preset.reportingOptions,
            attributeOptions: preset.attributeOptions
        )
    }
    #endif

    // MARK: - Legacy Speech request (macOS Apple Speech fallback)

    /// Up to 100 short phrases for `SFSpeechRecognitionRequest.contextualStrings`.
    public static func contextualStringsForRecognition(
        bias: LocalASRBiasPayload?,
        maxCount: Int = 100
    ) -> [String] {
        guard let bias, !bias.hardHotwords.isEmpty else { return [] }
        return Array(bias.hardHotwords.prefix(max(1, maxCount)))
    }

    /// Applies bundled CLM + optional contextual strings to a legacy on-device request.
    public static func applyCustomLanguageModel(
        to request: SFSpeechURLRecognitionRequest,
        locale: Locale,
        bias: LocalASRBiasPayload?
    ) {
        request.requiresOnDeviceRecognition = true
        if let configuration = shared.configurationForTranscription(locale: locale) {
            request.customizedLanguageModel = configuration
        }
        let phrases = contextualStringsForRecognition(bias: bias)
        if !phrases.isEmpty {
            request.contextualStrings = phrases
        }
    }

    // MARK: - Bundle / disk helpers

    private static var resourceBundle: Bundle {
        Bundle(for: CustomLanguageModelManager.self)
    }

    static func bundledTrainingAssetURL() -> URL? {
        if let url = resourceBundle.url(
            forResource: "OSGKeyboardCLM",
            withExtension: "bin",
            subdirectory: Storage.subdirectory
        ) {
            return url
        }
        return resourceBundle.url(forResource: "OSGKeyboardCLM", withExtension: "bin")
    }

    static func bundledManifest() -> BundledManifest? {
        let manifestURL =
            resourceBundle.url(
                forResource: "compiled-manifest",
                withExtension: "json",
                subdirectory: Storage.subdirectory
            )
            ?? resourceBundle.url(forResource: "compiled-manifest", withExtension: "json")
        guard let manifestURL,
              let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(BundledManifest.self, from: data)
        else {
            return nil
        }
        return manifest
    }

    static func preparedDirectoryURL() -> URL? {
        if let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: AppGroup.identifier
        ) {
            let directory = container.appendingPathComponent(Storage.subdirectory, isDirectory: true)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return directory
        }
        #if os(macOS)
        guard let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            return nil
        }
        let directory = appSupport
            .appendingPathComponent("OSGKeyboard", isDirectory: true)
            .appendingPathComponent(Storage.subdirectory, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
        #else
        return nil
        #endif
    }

    static func loadCachedConfigurationFromDisk() -> SFSpeechLanguageModel.Configuration? {
        guard let manifest = bundledManifest(),
              storedFingerprint() == fingerprint(for: manifest),
              let preparedDir = preparedDirectoryURL()
        else {
            return nil
        }

        let languageModelURL = preparedDir.appendingPathComponent("LM")
        let vocabularyURL = preparedDir.appendingPathComponent("Vocab")
        let fm = FileManager.default
        guard fm.fileExists(atPath: languageModelURL.path),
              fm.fileExists(atPath: vocabularyURL.path) else {
            return nil
        }

        return SFSpeechLanguageModel.Configuration(
            languageModel: languageModelURL,
            vocabulary: vocabularyURL
        )
    }

    static func isChineseLocale(_ locale: Locale) -> Bool {
        locale.identifier(.bcp47).lowercased().hasPrefix("zh")
    }

    private static func fingerprint(for manifest: BundledManifest) -> String {
        "\(manifest.identifier)|\(manifest.version)|\(manifest.bin_bytes)"
    }

    private static func storedFingerprint() -> String? {
        persistenceDefaults.string(forKey: Storage.fingerprintKey)
    }

    private static func removeItemIfExists(at url: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path) {
            try fm.removeItem(at: url)
        }
    }

    private static func prepareLanguageModel(
        assetURL: URL,
        configuration: SFSpeechLanguageModel.Configuration
    ) async throws {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            SFSpeechLanguageModel.prepareCustomLanguageModel(
                for: assetURL,
                configuration: configuration
            ) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    // MARK: - Retry / backoff

    private static var persistenceDefaults: UserDefaults {
        AppGroup.defaultsIfAvailable ?? .standard
    }

    private static func storedAttemptCount() -> Int {
        persistenceDefaults.integer(forKey: Storage.attemptCountKey)
    }

    private static func storedLastFailureAt() -> TimeInterval? {
        let value = persistenceDefaults.double(forKey: Storage.lastFailureAtKey)
        return value > 0 ? value : nil
    }

    private static func recordFailure() {
        let nextAttempt = storedAttemptCount() + 1
        persistenceDefaults.set(nextAttempt, forKey: Storage.attemptCountKey)
        persistenceDefaults.set(Date().timeIntervalSince1970, forKey: Storage.lastFailureAtKey)
    }

    private static func clearRetryState() {
        persistenceDefaults.removeObject(forKey: Storage.attemptCountKey)
        persistenceDefaults.removeObject(forKey: Storage.lastFailureAtKey)
    }

    /// Returns false when retry budget is exhausted or backoff has not elapsed.
    private static func canRetryAfterFailure() -> Bool {
        let attempts = storedAttemptCount()
        guard attempts > 0 else { return true }
        guard attempts <= Storage.maxRetryAttempts else { return false }

        guard let lastFailureAt = storedLastFailureAt() else { return true }
        let backoffIndex = min(attempts - 1, Storage.backoffIntervals.count - 1)
        let requiredDelay = Storage.backoffIntervals[backoffIndex]
        let elapsed = Date().timeIntervalSince1970 - lastFailureAt
        return elapsed >= requiredDelay
    }

    private static func log(_ message: String) {
        OSGLog.clm.info("\(message, privacy: .public)")
    }

    enum PrepareError: LocalizedError {
        case missingManifest
        case missingTrainingAsset
        case missingAppGroupContainer
        case missingPreparedArtifacts
        case retryBudgetExhausted

        var errorDescription: String? {
            switch self {
            case .missingManifest:
                return "Missing bundled custom language model manifest."
            case .missingTrainingAsset:
                return "Missing bundled custom language model training asset."
            case .missingAppGroupContainer:
                return "App Group container unavailable for custom language model preparation."
            case .missingPreparedArtifacts:
                return "Custom language model preparation did not produce LM/Vocab artifacts."
            case .retryBudgetExhausted:
                return "Custom language model preparation retry budget exhausted."
            }
        }
    }
}
