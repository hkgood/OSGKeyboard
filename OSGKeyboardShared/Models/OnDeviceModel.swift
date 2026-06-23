// OnDeviceModel.swift
// OSGKeyboard · Shared
//
// Identity of an on-device model the host app downloads and the
// keyboard extension observes via App Group flags (the extension
// cannot read the main app's Caches directory).

import Foundation

public enum OnDeviceModel: String, CaseIterable, Identifiable, Sendable {
    case qwen3ASR

    public var id: String { rawValue }

    /// CoreML inference bundle (`aufklarer/Qwen3-ASR-CoreML`), derived from
    /// official `Qwen/Qwen3-ASR-0.6B`.
    public var repoId: String {
        switch self {
        case .qwen3ASR: return "aufklarer/Qwen3-ASR-CoreML"
        }
    }

    /// Tokenizer files (vocab / merges) pulled from the upstream Qwen repo.
    public var tokenizerRepoId: String {
        switch self {
        case .qwen3ASR: return "Qwen/Qwen3-ASR-0.6B"
        }
    }

    public var displayName: String {
        switch self {
        case .qwen3ASR: return "Qwen3-ASR 0.6B (CoreML)"
        }
    }

    public var approximateSizeMB: Int {
        switch self {
        case .qwen3ASR: return 1_600
        }
    }

    public var compactSizeLabel: String {
        "\(approximateSizeMB)M"
    }

    /// Settings list title: model name plus compact size.
    public var listTitle: String {
        "\(displayName) · \(compactSizeLabel)"
    }

    public var repoAndSizeLabel: String {
        "\(repoId) · \(approximateSizeMB) MB"
    }
}
