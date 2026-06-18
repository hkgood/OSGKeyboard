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
    /// after this call). iOS 17 uses `AVAudioApplication.recordPermission`;
    /// older systems fall back to `AVAudioSession.recordPermission`.
    public func requestMicPermission() async -> Bool {
        if #available(iOS 17.0, *) {
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
        } else {
            let session = AVAudioSession.sharedInstance()
            switch session.recordPermission {
            case .granted: return true
            case .denied:  return false
            case .undetermined:
                if !didRequestMicOnce {
                    didRequestMicOnce = true
                    return await withCheckedContinuation { cont in
                        session.requestRecordPermission { cont.resume(returning: $0) }
                    }
                }
                return false
            @unknown default: return false
            }
        }
    }

    /// Request Speech Recognition permission. Returns true if granted
    /// (already or after this call). For iOS 18 SFSpeechRecognizer this
    /// is required before recognition can begin; for iOS 26 SpeechAnalyzer
    /// the framework prompts on first use, so this call is a no-op there.
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