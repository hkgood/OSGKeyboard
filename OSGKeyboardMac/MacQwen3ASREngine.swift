// MacQwen3ASREngine.swift
// OSGKeyboard · Mac
//
// Singleton actor that loads, warms up, and runs Qwen3-ASR via mlx-swift-asr.
// Model load + Metal JIT warmup take several seconds — call `prepareIfNeeded`
// at launch so the first dictation is fast.

import Foundation
import MLXASR

/// Lifecycle of the on-disk MLX model inside the app process.
enum MacQwen3EnginePhase: Sendable, Equatable {
    case idle
    case loading
    case ready
    case failed(String)
}

actor MacQwen3ASREngine {
    static let shared = MacQwen3ASREngine()

    private var stt: Qwen3ASRSTT?
    private var loadedModelPath: String?
    private(set) var phase: MacQwen3EnginePhase = .idle

    private init() {}

    /// Load and warm up the model when the path changes or nothing is loaded yet.
    func prepareIfNeeded(modelPath: String) async throws {
        if loadedModelPath == modelPath, stt != nil, phase == .ready { return }

        phase = .loading
        stt = nil
        loadedModelPath = nil

        let directory = URL(fileURLWithPath: modelPath, isDirectory: true)
        do {
            let instance = try await Qwen3ASRSTT.loadWithWarmup(from: directory)
            stt = instance
            loadedModelPath = modelPath
            phase = .ready
        } catch {
            let detail = error.localizedDescription
            phase = .failed(detail)
            throw MacLocalASRError.qwen3LoadFailed(detail)
        }
    }

    /// Transcribe mono 16 kHz float PCM. Ensures the model is loaded first.
    func transcribe(
        samples: [Float],
        language: String?,
        modelPath: String
    ) async throws -> String {
        try await prepareIfNeeded(modelPath: modelPath)
        guard let stt else {
            throw MacLocalASRError.qwen3LoadFailed("Engine not initialized")
        }

        let result = try await stt.transcribe(audio: samples, language: language)
        let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw MacLocalASRError.emptyTranscript
        }
        return text
    }

    /// Drop cached weights (e.g. after the user changes the model folder).
    func unload() {
        stt = nil
        loadedModelPath = nil
        phase = .idle
    }
}

enum MacQwen3LanguageHint {
    /// Map persisted BCP-47 locale ids to Qwen3 prompt language names.
    /// Returns `nil` for auto-detect.
    static func from(locale: Locale) -> String? {
        let raw = locale.identifier.lowercased()
        if raw.isEmpty || raw == "auto" { return nil }
        if raw.hasPrefix("zh") { return "Chinese" }
        if raw.hasPrefix("en") { return "English" }
        if raw.hasPrefix("ja") { return "Japanese" }
        if raw.hasPrefix("ko") { return "Korean" }
        if raw.hasPrefix("fr") { return "French" }
        if raw.hasPrefix("de") { return "German" }
        if raw.hasPrefix("es") { return "Spanish" }
        if raw.hasPrefix("pt") { return "Portuguese" }
        if raw.hasPrefix("ru") { return "Russian" }
        if raw.hasPrefix("ar") { return "Arabic" }
        return nil
    }
}
