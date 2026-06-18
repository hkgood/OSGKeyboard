// OnboardingView.swift
// OSGKeyboard · Main App
//
// Three-step onboarding presented as a horizontal pager:
//
//   1) Welcome — what the app does, in one sentence
//   2) Enable  — Settings → General → Keyboards → Add → Allow Full Access
//   3) Setup   — pick a provider, paste a key
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
                TabView(selection: $page) {
                    WelcomePage().tag(0)
                    EnableKeyboardPage().tag(1)
                    APISetupPage(config: config).tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

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
                    Text("返回 · Back")
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
                Text(page == 2 ? (config.isConfigured ? "完成 · Done" : "继续 · Continue") : "下一步 · Next")
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
                Text("按住说话,松开即得润色文字。")
                    .font(TypeStyle.body)
                    .foregroundStyle(palette.textSecondary)
                    .multilineTextAlignment(.center)
                Text("Hold to talk. Release for polished text, in any app.")
                    .font(TypeStyle.footnote)
                    .foregroundStyle(palette.textTertiary)
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
                        title: "Audio stays on device · 音频不出本机",
                        body: "Transcribed locally with Apple's speech engine. · 由 Apple 端侧引擎转录")
            footnoteRow(icon: "wifi",
                        title: "Only the polished text is sent · 仅发送润色后文字",
                        body: "Sent to your chosen LLM to add structure & punctuation. · 仅向所选 LLM 发送润色后文字")
            footnoteRow(icon: "keyboard",
                        title: "Works everywhere · 处处可用",
                        body: "WeChat, Notes, Mail, ChatGPT, Claude, Cursor — anywhere a keyboard appears. · 微信、备忘录、邮件、ChatGPT、Claude、Cursor — 任何键盘出现的地方")
        }
        .padding(Spacing.md)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
                .stroke(palette.divider, lineWidth: 0.5)
        )
        .padding(.horizontal, Spacing.md)
    }

    private func footnoteRow(icon: String, title: String, body: String) -> some View {
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
                Text("启用 OSGKeyboard")
                    .font(TypeStyle.title2)
                    .foregroundStyle(palette.textPrimary)
                Text("Enable OSGKeyboard")
                    .font(TypeStyle.body)
                    .foregroundStyle(palette.textTertiary)
            }
            VStack(alignment: .leading, spacing: Spacing.sm) {
                step(num: 1, text: "设置 → 通用 → 键盘 → 键盘")
                step(num: 2, text: "点击「添加新键盘…」并选择 OSGKeyboard")
                step(num: 3, text: "点击 OSGKeyboard 并启用「允许完全访问」")
                step(num: 4, text: "Allow Full Access is required for microphone + LLM calls · 允许完全访问是麦克风和网络调用的前提")
            }
            .cardSurface()
            .padding(.horizontal, Spacing.md)

            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Label("打开 iOS 设置 · Open Settings", systemImage: "arrow.up.right.square")
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
                    Text("配置 AI 提供商")
                        .font(TypeStyle.title2)
                        .foregroundStyle(palette.textPrimary)
                    Text("Configure your AI provider")
                        .font(TypeStyle.body)
                        .foregroundStyle(palette.textTertiary)
                    Text("OSGKeyboard only calls the AI to polish your text. No audio leaves your device.")
                        .font(TypeStyle.footnote)
                        .foregroundStyle(palette.textSecondary)
                        .padding(.top, Spacing.xxs)
                }
                .padding(.horizontal, Spacing.md)
                .padding(.top, Spacing.lg)

                ProviderPickerSection(config: config)
                    .padding(.horizontal, Spacing.md)

                APISettingsCard(config: config)
                    .padding(.horizontal, Spacing.md)
            }
            .padding(.bottom, Spacing.xxxl)
        }
    }
}
