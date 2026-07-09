// LocalASRCapabilities.swift
// OSGKeyboard · Shared
//
// Declares what each on-device ASR backend can accept for vocabulary bias.
// Callers must consult capabilities before building a `LocalASRBiasPayload`.

import Foundation

/// How a backend accepts vocabulary hints (honest matrix — not every model
/// supports hard hotwords).
public enum LocalASRHotwordMode: String, Sendable, Codable, Equatable {
    case none
    case promptOnly
    case perRequest
    case recognizerScoped
    case cloudVocabulary
}

/// Cost of refreshing hotwords on a backend (e.g. Sherpa Qwen3 reloads recognizer).
public enum LocalASRHotwordReloadCost: String, Sendable, Codable, Equatable {
    case none
    case recognizerReload
    case modelReload
}

public struct LocalASRCapabilities: Sendable, Equatable {
    public let hotwordMode: LocalASRHotwordMode
    public let maxHotwordCount: Int
    public let maxPromptCharacters: Int
    public let supportsStreaming: Bool
    public let hotwordReloadCost: LocalASRHotwordReloadCost

    public init(
        hotwordMode: LocalASRHotwordMode,
        maxHotwordCount: Int,
        maxPromptCharacters: Int,
        supportsStreaming: Bool,
        hotwordReloadCost: LocalASRHotwordReloadCost
    ) {
        self.hotwordMode = hotwordMode
        self.maxHotwordCount = maxHotwordCount
        self.maxPromptCharacters = maxPromptCharacters
        self.supportsStreaming = supportsStreaming
        self.hotwordReloadCost = hotwordReloadCost
    }

    /// Qwen3 MLX via mlx-swift-asr — `context` soft prompt on `transcribe`.
    public static let qwen3MLX = LocalASRCapabilities(
        hotwordMode: .promptOnly,
        maxHotwordCount: 0,
        maxPromptCharacters: 800,
        supportsStreaming: false,
        hotwordReloadCost: .none
    )

    /// Apple Speech on macOS — no project-controlled hotword API today.
    public static let appleSpeech = LocalASRCapabilities(
        hotwordMode: .none,
        maxHotwordCount: 0,
        maxPromptCharacters: 0,
        supportsStreaming: false,
        hotwordReloadCost: .none
    )

    /// Sherpa Qwen3 — hard hotwords via `--qwen3-asr-hotwords`.
    public static let sherpaQwen3 = LocalASRCapabilities(
        hotwordMode: .recognizerScoped,
        maxHotwordCount: 100,
        maxPromptCharacters: 0,
        supportsStreaming: false,
        hotwordReloadCost: .recognizerReload
    )

    /// Sherpa SenseVoice — fast Chinese baseline without hotwords.
    public static let sherpaSenseVoice = LocalASRCapabilities(
        hotwordMode: .none,
        maxHotwordCount: 0,
        maxPromptCharacters: 0,
        supportsStreaming: false,
        hotwordReloadCost: .none
    )

    /// FunASR Paraformer (Sherpa offline) — no project hotword API.
    public static let sherpaParaformer = LocalASRCapabilities(
        hotwordMode: .none,
        maxHotwordCount: 0,
        maxPromptCharacters: 0,
        supportsStreaming: false,
        hotwordReloadCost: .none
    )
}
