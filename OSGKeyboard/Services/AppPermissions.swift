// AppPermissions.swift
// OSGKeyboard · Main App
//
// Central permission handling for onboarding, Flow, and clipboard access.

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

    enum PasteAccessResult: Equatable {
        case verified
        case noTextAvailable
        case unavailable
    }

    private static let pasteAccessVerifiedKey = "clipboard.pasteAccessVerified.v1"

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

    /// iOS does not expose the current "Paste from Other Apps" setting.
    /// This records the last explicit, successful user-initiated read instead.
    static var hasVerifiedPasteAccess: Bool {
        UserDefaults.standard.bool(forKey: pasteAccessVerifiedKey)
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

    @MainActor
    static func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    /// Performs an explicit direct read so iOS can present paste authorization
    /// and create the app's "Paste from Other Apps" settings entry.
    @MainActor
    @discardableResult
    static func requestPasteAccess() -> PasteAccessResult {
        let pasteboard = UIPasteboard.general
        guard pasteboard.hasStrings else { return .noTextAvailable }
        guard pasteboard.string != nil else {
            UserDefaults.standard.set(false, forKey: pasteAccessVerifiedKey)
            return .unavailable
        }
        UserDefaults.standard.set(true, forKey: pasteAccessVerifiedKey)
        return .verified
    }

    /// Home-screen guidance when Flow permissions are missing after onboarding.
    static var homePermissionGuidanceMessage: String {
        let micMissing = micStatus != .granted
        let speechMissing = speechStatus != .granted
        if micMissing && speechMissing {
            return AppL10n.string("home.setup.permission.both")
        }
        if micMissing {
            return AppL10n.string("home.setup.permission.mic")
        }
        return AppL10n.string("home.setup.permission.speech")
    }

    /// True when at least one permission can still be requested in-app.
    static var canRequestPermissionsInApp: Bool {
        micStatus == .undetermined || speechStatus == .undetermined
    }

    /// Requests any still-undetermined Flow permissions in order.
    static func requestFlowPermissionsIfNeeded() async {
        if micStatus == .undetermined {
            _ = await requestMicrophone()
        }
        if speechStatus == .undetermined {
            _ = await requestSpeechRecognition()
        }
    }
}
