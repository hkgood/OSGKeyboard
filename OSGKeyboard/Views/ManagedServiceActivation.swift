// ManagedServiceActivation.swift
// OSGKeyboard · Main App
//
// Switching to OSG credits always passes the cloud-sharing consent before the
// managed gateway is prepared. Settings and Home share this path so neither
// can enable credits without the disclosure.

import OSGKeyboardShared
import SwiftUI

@MainActor
enum ManagedServiceActivation {
    /// Prepares the managed gateway, then routes recognition and polish
    /// through OSG credits. Returns false when the gateway is unavailable.
    @discardableResult
    static func activate(
        config: ProviderConfig,
        accountSession: AccountSessionCoordinator
    ) async -> Bool {
        guard await accountSession.prepareManagedGateway() else { return false }
        withAnimation(Motion.quick) {
            config.engineMode = "cloud"
            config.modeId = "polish"
            config.credentialSource = .managed
        }
        return true
    }
}

extension View {
    /// Consent alert shown before the first switch to OSG credits.
    func managedCloudConsentAlert(
        isPresented: Binding<Bool>,
        config: ProviderConfig,
        onAccept: @escaping () -> Void
    ) -> some View {
        alert(
            AppL10n.string("settings.aiService.credits.consent.title"),
            isPresented: isPresented
        ) {
            Button(AppL10n.string("common.cancel"), role: .cancel) {}
            Button(AppL10n.string("settings.aiService.credits.consent.accept")) {
                config.hasAcknowledgedCloudSharing = true
                onAccept()
            }
            .accessibilityIdentifier("settings.aiService.credits.consent.accept")
        } message: {
            Text(AppL10n.string("settings.aiService.credits.consent.message"))
        }
    }
}
