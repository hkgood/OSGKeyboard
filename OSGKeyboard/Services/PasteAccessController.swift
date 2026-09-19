// PasteAccessController.swift
// OSGKeyboard · Main App
//
// Shared paste-access verification state for the settings and skills screens.
// Both surfaces need the same tri-state result of `requestPasteAccess()`
// (verified / needs recovery / no text to sample), so the decision lives here
// once instead of being re-implemented per view.

import OSGKeyboardShared
import SwiftUI

@MainActor
final class PasteAccessController: ObservableObject {
    /// iOS has granted paste access and the last read succeeded.
    @Published private(set) var isVerified: Bool
    /// A read was attempted but denied — the caller should offer a Settings
    /// recovery path.
    @Published private(set) var needsRecovery = false
    /// Drives a "nothing on the clipboard to test with" alert.
    @Published var showNoTextAlert = false
    /// A brief post-verification confirmation flash (used by the guide card).
    @Published private(set) var showSuccess = false

    init() {
        isVerified = AppPermissions.hasVerifiedPasteAccess
    }

    /// Re-reads the persisted verification flag, e.g. on appear or foreground.
    func refresh(clearRecovery: Bool = false) {
        isVerified = AppPermissions.hasVerifiedPasteAccess
        if clearRecovery {
            needsRecovery = false
        }
    }

    /// Performs the explicit paste read and updates state. `flashSuccess` shows
    /// a short confirmation that auto-dismisses.
    func verify(flashSuccess: Bool = false, animation: Animation = Motion.soft) {
        switch AppPermissions.requestPasteAccess() {
        case .verified:
            withAnimation(animation) {
                isVerified = true
                needsRecovery = false
                if flashSuccess {
                    showSuccess = true
                }
            }
            guard flashSuccess else { return }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(700))
                withAnimation(animation) {
                    showSuccess = false
                }
            }
        case .noTextAvailable:
            showNoTextAlert = true
        case .unavailable:
            withAnimation(animation) {
                isVerified = false
                needsRecovery = true
            }
        }
    }
}
