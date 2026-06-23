// OnDeviceModelStatus.swift
// OSGKeyboard · Shared
//
// Mirrors on-device model download state into the App Group so the
// keyboard extension can show readiness hints without reading the
// host app's Caches directory.

import Foundation

public enum OnDeviceModelStatus {

    private enum Key {
        static func downloaded(_ model: OnDeviceModel) -> String {
            "models.\(model.rawValue).downloaded"
        }
        static func progress(_ model: OnDeviceModel) -> String {
            "models.\(model.rawValue).downloadProgress"
        }
        static let modelsLoadedInMemory = "models.loadedInMemory"
    }

    // MARK: - Writes (host app)

    public static func setDownloaded(_ downloaded: Bool, for model: OnDeviceModel) {
        guard AppGroup.isAvailable else { return }
        AppGroup.defaults.set(downloaded, forKey: Key.downloaded(model))
        if downloaded {
            clearProgress(for: model)
        }
    }

    public static func setProgress(_ progress: Double?, for model: OnDeviceModel) {
        guard AppGroup.isAvailable else { return }
        if let progress {
            AppGroup.defaults.set(progress, forKey: Key.progress(model))
        } else {
            AppGroup.defaults.removeObject(forKey: Key.progress(model))
        }
    }

    public static func clearProgress(for model: OnDeviceModel) {
        guard AppGroup.isAvailable else { return }
        AppGroup.defaults.removeObject(forKey: Key.progress(model))
    }

    public static func setModelsLoadedInMemory(_ loaded: Bool) {
        guard AppGroup.isAvailable else { return }
        AppGroup.defaults.set(loaded, forKey: Key.modelsLoadedInMemory)
    }

    public static func modelsLoadedInMemory(defaults: UserDefaults? = nil) -> Bool {
        let store = defaults ?? (AppGroup.isAvailable ? AppGroup.defaults : .standard)
        return store.bool(forKey: Key.modelsLoadedInMemory)
    }

    // MARK: - Reads (keyboard + host app)

    public static func isDownloaded(_ model: OnDeviceModel, defaults: UserDefaults? = nil) -> Bool {
        let store = defaults ?? (AppGroup.isAvailable ? AppGroup.defaults : .standard)
        return store.bool(forKey: Key.downloaded(model))
    }

    public static func downloadProgress(_ model: OnDeviceModel, defaults: UserDefaults? = nil) -> Double? {
        let store = defaults ?? (AppGroup.isAvailable ? AppGroup.defaults : .standard)
        guard store.object(forKey: Key.progress(model)) != nil else { return nil }
        return store.double(forKey: Key.progress(model))
    }

    /// Whether the currently selected local-engine stack has every
    /// required on-device model downloaded.
    public static func isLocalStackReady(
        asrBackend: LocalASRBackend,
        defaults: UserDefaults? = nil
    ) -> Bool {
        if asrBackend == .qwen3ASR {
            return isDownloaded(.qwen3ASR, defaults: defaults)
        }
        return true
    }

    /// First missing model for the active local stack, if any.
    public static func firstMissingModel(
        asrBackend: LocalASRBackend,
        defaults: UserDefaults? = nil
    ) -> OnDeviceModel? {
        if asrBackend == .qwen3ASR, !isDownloaded(.qwen3ASR, defaults: defaults) {
            return .qwen3ASR
        }
        return nil
    }
}

// MARK: - On-device Qwen3 runtime

/// CoreML ASR requires iOS 18+ / macOS 15+ (MLState KV cache).
public enum OnDeviceMLRuntime {
    /// Whether Qwen3-ASR CoreML can run in this process.
    public static var supportsOnDeviceQwen3: Bool {
        if #available(iOS 18.0, *) {
            return true
        }
        return false
    }
}
