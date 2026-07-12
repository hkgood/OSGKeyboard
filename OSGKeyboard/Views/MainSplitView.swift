// MainSplitView.swift
// OSGKeyboard · Main App
//
// iPad / regular-width shell: sidebar navigation + detail workspace.
// Mirrors the macOS `NavigationSplitView` structure while keeping iOS tabs
// and Flow session behaviour unchanged underneath.

import SwiftUI
import OSGKeyboardShared
import UIKit

struct MainSplitView: View {
    @Binding var selection: AppTab

    @Environment(\.themePalette) private var palette

    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
                .navigationSplitViewColumnWidth(WideLayoutMetrics.sidebarWidth)
        } detail: {
            detail
        }
        .navigationSplitViewStyle(.balanced)
        .background(palette.background)
        // No floating dock in split mode — child scroll views should not
        // reserve bottom clearance for the phone tab bar.
        .environment(\.isTabBarVisible, false)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            brandHeader
            VStack(spacing: 4) {
                ForEach(AppTab.allCases, id: \.rawValue) { tab in
                    WideSidebarRow(
                        tab: tab,
                        isSelected: selection == tab
                    ) {
                        withAnimation(Motion.soft) { selection = tab }
                    }
                }
            }
            .padding(.horizontal, WideLayoutMetrics.sidebarInset)
            Spacer()
            devicesFooter
        }
        .background(palette.background)
    }

    private var brandHeader: some View {
        HStack {
            // Match macOS sidebar: template wide mark tinted with accent so
            // light / dark both stay readable (PNG `osglogo` can fail to
            // show under NavigationSplitView chrome on some iPad sizes).
            Image("OSGLogoWide")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(height: 28)
                .foregroundStyle(palette.accent)
                .accessibilityLabel("OSGKeyboard")
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
        .padding(.leading, WideLayoutMetrics.sidebarContentInset)
        .padding(.trailing, WideLayoutMetrics.sidebarInset)
        .padding(.top, Spacing.lg)
        .padding(.bottom, Spacing.md)
    }

    private var devicesFooter: some View {
        Label("home.wide.devices", systemImage: "ipad.and.iphone")
            .font(TypeStyle.caption2)
            .foregroundStyle(palette.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, WideLayoutMetrics.sidebarInset + Spacing.sm)
            .padding(.vertical, Spacing.sm)
    }

    // MARK: - Detail

    private var detail: some View {
        VStack(spacing: 0) {
            MainTabContent(tab: selection)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .id(selection)
                .transition(.opacity)
            WideStatusFooter()
        }
        .background(palette.background)
    }
}

// MARK: - Sidebar row

private struct WideSidebarRow: View {
    let tab: AppTab
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.themePalette) private var palette

    var body: some View {
        Button(action: action) {
            Label(tab.sidebarTitle, systemImage: tab.sidebarSystemImage)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? palette.accent : palette.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, 7)
                .background(
                    rowBackground,
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(Motion.quick, value: isSelected)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var rowBackground: Color {
        isSelected ? palette.accentMuted : .clear
    }
}

// MARK: - Status footer

/// Quiet bottom strip: engine mode + translation target + Flow readiness.
private struct WideStatusFooter: View {
    @Environment(\.themePalette) private var palette
    @ObservedObject private var config = ProviderConfig.shared
    @EnvironmentObject private var flowManager: FlowSessionManager

    @State private var micStatus = AppPermissions.micStatus
    @State private var speechStatus = AppPermissions.speechStatus

    private var needsCloudSetup: Bool {
        !config.isLocalEngine && !config.isConfigured
    }

    private var needsPermissionSetup: Bool {
        micStatus != .granted || speechStatus != .granted
    }

    private var canManuallyStartSession: Bool {
        !flowManager.isActive && !flowManager.isStarting && !needsPermissionSetup
    }

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Spacer()
            Label(
                config.engineMode == "cloud" ? "home.wide.mode.cloud" : "home.wide.mode.local",
                systemImage: config.engineMode == "cloud" ? "cloud" : "cpu"
            )
            .contentTransition(.opacity)

            Text("·")
                .foregroundStyle(palette.textTertiary.opacity(0.5))

            Label(
                translationLabel,
                systemImage: "translate"
            )
            .contentTransition(.opacity)

            Text("·")
                .foregroundStyle(palette.textTertiary.opacity(0.5))

            flowStatusControl
        }
        .font(TypeStyle.caption2)
        .foregroundStyle(palette.textTertiary)
        .labelStyle(.titleAndIcon)
        .padding(.horizontal, WideLayoutMetrics.pageHorizontalInset)
        .padding(.vertical, Spacing.sm)
        .animation(Motion.quick, value: config.engineMode)
        .animation(Motion.quick, value: config.translationTargetLocaleId)
        .animation(Motion.soft, value: flowManager.isActive)
        .onAppear { refreshPermissionStatuses() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            refreshPermissionStatuses()
        }
    }

    @ViewBuilder
    private var flowStatusControl: some View {
        HStack(spacing: Spacing.xs) {
            Circle()
                .fill(flowStatusColor)
                .frame(width: 6, height: 6)

            if needsCloudSetup {
                Text("home.flow.notReady")
                    .foregroundStyle(palette.warning)
            } else if flowManager.isUtteranceRecording {
                Text("home.flow.recording")
            } else if flowManager.isUtteranceProcessing {
                Text("home.flow.processing")
            } else if flowManager.isActive,
                      FlowSessionBridge.isHostReady(),
                      let expires = flowManager.sessionExpiresAt {
                Text("home.flow.label")
                Text(":")
                Text(expires, style: .timer)
                    .monospacedDigit()
            } else {
                Text(flowStatusLabel)
            }

            if flowManager.isActive {
                Button {
                    flowManager.endSession()
                } label: {
                    Text("home.flow.endShort")
                        .foregroundStyle(palette.accent)
                }
                .buttonStyle(.plain)
            } else if canManuallyStartSession && !needsCloudSetup {
                Button {
                    flowManager.activateOnForeground()
                } label: {
                    Text("home.flow.startShort")
                        .foregroundStyle(palette.accent)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func refreshPermissionStatuses() {
        micStatus = AppPermissions.micStatus
        speechStatus = AppPermissions.speechStatus
    }

    private var translationLabel: String {
        let resolved = TranslationLanguageCatalog.resolve(config.translationTargetLocaleId)
        if TranslationLanguageCatalog.isOff(resolved.id) {
            return AppL10n.string("keyboard.translation.offMenu", language: config.uiLanguage)
        }
        return resolved.nativeName
    }

    private var flowStatusColor: Color {
        if !config.isLocalEngine && !config.isConfigured { return palette.warning }
        if flowManager.isUtteranceRecording || flowManager.isUtteranceProcessing {
            return palette.accent
        }
        if flowManager.isActive, FlowSessionBridge.isHostReady() { return palette.accent }
        if flowManager.isStarting { return palette.accent }
        if flowManager.isActive { return palette.warning }
        return palette.textTertiary
    }

    private var flowStatusLabel: LocalizedStringKey {
        if !config.isLocalEngine && !config.isConfigured {
            return "home.flow.notReady"
        }
        if flowManager.isStarting {
            return "home.flow.starting"
        }
        if flowManager.isUtteranceRecording {
            return "home.flow.recording"
        }
        if flowManager.isUtteranceProcessing {
            return "home.flow.processing"
        }
        if flowManager.isActive, FlowSessionBridge.isHostReady() {
            return "home.flow.label"
        }
        if flowManager.isActive {
            return "home.flow.notReady"
        }
        return "home.flow.inactive"
    }
}
