// HomeView.swift
// OSGKeyboard · Main App
//
// Minimal home screen shown after onboarding. Two CTAs: enable keyboard
// (opens iOS settings) and edit API config (sheet).

import SwiftUI
import OSGKeyboardShared

struct HomeView: View {
    @ObservedObject var config = ProviderConfig.shared
    @State private var showSettings = false

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 22) {
                Spacer()
                Image(systemName: "mic.circle.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(Theme.accent)
                Text("OSGKeyboard is ready")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                Text(currentProviderSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Spacer()

                VStack(spacing: 12) {
                    primaryButton(
                        title: "Enable in iOS Settings",
                        systemImage: "gearshape.fill"
                    ) {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    primaryButton(
                        title: "Edit API Configuration",
                        systemImage: "key.fill",
                        secondary: true
                    ) {
                        showSettings = true
                    }
                }
                .padding(.horizontal, 24)

                Spacer().frame(height: 12)
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .preferredColorScheme(.dark)
    }

    private var currentProviderSubtitle: String {
        let name = LLMProvider.provider(id: config.providerId).name
        return "Using \(name) • Model: \(config.model.isEmpty ? "—" : config.model)"
    }

    private func primaryButton(
        title: String,
        systemImage: String,
        secondary: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: systemImage)
                Text(title).font(.subheadline.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                secondary ? Theme.card : Theme.accent,
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .foregroundStyle(secondary ? Theme.textPrimary : .black)
        }
    }
}
