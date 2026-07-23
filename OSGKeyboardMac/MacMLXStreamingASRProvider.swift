// MacMLXStreamingASRProvider.swift
// OSGKeyboard · Mac
//
// Loads and caches Qwen3 MLX models; builds streaming sessions with bias.

import Foundation
import MLX
import MLXAudioSTT

actor MacMLXStreamingASRProvider {
    static let shared = MacMLXStreamingASRProvider()

    private var cachedModelId: String?
    private var cachedModel: Qwen3ASRModel?
    private var didWarmup = false

    func prepare(model: LocalASRModelDefinition) async throws {
        _ = try await loadModel(model)
        try await warmupIfNeeded()
    }

    func makeSession(
        model: LocalASRModelDefinition,
        bias: LocalASRBiasPayload?,
        locale: Locale
    ) async throws -> MacMLXStreamingSession {
        let qwen = try await loadModel(model)
        var config = StreamingConfig(
            decodeIntervalSeconds: 0.5,
            boundaryDecodeIntervalSeconds: 0.2,
            boundaryBoostSeconds: 1.0,
            encoderWindowOverlapSeconds: 1.0,
            maxCachedWindows: 8,
            delayPreset: .realtime,
            language: MacQwen3LanguageHint.from(locale: locale),
            context: bias?.promptBias,
            temperature: 0,
            maxTokensPerPass: 512,
            minAgreementPasses: 2,
            boundaryMinAgreementPasses: 2,
            maxDecodeWindows: 1,
            finalizeCompletedWindows: true
        )
        return MacMLXStreamingSession(model: qwen, config: config)
    }

    func transcribeBatch(
        samples: [Float],
        model: LocalASRModelDefinition,
        locale: Locale,
        bias: LocalASRBiasPayload?
    ) async throws -> String {
        let qwen = try await loadModel(model)
        let audio = MLXArray(samples.map { Float32($0) })
        let language = MacQwen3LanguageHint.from(locale: locale)
        let context = bias?.promptBias ?? ""
        let output = qwen.generate(
            audio: audio,
            context: context,
            language: language
        )
        let cleaned = MacHallucinationFilter.strip(output.text)
        guard !cleaned.isEmpty else { throw MacLocalASRError.emptyTranscript }
        return cleaned
    }

    // MARK: - Private

    private func loadModel(_ definition: LocalASRModelDefinition) async throws -> Qwen3ASRModel {
        if cachedModelId == definition.id, let cachedModel {
            return cachedModel
        }
        guard let root = LocalASRModelInstallState.modelRootURL(definition) else {
            throw MacLocalASRError.qwen3ModelMissing
        }
        let model = try await Qwen3ASRModel.fromModelDirectory(root)
        cachedModelId = definition.id
        cachedModel = model
        didWarmup = false
        return model
    }

    private func warmupIfNeeded() async throws {
        guard !didWarmup else { return }
        guard let model = cachedModel else { return }
        didWarmup = true
        // One second of silence — primes Metal kernels before the first user take.
        let silence = MLXArray([Float](repeating: 0, count: 16_000).map { Float32($0) })
        _ = model.generate(audio: silence, language: MacQwen3LanguageHint.from(locale: Locale(identifier: "zh-CN")))
    }
}
