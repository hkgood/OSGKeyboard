// FlowCaptureVoiceProcessing.swift
// OSGKeyboard · Host Support
//
// Capture-side speech front-end for local ASR: Apple Voice Processing
// (noise suppression / AGC / AEC) plus near-talk built-in mic preference.
// `.measurement` delivers near-raw PCM and is a poor fit for competing
// talkers in the same room; `.voiceChat` + VP is the system path that
// also unlocks Control Center Mic Modes (incl. Voice Isolation).

import AVFoundation
import Foundation
import OSGKeyboardShared

public enum FlowCaptureVoiceProcessing {

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

    /// Prefer a near-field built-in data source (front/lower + cardioid when
    /// available). No-op while Bluetooth HFP is preferred or active — keep
    /// the existing headset route.
    public static func preferNearTalkBuiltInMic(on session: AVAudioSession) {
        if session.currentRoute.inputs.first?.portType == .bluetoothHFP { return }
        if session.preferredInput?.portType == .bluetoothHFP { return }

        guard let builtIn = session.availableInputs?.first(where: {
            $0.portType == .builtInMic
        }) else { return }

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

        do {
            try session.setPreferredInput(builtIn)
        } catch {
            OSGDiag.log(
                "preferred built-in mic failed: \(error.localizedDescription)",
                category: "flow"
            )
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
}
