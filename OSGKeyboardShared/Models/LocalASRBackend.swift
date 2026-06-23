// LocalASRBackend.swift
// OSGKeyboard · Shared
//
// Identifies which on-device speech recognition engine to use when the
// user picks the "local" engine (no cloud LLM polish). The shared
// factory `ASRServiceFactory` dispatches on this enum; the settings UI
// renders it as a picker.
//
// Why an enum in `Shared` rather than living next to the concrete
// `ASRService` implementations: the value must be serialisable into
// the App Group store (so the keyboard extension can observe the
// selection), exposed via `ProviderConfig` (UI binding) and consumed
// by every layer that asks for an ASR backend.

import Foundation

public enum LocalASRBackend: String, CaseIterable, Identifiable, Sendable, Codable {
    /// iOS 26 `SpeechAnalyzer` + `DictationTranscriber`. Always
    /// on-device, no asset download, ships with iOS. Default for every
    /// fresh install — anything else is opt-in.
    case speechAnalyzer

    /// Qwen3-ASR-0.6B via CoreML (Neural Engine + CPU). Stronger on Chinese
    /// dialects and noisy audio than `SpeechAnalyzer`, works in Flow while
    /// the host app is backgrounded, but requires a ~1.6 GB download on first
    /// use and iOS 18+.
    case qwen3ASR

    public var id: String { rawValue }

    /// Localisation key for the human label in the settings picker.
    public var labelKey: String {
        switch self {
        case .speechAnalyzer: return "asr.backend.speechAnalyzer.label"
        case .qwen3ASR:        return "asr.backend.qwen3.label"
        }
    }

    /// Localisation key for the one-line subtitle shown under the label.
    public var blurbKey: String {
        switch self {
        case .speechAnalyzer: return "asr.backend.speechAnalyzer.blurb"
        case .qwen3ASR:        return "asr.backend.qwen3.blurb"
        }
    }

    /// Whether this backend needs the user to download a model file
    /// before it can run. Used to gate the "Downloading Qwen3-ASR" UI
    /// in a follow-up; for now we just expose the flag.
    public var requiresModelDownload: Bool {
        switch self {
        case .speechAnalyzer: return false
        case .qwen3ASR:        return true
        }
    }
}
