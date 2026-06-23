// LocalASRBackend.swift
// OSGKeyboard · Shared
//
// Identifies which on-device speech recognition engine to use when the
// user picks the "local" engine (no cloud LLM polish). The shared
// factory `ASRServiceFactory` dispatches on this enum; the settings UI
// renders it as a picker.
//
// As of v0.2.0 the only on-device backend is iOS 26 `SpeechAnalyzer`
// + `DictationTranscriber`. The previous Qwen3-CoreML backend has
// been removed: that path required a ~1.6 GB CoreML bundle, a local
// SPM fork that pulled in mlx-swift, and significant app-side state
// (download manager, warm-up service, model registry). We now keep the
// local engine narrow — same iOS ASR the cloud engine already uses —
// and let users opt into a cloud polish step after the transcript is
// produced if they need stronger accuracy on noisy audio or dialectal
// Chinese. See `LocalPolishConfig` for the post-ASR polish toggle.
//
// Why an enum in `Shared` rather than a `Bool`: the value must remain
// serialisable into the App Group store (so the keyboard extension can
// observe the selection) and exposed via `ProviderConfig` (UI binding).
// Keeping the type stable even with a single case avoids a migration
// the next time someone adds a non-cloud backend (e.g. whisper.cpp).

import Foundation

public enum LocalASRBackend: String, CaseIterable, Identifiable, Sendable, Codable {
    /// iOS 26 `SpeechAnalyzer` + `DictationTranscriber`. Always
    /// on-device, no asset download, ships with iOS. The only local
    /// backend in v0.2.0.
    case speechAnalyzer

    public var id: String { rawValue }

    /// Localisation key for the human label in the settings picker.
    public var labelKey: String {
        "asr.backend.speechAnalyzer.label"
    }

    /// Localisation key for the one-line subtitle shown under the label.
    public var blurbKey: String {
        "asr.backend.speechAnalyzer.blurb"
    }

    /// Whether this backend needs the user to download a model file
    /// before it can run. Always `false` for iOS-bundled speech.
    public var requiresModelDownload: Bool {
        false
    }
}