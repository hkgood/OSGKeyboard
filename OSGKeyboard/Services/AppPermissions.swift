// AppPermissions.swift
// OSGKeyboard · Main App
//
// Central permission status for onboarding and Flow session startup.

import AVFoundation
import Speech
import UIKit

enum AppPermissions {

    enum MicStatus: Equatable {
        case undetermined
        case granted
        case denied
    }

    enum SpeechStatus: Equatable {
        case undetermined
        case granted
        case denied
        case restricted
    }

    static var micStatus: MicStatus {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: return .granted
        case .denied: return .denied
        case .undetermined: return .undetermined
        @unknown default: return .denied
        }
    }

    static var speechStatus: SpeechStatus {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: return .granted
        case .denied: return .denied
        case .restricted: return .restricted
        case .notDetermined: return .undetermined
        @unknown default: return .denied
        }
    }

    /// Both permissions required for Flow voice sessions.
    static var flowRequirementsMet: Bool {
        micStatus == .granted && speechStatus == .granted
    }

    /// Show guided permission pages when any Flow permission is not granted.
    static var needsPermissionGuidance: Bool {
        micStatus != .granted || speechStatus != .granted
    }

    static func requestMicrophone() async -> Bool {
        switch micStatus {
        case .granted: return true
        case .denied: return false
        case .undetermined: return await AVAudioApplication.requestRecordPermission()
        }
    }

    static func requestSpeechRecognition() async -> Bool {
        switch speechStatus {
        case .granted: return true
        case .denied, .restricted: return false
        case .undetermined:
            return await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
                SFSpeechRecognizer.requestAuthorization { status in
                    cont.resume(returning: status == .authorized)
                }
            }
        }
    }

    static func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
