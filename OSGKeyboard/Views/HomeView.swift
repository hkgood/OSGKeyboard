// HomeView.swift
// OSGKeyboard · Main App
//
// Post-onboarding home. Two jobs: (1) tell the user we're ready, and
// (2) give a clear path to the next setup step if anything is missing.

import SwiftUI
import OSGKeyboardShared
import OSGKeyboardExt

struct HomeView: View {
    @Environment(\.themePalette) private var palette: ThemePalette

    @ObservedObject var config = ProviderConfig.shared
    @State private var showSettings = false
    @State private var showKeyboardPreview = false

    var body: some View {
        ZStack {
            palette.background.ignoresSafeArea()
            VStack(spacing: 0) {
                statusHeader
                    .padding(.top, Spacing.xl)
                Spacer()
                heroButton
                Spacer()
                actionStack
                    .padding(.horizontal, Spacing.md)
                    .padding(.bottom, Spacing.lg)
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showKeyboardPreview) {
            KeyboardPreviewSheet()
        }
    }

    // MARK: - Header

    private var statusHeader: some View {
        VStack(spacing: Spacing.xs) {
            HStack(spacing: 6) {
                Circle()
                    .fill(config.isConfigured ? palette.success : palette.warning)
                    .frame(width: 8, height: 8)
                Text(config.isConfigured ? "就绪 · Ready" : "未完成配置 · Setup incomplete")
                    .font(TypeStyle.caption)
                    .foregroundStyle(palette.textSecondary)
            }
            Text("OSGKeyboard")
                .font(TypeStyle.largeTitle)
                .foregroundStyle(palette.textPrimary)
            Text(providerLine)
                .font(TypeStyle.caption)
                .foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.center)
        }
    }

    private var providerLine: String {
        let p = LLMProvider.provider(id: config.providerId)
        let model = config.model.isEmpty ? "—" : config.model
        return "\(p.name)  ·  \(model)"
    }

    // MARK: - Hero

    private var heroButton: some View {
        Button {
            showSettings = true
        } label: {
            ZStack {
                Circle()
                    .fill(palette.accentMuted)
                    .frame(width: 220, height: 220)
                    .blur(radius: 40)
                Circle()
                    .fill(LinearGradient(
                        colors: [palette.surfaceElevated, palette.surface],
                        startPoint: .top,
                        endPoint: .bottom
                    ))
                    .frame(width: 160, height: 160)
                    .overlay(
                        Circle().stroke(palette.accent.opacity(0.35), lineWidth: 1.5)
                    )
                    .shadow(color: palette.accent.opacity(0.18), radius: 24, y: 8)
                VStack(spacing: 6) {
                    Image(systemName: "waveform")
                        .font(.system(size: 36, weight: .light))
                        .foregroundStyle(palette.accent)
                    Text("点此配置 · Tap to configure")
                        .font(TypeStyle.caption)
                        .foregroundStyle(palette.textSecondary)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("打开设置 · Open OSGKeyboard settings"))
    }

    // MARK: - Actions

    private var actionStack: some View {
        VStack(spacing: Spacing.xs) {
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Label("启用键盘 · Enable in iOS Settings", systemImage: "keyboard")
                    .primaryButton()
            }
            .buttonStyle(.plain)

            Button {
                showSettings = true
            } label: {
                Label("编辑 API 配置 · Edit API Configuration", systemImage: "slider.horizontal.3")
                    .secondaryButton()
            }
            .buttonStyle(.plain)

            #if DEBUG
            Button {
                showKeyboardPreview = true
            } label: {
                Label("键盘预览 · Keyboard Preview (Debug)", systemImage: "eye")
                    .secondaryButton()
            }
            .buttonStyle(.plain)
            #endif

            HStack(spacing: Spacing.xs) {
                Button {
                    if let url = URL(string: "https://github.com/hkgood/OSGKeyboard") {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Text("GitHub")
                        .font(TypeStyle.caption)
                        .foregroundStyle(palette.textSecondary)
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, 6)
                        .background(palette.surface, in: Capsule())
                        .overlay(Capsule().stroke(palette.divider, lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                Spacer()
                Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0")")
                    .font(TypeStyle.caption2)
                    .foregroundStyle(palette.textTertiary)
            }
        }
    }
}
