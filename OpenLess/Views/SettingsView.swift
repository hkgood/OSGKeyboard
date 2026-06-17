// SettingsView.swift
// OSGKeyboard · Main App
//
// Reachable from HomeView. Reuses the same Onboarding cards.

import SwiftUI
import OSGKeyboardShared

struct SettingsView: View {
    @ObservedObject var config = ProviderConfig.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 14) {
                        ProviderPickerSection(config: config)
                        APISettingsCard(config: config)
                            .padding(.horizontal, 16)

                        Button {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            Label("Open iOS Keyboard Settings", systemImage: "keyboard")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
                                .foregroundStyle(Theme.textPrimary)
                        }
                        .padding(.horizontal, 16)
                    }
                    .padding(.vertical, 18)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Theme.accent)
                }
            }
            .preferredColorScheme(.dark)
        }
    }
}
