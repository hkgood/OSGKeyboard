// PermissionPrimer.swift
// OSGKeyboard · Main App
//
// Legacy entry point — permission prompts now run inside Onboarding.
// Kept as a no-op so older call sites compile without re-firing TCC
// dialogs on every launch.

import Foundation

@MainActor
enum PermissionPrimer {
    static func primeIfNeeded() async {
        // Permissions are requested step-by-step in OnboardingView.
    }
}
