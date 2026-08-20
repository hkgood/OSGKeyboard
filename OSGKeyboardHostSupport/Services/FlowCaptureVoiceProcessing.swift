// FlowCaptureVoiceProcessing.swift
// OSGKeyboard · Host Support
//
// Capture-side speech front-end for local ASR: Apple Voice Processing
// (noise suppression / AGC / AEC) plus user-configured microphone routing.
// `.measurement` delivers near-raw PCM and is a poor fit for competing
// talkers in the same room; `.voiceChat` + VP is the system path that
// also unlocks Control Center Mic Modes (incl. Voice Isolation).

import AVFoundation
import Foundation
#if canImport(OSGKeyboardShared)
import OSGKeyboardShared
#endif

public enum FlowCaptureVoiceProcessing {

    public enum PreferredMicrophoneError: Error, LocalizedError {
        case noAvailableMicrophone
        case routeDidNotActivate

        public var errorDescription: String? {
            switch self {
            case .noAvailableMicrophone:
                return SharedL10n.string("microphonePriority.error.noneAvailable")
            case .routeDidNotActivate:
                return SharedL10n.string("microphonePriority.error.routeDidNotActivate")
            }
        }
    }

    /// Speech-oriented session mode. Prefer over `.measurement` for ASR.
    public static let captureMode: AVAudioSession.Mode = .voiceChat

    public static let captureOptions: AVAudioSession.CategoryOptions = [
        .defaultToSpeaker, .allowBluetoothHFP, .mixWithOthers
    ]

    /// Enable Apple Voice Processing on a stopped engine. Format may change
    /// afterward — callers must re-read `inputNode` formats before `installTap`.
    @discardableResult
    public static func enableVoiceProcessing(on engine: AVAudioEngine) -> Bool {
        let input = engine.inputNode
        if input.isVoiceProcessingEnabled { return true }
        do {
            try input.setVoiceProcessingEnabled(true)
            OSGDiag.log("voiceProcessing enabled", category: "flow")
            logActiveMicrophoneMode()
            return true
        } catch {
            OSGDiag.log(
                "voiceProcessing enable failed: \(error.localizedDescription)",
                category: "flow"
            )
            return false
        }
    }

    /// Returns every input iOS currently exposes. The first-time order keeps
    /// the app's historical routing (Bluetooth HFP, built-in, then external),
    /// while a saved user order is preserved by `MicrophonePriorityStore`.
    public static func availableMicrophones(
        on session: AVAudioSession
    ) -> [MicrophonePriorityDevice] {
        (session.availableInputs ?? [])
            .map { input in
                MicrophonePriorityDevice(
                    id: input.uid,
                    name: input.portName,
                    kind: microphoneKind(for: input.portType)
                )
            }
            .sorted { lhs, rhs in
                let leftRank = defaultRank(for: lhs.kind)
                let rightRank = defaultRank(for: rhs.kind)
                if leftRank != rightRank { return leftRank < rightRank }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }

    /// Applies the first connected device in the device-local priority list.
    /// A deliberately excluded device is never used as an implicit fallback.
    @discardableResult
    public static func selectPreferredInput(
        on session: AVAudioSession,
        store: MicrophonePriorityStore = MicrophonePriorityStore()
    ) throws -> String {
        let available = availableMicrophones(on: session)
        let configuration = store.mergeAndSave(available: available)
        guard
            let selected = configuration.preferredDevice(available: available),
            let input = session.availableInputs?.first(where: { $0.uid == selected.id })
        else {
            throw PreferredMicrophoneError.noAvailableMicrophone
        }

        if input.portType == .builtInMic {
            configureNearTalkDataSource(for: input)
        }
        try session.setPreferredInput(input)
        OSGDiag.log(
            "preferred microphone name=\(input.portName) uid=\(input.uid)",
            category: "flow"
        )
        return input.uid
    }

    /// Explicit built-in preference retained for callers that need that exact
    /// route rather than the user-configured priority resolver.
    public static func preferNearTalkBuiltInMic(on session: AVAudioSession) {
        guard let builtIn = session.availableInputs?.first(where: {
            $0.portType == .builtInMic
        }) else { return }

        configureNearTalkDataSource(for: builtIn)

        do {
            try session.setPreferredInput(builtIn)
        } catch {
            OSGDiag.log(
                "preferred built-in mic failed: \(error.localizedDescription)",
                category: "flow"
            )
        }
    }

    private static func configureNearTalkDataSource(
        for builtIn: AVAudioSessionPortDescription
    ) {
        let sources = builtIn.dataSources ?? []
        let preferred =
            sources.first(where: { $0.orientation == .front })
            ?? sources.first(where: { $0.location == .lower })
            ?? sources.first

        if let preferred {
            if preferred.supportedPolarPatterns?.contains(.cardioid) == true {
                do {
                    try preferred.setPreferredPolarPattern(.cardioid)
                } catch {
                    OSGDiag.log(
                        "cardioid polar pattern failed: \(error.localizedDescription)",
                        category: "flow"
                    )
                }
            }
            do {
                try builtIn.setPreferredDataSource(preferred)
            } catch {
                OSGDiag.log(
                    "preferred data source failed: \(error.localizedDescription)",
                    category: "flow"
                )
            }
        }
    }

    public static func logActiveMicrophoneMode() {
        let preferred = micModeLabel(AVCaptureDevice.preferredMicrophoneMode)
        let active = micModeLabel(AVCaptureDevice.activeMicrophoneMode)
        OSGDiag.log(
            "micMode preferred=\(preferred) active=\(active)",
            category: "flow"
        )
    }

    private static func micModeLabel(_ mode: AVCaptureDevice.MicrophoneMode) -> String {
        switch mode {
        case .standard: return "standard"
        case .wideSpectrum: return "wideSpectrum"
        case .voiceIsolation: return "voiceIsolation"
        @unknown default: return "unknown(\(mode.rawValue))"
        }
    }

    private static func microphoneKind(
        for portType: AVAudioSession.Port
    ) -> MicrophoneDeviceKind {
        switch portType {
        case .builtInMic:
            return .builtIn
        case .bluetoothHFP, .bluetoothLE, .bluetoothA2DP:
            return .bluetooth
        case .usbAudio:
            return .usb
        case .headsetMic, .lineIn:
            return .wired
        default:
            return .other
        }
    }

    private static func defaultRank(for kind: MicrophoneDeviceKind) -> Int {
        switch kind {
        case .bluetooth: return 0
        case .builtIn: return 1
        case .usb: return 2
        case .wired: return 3
        case .virtual: return 4
        case .other: return 5
        }
    }
}
