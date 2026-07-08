// MacLocalASRService.swift
// OSGKeyboard · Mac
//
// On-device ASR for macOS. Primary: Qwen3-ASR-1.7B (MLX via mlx-swift-asr).
// Falls back to Apple Speech when Qwen3 weights are absent or backend is Apple Speech.

import Foundation

enum MacLocalASRBackend: String, Sendable, CaseIterable {
    case qwen3MLX
    case appleSpeech
}

enum MacLocalASRError: Error, LocalizedError {
    case qwen3ModelMissing
    case qwen3LoadFailed(String)
    case qwen3InferenceFailed(String)
    case speechDenied
    case speechFailed(String)
    case emptyTranscript

    var errorDescription: String? {
        switch self {
        case .qwen3ModelMissing:
            return MacL10n.string("mac.error.qwen3ModelMissing")
        case .qwen3LoadFailed(let detail):
            return MacL10n.format("mac.error.qwen3LoadFailed", detail)
        case .qwen3InferenceFailed(let detail):
            return MacL10n.format("mac.error.qwen3InferenceFailed", detail)
        case .speechDenied:
            return "Speech recognition permission denied"
        case .speechFailed(let detail):
            return detail
        case .emptyTranscript:
            return MacL10n.string("mac.error.emptyTranscript")
        }
    }
}

enum MacLocalASRPreferences {
    static let backendKey = "mac.localASR.backend"
    static let qwen3ModelPathKey = "mac.localASR.qwen3ModelPath"

    static var backend: MacLocalASRBackend {
        get {
            guard let raw = UserDefaults.standard.string(forKey: backendKey),
                  let value = MacLocalASRBackend(rawValue: raw) else {
                return .qwen3MLX
            }
            return value
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: backendKey) }
    }

    static var qwen3ModelPath: String {
        get { UserDefaults.standard.string(forKey: qwen3ModelPathKey) ?? defaultQwen3ModelPath }
        set { UserDefaults.standard.set(newValue, forKey: qwen3ModelPathKey) }
    }

    /// Default install location for MLX-converted Qwen3-ASR weights.
    static var defaultQwen3ModelPath: String {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("OSGKeyboard/models/qwen3-asr-1.7b-mlx", isDirectory: true).path
    }

    static func qwen3ModelIsInstalled(at path: String = qwen3ModelPath) -> Bool {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else {
            return false
        }
        let fm = FileManager.default
        let config = (path as NSString).appendingPathComponent("config.json")
        let weights = (path as NSString).appendingPathComponent("model.safetensors")
        guard fm.fileExists(atPath: config), fm.fileExists(atPath: weights) else {
            return false
        }
        let names = (try? fm.contentsOfDirectory(atPath: path)) ?? []
        return names.contains("vocab.json") && names.contains("merges.txt")
    }
}

enum MacLocalASRService {
    /// Transcribe using the user's preferred local backend with automatic
    /// fallback to Apple Speech when Qwen3 weights are not present.
    static func transcribe(samples: [Float], locale: Locale) async throws -> String {
        let preferQwen3 = MacLocalASRPreferences.backend == .qwen3MLX
        if preferQwen3, MacLocalASRPreferences.qwen3ModelIsInstalled() {
            do {
                return try await MacQwen3LocalASR.transcribe(
                    samples: samples,
                    sampleRate: 16_000,
                    locale: locale,
                    modelPath: MacLocalASRPreferences.qwen3ModelPath
                )
            } catch MacLocalASRError.qwen3ModelMissing {
                // Fall through to Apple Speech when weights are absent.
            } catch {
                throw error
            }
        }
        return try await MacSpeechLocalASR.transcribe(samples: samples, locale: locale)
    }
}
