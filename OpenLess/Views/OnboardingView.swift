// OnboardingView.swift
// OSGKeyboard · Main App
//
// Three-page horizontal onboarding:
//  1) Welcome
//  2) Enable keyboard + Allow Full Access
//  3) Pick provider + enter API key

import SwiftUI
import OSGKeyboardShared

struct OnboardingView: View {
    @ObservedObject var config = ProviderConfig.shared
    @State private var page: Int = 0

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                TabView(selection: $page) {
                    WelcomePage().tag(0)
                    EnableKeyboardPage().tag(1)
                    APISetupPage(config: config) {
                        // completion — root switches to HomeView
                    }
                    .tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                pageDots
                    .padding(.bottom, 12)

                bottomBar
            }
        }
        .preferredColorScheme(.dark)
    }

    private var pageDots: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(i == page ? Theme.accent : Color.white.opacity(0.2))
                    .frame(width: 6, height: 6)
            }
        }
    }

    private var bottomBar: some View {
        HStack {
            if page > 0 {
                Button("Back") { withAnimation { page -= 1 } }
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            if page < 2 {
                Button {
                    withAnimation { page += 1 }
                } label: {
                    Text("Next")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 20).padding(.vertical, 10)
                        .background(Theme.accent, in: Capsule())
                        .foregroundStyle(.black)
                }
            } else {
                Button {
                    // finalise — ProviderConfig is already bound to App Group
                } label: {
                    Text("Done")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 24).padding(.vertical, 10)
                        .background(config.isConfigured ? Theme.accent : Color.gray.opacity(0.4),
                                    in: Capsule())
                        .foregroundStyle(.black)
                }
                .disabled(!config.isConfigured)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 18)
    }
}

private struct WelcomePage: View {
    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "mic.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(Theme.accent)
            Text("OSGKeyboard")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
            Text("Hold the mic key, speak, and let AI polish your words into clean text — in every app.")
                .multilineTextAlignment(.center)
                .font(.system(size: 15))
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 28)
            Spacer()
        }
    }
}

private struct EnableKeyboardPage: View {
    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "keyboard.fill")
                .font(.system(size: 64))
                .foregroundStyle(Theme.accent)
            Text("Enable OSGKeyboard")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)

            VStack(alignment: .leading, spacing: 10) {
                step(num: 1, text: "Open Settings → General → Keyboard → Keyboards")
                step(num: 2, text: "Tap “Add New Keyboard…” and choose OSGKeyboard")
                step(num: 3, text: "Tap OSGKeyboard and enable “Allow Full Access” (needed for mic + LLM)")
            }
            .padding(.horizontal, 22)

            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Label("Open iOS Settings", systemImage: "arrow.up.right.square")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 18).padding(.vertical, 10)
                    .background(Theme.accent, in: Capsule())
                    .foregroundStyle(.black)
            }
            .padding(.top, 6)
            Spacer()
        }
    }

    private func step(num: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(num)")
                .font(.system(size: 11, weight: .bold))
                .frame(width: 20, height: 20)
                .background(Theme.accent, in: Circle())
                .foregroundStyle(.black)
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(Theme.textPrimary)
        }
    }
}

private struct APISetupPage: View {
    @ObservedObject var config: ProviderConfig
    let onDone: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Text("Configure your AI provider")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.top, 18)
                Text("OSGKeyboard only calls the AI to polish your text. No audio leaves your device.")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 24)

                ProviderPickerSection(config: config)
                APISettingsCard(config: config)
                    .padding(.horizontal, 16)
            }
            .padding(.bottom, 40)
        }
    }
}
