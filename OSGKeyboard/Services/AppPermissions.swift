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

    /// Undocumented Settings deep link that lands on General → Keyboard, the
    /// page where the user adds the keyboard and grants Full Access.
    ///
    /// `prefs:`-family URLs are private. App Review generally rejects them,
    /// with custom-keyboard extensions using this specific keyboard path as
    /// the long-standing exception — it is what shipping third-party keyboards
    /// rely on. Apple can break or start rejecting it at any time, so every
    /// call falls back to the public `openSettingsURLString`, and setting this
    /// to `false` removes the private scheme from the binary's behaviour
    /// entirely without touching any call site.
    static let usesPrivateKeyboardSettingsDeepLink = false

    private static let keyboardSettingsDeepLink = "App-Prefs:root=General&path=Keyboard"

    /// Opens the keyboard section of Settings when iOS honours the deep link,
    /// otherwise the app's own Settings page. `completion` reports whether any
    /// of the attempts was accepted, so the caller can fall back to written
    /// steps when none was.
    @MainActor
    static func openKeyboardSettings(completion: ((Bool) -> Void)? = nil) {
        guard usesPrivateKeyboardSettingsDeepLink,
              let deepLink = URL(string: keyboardSettingsDeepLink) else {
            openSystemSettings(completion: completion)
            return
        }
        UIApplication.shared.open(deepLink) { opened in
            guard opened else {
                openSystemSettings(completion: completion)
                return
            }
            completion?(true)
        }
    }

    /// Opens the app's own page in Settings. iOS exposes no *public* URL that
    /// reaches General → Keyboard → Keyboards, so callers must still guide the
    /// user through the remaining taps. `completion` reports whether iOS
    /// actually accepted the open so the caller can fall back to written steps.
    @MainActor
    static func openSystemSettings(completion: ((Bool) -> Void)? = nil) {
        guard let url = URL(string: UIApplication.openSettingsURLString) else {
            completion?(false)
            return
        }
        UIApplication.shared.open(url) { opened in
            completion?(opened)
        }
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
