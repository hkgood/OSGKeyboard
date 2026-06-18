// PermissionManager.swift
// OSGKeyboard · Keyboard Extension
//
// Extracted from KeyboardViewController so the view controller doesn't
// need to know about AVAudioApplication vs AVAudioSession branching
// or SFSpeechRecognizer.requestAuthorization callback bridging.
//
// Contract:
//   • `requestMicPermission()` returns true if the user has authorised
//     or *just* authorised; false otherwise. Idempotent within a
//     process — the second call will not prompt again if the user has
//     already answered.
//   • `requestSpeechPermission()` mirrors the same shape but for
//     SFSpeechRecognizer.

import Foundation
import AVFoundation
import Speech

@MainActor
public final class PermissionManager: @unchecked Sendable {

    public init() {}

    private var didRequestMicOnce: Bool = false

    /// Request microphone access. Returns true if granted (already or
    /// after this call). Uses the iOS 17+ `AVAudioApplication` API.
    public func requestMicPermission() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: return true
        case .denied:  return false
        case .undetermined:
            if !didRequestMicOnce {
                didRequestMicOnce = true
                return await AVAudioApplication.requestRecordPermission()
            }
            return false
        @unknown default: return false
        }
    }

    /// Request Speech Recognition permission. Returns true if granted
    /// (already or after this call). The `SFSpeechRecognizer` plist
    /// key + this call are still required even on iOS 26 — the
    /// `SpeechAnalyzer` API does not expose an explicit request
    /// method of its own and the framework checks the same TCC
    /// entry on first use.
    public func requestSpeechPermission() async -> Bool {
        await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { status in
                switch status {
                case .authorized: cont.resume(returning: true)
                case .denied, .restricted, .notDetermined:
                    cont.resume(returning: false)
                @unknown default:
                    cont.resume(returning: false)
                }
            }
        }
    }
}