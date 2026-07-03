// KeyboardOnboardingOverlay.swift
// OSGKeyboard · Keyboard Extension
//
// v0.3.0 in-keyboard onboarding. Replaces the previous "jump out to
// the host app" flow with a five-step overlay that lives on top of
// the normal keyboard UI.
//
// Why in-keyboard instead of jumping to the host app?
//
//   - iOS keyboard extensions **cannot programmatically switch back
//     to the previous app** after a host-app jump. The user has to
//     re-find their app, re-tap a text field, and re-select OSGKeyboard
//     from the globe menu. That's a 5+ tap friction.
//
//   - Steps 1, 2, 4 (welcome, mic permission, speech permission,
//     API key) need nothing the host app owns. They can all live in
//     the keyboard.
//
//   - The only step that *must* leave the keyboard is step 3
//     ("Enable Keyboard") — iOS requires the user to flip a toggle
//     in `Settings.app`, which is reachable from the extension via
//     `UIApplication.openSettingsURLString`. After the user comes
//     back, `viewWillAppear` reads `KeyboardSetupBridge.isReadyForOnboardingSkip`
//     and the overlay auto-advances past step 3.
//
// The overlay mounts only when `state.hasCompletedOnboarding == false`.
// All inputs route through `KeyboardState` action hooks, so the
// controller can mirror them into the App Group without the view
// having to know about persistence.

import SwiftUI
import OSGKeyboardShared

struct KeyboardOnboardingOverlay: View {
    @Environment(\.themePalette) private var palette: ThemePalette

    @ObservedObject var state: KeyboardViewController.State

    var body: some View {
        ZStack {
            // Dim the underlying keyboard so the overlay reads as a
            // distinct surface. We can't completely hide it without
            // losing keyboard-system visibility, so a 60% black wash
            // is the sweet spot between focus and consistency.
            palette.background.opacity(0.96).ignoresSafeArea()

            VStack(spacing: 0) {
                header

                Spacer(minLength: Spacing.sm)

                Group {
                    switch currentStep {
                    case .welcome:    welcomeStep
                    case .microphone: microphoneStep
                    case .speech:     speechStep
                    case .keyboard:   keyboardStep
                    case .api:        apiStep
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .trailing)))
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Spacer(minLength: Spacing.sm)

                footer
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.md)
        }
    }

    // MARK: - Steps

    private enum Step: Int, CaseIterable {
        case welcome = 0, microphone, speech, keyboard, api

        static let count = 5
    }

    private var currentStep: Step {
        Step(rawValue: state.onboardingPage) ?? .welcome
    }

    private var header: some View {
        VStack(spacing: Spacing.xs) {
            HStack(spacing: 6) {
                ForEach(0..<Step.count, id: \.self) { idx in
                    Capsule()
                        .fill(idx <= currentStep.rawValue
                              ? palette.accent
                              : palette.divider)
                        .frame(height: 4)
                }
            }
            .padding(.horizontal, Spacing.xs)

            Text(ExtL10n.string("keyboard.onboarding.title"))
                .font(TypeStyle.caption2)
                .foregroundStyle(palette.textSecondary)
        }
    }

    // MARK: - Step content

    private var welcomeStep: some View {
        stepBody(
            iconSystemName: "waveform.badge.mic",
            title: "keyboard.onboarding.welcome.title",
            body: "keyboard.onboarding.welcome.body"
        )
    }

    private var microphoneStep: some View {
        stepBody(
            iconSystemName: "mic.fill",
            title: "keyboard.onboarding.mic.title",
            body: "keyboard.onboarding.mic.body"
        )
    }

    private var speechStep: some View {
        stepBody(
            iconSystemName: "ear",
            title: "keyboard.onboarding.speech.title",
            body: "keyboard.onboarding.speech.body"
        )
    }

    private var keyboardStep: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "keyboard")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(palette.accent)
            Text(ExtL10n.string("keyboard.onboarding.keyboard.title"))
                .font(TypeStyle.headline)
                .foregroundStyle(palette.textPrimary)
                .multilineTextAlignment(.center)
            Text(ExtL10n.string("keyboard.onboarding.keyboard.body"))
                .font(TypeStyle.caption)
                .foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                state.openSystemSettings()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.right.square")
                    Text(ExtL10n.string("keyboard.onboarding.keyboard.openSettings"))
                }
                .font(TypeStyle.caption.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.xs + 2)
                .background(palette.accent, in: Capsule())
            }
            .accessibilityLabel(ExtL10n.string("keyboard.onboarding.keyboard.openSettings"))
        }
        .frame(maxWidth: .infinity)
    }

    private var apiStep: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "key.fill")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(palette.accent)
            Text(ExtL10n.string("keyboard.onboarding.api.title"))
                .font(TypeStyle.headline)
                .foregroundStyle(palette.textPrimary)
                .multilineTextAlignment(.center)
            Text(ExtL10n.string("keyboard.onboarding.api.body"))
                .font(TypeStyle.caption)
                .foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text(ExtL10n.string("keyboard.onboarding.api.skipHint"))
                .font(TypeStyle.caption2)
                .foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private func stepBody(
        iconSystemName: String,
        title: String,
        body: String
    ) -> some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: iconSystemName)
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(palette.accent)
            Text(ExtL10n.string(title))
                .font(TypeStyle.headline)
                .foregroundStyle(palette.textPrimary)
                .multilineTextAlignment(.center)
            Text(ExtL10n.string(body))
                .font(TypeStyle.caption)
                .foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: Spacing.xs) {
            if currentStep != .welcome {
                Button(ExtL10n.string("keyboard.onboarding.back")) {
                    state.onboardingPage = max(0, currentStep.rawValue - 1)
                }
                .font(TypeStyle.caption)
                .foregroundStyle(palette.textSecondary)
                .frame(minHeight: 36)
            }

            Spacer(minLength: 0)

            primaryButton
        }
    }

    @ViewBuilder
    private var primaryButton: some View {
        switch currentStep {
        case .welcome:
            Button(ExtL10n.string("keyboard.onboarding.getStarted")) {
                state.onboardingPage = 1
            }
            .buttonStyle(OverlayPrimaryButtonStyle(palette: palette))

        case .microphone:
            Button(ExtL10n.string("keyboard.onboarding.mic.grant")) {
                state.requestMicPermission()
                // Optimistically advance — if permission is denied the
                // status text on the next viewWillAppear will reflect it.
                state.onboardingPage = 2
            }
            .buttonStyle(OverlayPrimaryButtonStyle(palette: palette))

        case .speech:
            Button(ExtL10n.string("keyboard.onboarding.speech.grant")) {
                state.requestSpeechPermission()
                state.onboardingPage = 3
            }
            .buttonStyle(OverlayPrimaryButtonStyle(palette: palette))

        case .keyboard:
            // Step 3 is auto-advanced by viewWillAppear once the user
            // has enabled the keyboard in Settings.app. We don't show
            // a "Continue" button here — that would re-trigger the
            // confusion we're solving.
            Button(ExtL10n.string("keyboard.onboarding.keyboard.openSettings")) {
                state.openSystemSettings()
            }
            .buttonStyle(OverlayPrimaryButtonStyle(palette: palette))

        case .api:
            HStack(spacing: Spacing.xs) {
                Button(ExtL10n.string("keyboard.onboarding.api.skip")) {
                    state.completeOnboarding()
                }
                .font(TypeStyle.caption)
                .foregroundStyle(palette.textSecondary)
                .padding(.horizontal, Spacing.sm)
                .frame(minHeight: 36)

                Button(ExtL10n.string("keyboard.onboarding.api.openHostApp")) {
                    state.openSettings()
                }
                .buttonStyle(OverlayPrimaryButtonStyle(palette: palette))
            }
        }
    }
}

private struct OverlayPrimaryButtonStyle: ButtonStyle {
    let palette: ThemePalette

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(TypeStyle.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.xs + 2)
            .background(palette.accent.opacity(configuration.isPressed ? 0.7 : 1.0),
                        in: Capsule())
            .frame(minHeight: 36)
            .contentShape(Capsule())
    }
}