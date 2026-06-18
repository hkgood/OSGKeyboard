// OnboardingView.swift
// OSGKeyboard · Main App
//
// Three-step onboarding:
//
//   1) Welcome — what the app does, in one sentence
//   2) Enable  — Settings → General → Keyboards → Add → Allow Full Access
//   3) Setup   — pick a provider, paste a key
//
// We deliberately do NOT use `TabView` with `.page` style for the
// pager. That style wraps the content in a `UIPageViewController`,
// and `UIPageViewController` has a long-standing behavior on some iOS
// versions where
// the keyboard-showing layout reflow on a `TextField` focus is
// misread as a horizontal swipe — the page jumps back to step 1
// the moment the user starts typing. Replacing the TabView with a
// `ZStack`-based conditional view sidesteps the bug entirely; we
// give up the swipe-to-page gesture, but the Back/Next buttons at
// the bottom (and the page dots) are the canonical onboarding
// affordance and the user is never more than one tap from the next
// page anyway.
//
// Visual style: one large accent surface, generous whitespace, single CTA
// at the bottom. No tipsy animations, no cheerful illustrations — every
// pixel is doing one job.

import SwiftUI
import OSGKeyboardShared

struct OnboardingView: View {
    @Environment(\.themePalette) private var palette: ThemePalette

    @ObservedObject var config: ProviderConfig
    @State private var page: Int = 0

    var body: some View {
        ZStack {
            palette.background.ignoresSafeArea()
            VStack(spacing: 0) {
                Group {
                    switch page {
                    case 0: WelcomePage()
                    case 1: EnableKeyboardPage()
                    default: APISetupPage(config: config)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity.combined(with: .move(edge: .trailing)))

                pageDots
                    .padding(.bottom, Spacing.md)

                bottomBar
                    .padding(.horizontal, Spacing.md)
                    .padding(.bottom, Spacing.lg)
            }
        }
    }

    private var pageDots: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { i in
                Capsule()
                    .fill(i == page ? palette.accent : Color.white.opacity(0.18))
                    .frame(width: i == page ? 18 : 6, height: 6)
                    .animation(Motion.quick, value: page)
            }
        }
    }

    @ViewBuilder
    private var bottomBar: some View {
        HStack(spacing: Spacing.sm) {
            if page > 0 {
                Button { withAnimation(Motion.soft) { page -= 1 } } label: {
                    Text("common.back")
                        .font(TypeStyle.headline)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(palette.surface, in: RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
                                .stroke(palette.dividerStrong, lineWidth: 0.5)
                        )
                        .foregroundStyle(palette.textPrimary)
                }
                .buttonStyle(.plain)
            }

            Button {
                withAnimation(Motion.soft) {
                    if page < 2 { page += 1 }
                }
            } label: {
                Text(page == 2
                     ? (config.isConfigured
                        ? NSLocalizedString("common.done", comment: "")
                        : NSLocalizedString("common.continue", comment: ""))
                     : NSLocalizedString("common.next", comment: ""))
                    .font(TypeStyle.headline)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(
                        (page == 2 && !config.isConfigured) ? palette.surfaceElevated : palette.accent,
                        in: RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
                    )
                    .foregroundStyle(
                        (page == 2 && !config.isConfigured) ? palette.textSecondary : palette.textOnAccent
                    )
            }
            .buttonStyle(.plain)
            .disabled(page == 2 && !config.isConfigured)
        }
    }
}

// MARK: - Page 1: Welcome

private struct WelcomePage: View {
    @Environment(\.themePalette) private var palette: ThemePalette

    var body: some View {
        VStack(spacing: Spacing.xl) {
            Spacer()
            ZStack {
                Circle()
                    .fill(palette.accentMuted)
                    .frame(width: 180, height: 180)
                    .blur(radius: 30)
                Image(systemName: "mic.circle.fill")
                    .font(.system(size: 96, weight: .light))
                    .foregroundStyle(palette.accent)
            }
            VStack(spacing: Spacing.sm) {
                Text("OSGKeyboard")
                    .font(TypeStyle.title)
                    .foregroundStyle(palette.textPrimary)
                Text("onboarding.welcome.subtitle")
                    .font(TypeStyle.body)
                    .foregroundStyle(palette.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, Spacing.xl)
            PrivacyFootnote()
                .padding(.top, Spacing.lg)
            Spacer()
        }
    }
}

private struct PrivacyFootnote: View {
    @Environment(\.themePalette) private var palette: ThemePalette

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            footnoteRow(icon: "lock.fill",
                        title: "privacy.audio.title",
                        body: "privacy.audio.body")
            footnoteRow(icon: "wifi",
                        title: "privacy.network.title",
                        body: "privacy.network.body")
            footnoteRow(icon: "keyboard",
                        title: "privacy.universal.title",
                        body: "privacy.universal.body")
        }
        .padding(Spacing.md)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
                .stroke(palette.divider, lineWidth: 0.5)
        )
        .padding(.horizontal, Spacing.md)
    }

    // `LocalizedStringKey` (not `String`) so the call-site string
    // literals are auto-looked-up in Localizable.strings. Passing a
    // plain `String` would just print the key.
    private func footnoteRow(icon: String, title: LocalizedStringKey, body: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: Spacing.xs) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(palette.accent)
                .frame(width: 24, height: 24)
                .background(palette.accentMuted, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(TypeStyle.caption)
                    .foregroundStyle(palette.textPrimary)
                Text(body)
                    .font(TypeStyle.caption2)
                    .foregroundStyle(palette.textSecondary)
            }
        }
    }
}

// MARK: - Page 2: Enable keyboard

private struct EnableKeyboardPage: View {
    @Environment(\.themePalette) private var palette: ThemePalette

    var body: some View {
        VStack(spacing: Spacing.xl) {
            Spacer()
            Image(systemName: "keyboard.fill")
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(palette.accent)
            VStack(spacing: Spacing.sm) {
                Text("onboarding.enable.title")
                    .font(TypeStyle.title2)
                    .foregroundStyle(palette.textPrimary)
            }
            VStack(alignment: .leading, spacing: Spacing.sm) {
                step(num: 1, text: NSLocalizedString("onboarding.enable.step1", comment: ""))
                step(num: 2, text: NSLocalizedString("onboarding.enable.step2", comment: ""))
                step(num: 3, text: NSLocalizedString("onboarding.enable.step3", comment: ""))
                step(num: 4, text: NSLocalizedString("onboarding.enable.step4", comment: ""))
            }
            .cardSurface()
            .padding(.horizontal, Spacing.md)

            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Label(LocalizedStringKey("onboarding.enable.openSettings"), systemImage: "arrow.up.right.square")
                    .primaryButton()
            }
            .padding(.horizontal, Spacing.md)
            Spacer()
        }
    }

    private func step(num: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: Spacing.xs) {
            Text("\(num)")
                .font(TypeStyle.caption2)
                .frame(width: 22, height: 22)
                .background(palette.accent, in: Circle())
                .foregroundStyle(palette.textOnAccent)
            Text(text)
                .font(TypeStyle.body)
                .foregroundStyle(palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Page 3: API setup

private struct APISetupPage: View {
    @Environment(\.themePalette) private var palette: ThemePalette

    @ObservedObject var config: ProviderConfig

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.md) {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text("onboarding.api.title")
                        .font(TypeStyle.title2)
                        .foregroundStyle(palette.textPrimary)
                    Text("onboarding.api.subtitle")
                        .font(TypeStyle.footnote)
                        .foregroundStyle(palette.textTertiary)
                        .padding(.top, Spacing.xxs)
                }
                .padding(.horizontal, Spacing.md)
                .padding(.top, Spacing.lg)

                // Same Engine picker as Settings — see EnginePickerSection.
                EnginePickerSection(config: config)
                    .padding(.horizontal, Spacing.md)

                if config.engineMode == "cloud" {
                    ProviderPickerSection(config: config)
                        .padding(.horizontal, Spacing.md)

                    APISettingsCard(config: config)
                        .padding(.horizontal, Spacing.md)
                } else {
                    // Local path: no LLM, no API key needed. Show a short
                    // confirmation so the user understands "no further
                    // setup required".
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        HStack(spacing: Spacing.sm) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(palette.accent)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("onboarding.api.localReady.title")
                                    .font(TypeStyle.body)
                                    .foregroundStyle(palette.textPrimary)
                                Text("onboarding.api.localReady.body")
                                    .font(TypeStyle.caption2)
                                    .foregroundStyle(palette.textTertiary)
                            }
                            Spacer()
                        }
                        .padding(Spacing.md)
                    }
                    .background(palette.surface, in: RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
                            .stroke(palette.divider, lineWidth: 0.5)
                    )
                    .padding(.horizontal, Spacing.md)
                }
            }
            .padding(.bottom, Spacing.xxxl)
        }
    }
}
