// MacQwen3LocalASR.swift
// OSGKeyboard · Mac
//
// Qwen3-ASR-1.7B (MLX) via mlx-swift-asr. Expects a converted model directory
// containing config.json, model.safetensors, and tokenizer files.

import Foundation

enum MacQwen3LocalASR {
    /// Transcribe with Qwen3-ASR MLX weights at `modelPath`.
    static func transcribe(
        samples: [Float],
        sampleRate: Int,
        locale: Locale,
        modelPath: String,
        bias: LocalASRBiasPayload? = nil
    ) async throws -> String {
        guard MacLocalASRPreferences.qwen3ModelIsInstalled(at: modelPath) else {
            throw MacLocalASRError.qwen3ModelMissing
        }
        guard sampleRate == 16_000 else {
            throw MacLocalASRError.qwen3InferenceFailed(
                "Qwen3-ASR expects 16 kHz audio (got \(sampleRate) Hz)"
            )
        }

        let language = MacQwen3LanguageHint.from(locale: locale)
        let context = bias?.promptBias?.trimmingCharacters(in: .whitespacesAndNewlines)
        let promptContext = (context?.isEmpty == false) ? context : nil
        do {
            return try await MacQwen3ASREngine.shared.transcribe(
                samples: samples,
                language: language,
                modelPath: modelPath,
                context: promptContext
            )
        } catch let error as MacLocalASRError {
            throw error
        } catch {
            throw MacLocalASRError.qwen3InferenceFailed(error.localizedDescription)
        }
    }
}
