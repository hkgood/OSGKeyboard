// MacRootView.swift
// OSGKeyboard · Mac
//
// Window shell built on the native `NavigationSplitView` so the desktop app
// reads like macOS System Settings: traffic lights float over a borderless
// sidebar, no separate title bar. The same structure lifts cleanly onto
// iPadOS later (NavigationSplitView is cross-platform).

import SwiftUI

struct MacRootView: View {
    @ObservedObject var viewModel: MacDictationViewModel

    @Environment(\.themePalette) private var palette
    @Environment(\.openWindow) private var openWindow

    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    private var uiLanguage: AppUILanguage { viewModel.config.uiLanguage }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
                .navigationSplitViewColumnWidth(MacMetrics.sidebarWidth)
        } detail: {
            detail
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: MacMetrics.windowMinWidth, minHeight: MacMetrics.windowMinHeight)
        .onAppear {
            // Let the AppKit status-bar popover reopen this window on demand.
            MacWindowBridge.shared.open = { openWindow(id: "main") }
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            brandHeader
            VStack(spacing: 4) {
                ForEach(MacSection.allCases) { section in
                    MacSidebarRow(
                        section: section,
                        isSelected: viewModel.selectedSection == section,
                        language: uiLanguage
                    ) {
                        withAnimation(Motion.soft) { viewModel.selectedSection = section }
                    }
                }
            }
            .padding(.horizontal, MacMetrics.sidebarInset)
            Spacer()
            devicesFooter
        }
    }

    /// Brand mark pinned above the nav list. Top padding clears the traffic
    /// lights that now float over the borderless sidebar.
    private var brandHeader: some View {
        HStack {
            Image("OSGLogoWide")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(height: 28)
                .foregroundStyle(palette.accent)
                .accessibilityLabel("OSGKeyboard")
            Spacer()
        }
        .padding(.leading, MacMetrics.sidebarContentInset)
        .padding(.trailing, MacMetrics.sidebarInset)
        .padding(.top, Spacing.lg)
        .padding(.bottom, Spacing.md)
    }

    private var devicesFooter: some View {
        Label(
            MacL10n.string("mac.devices", language: uiLanguage),
            systemImage: "laptopcomputer.and.iphone"
        )
        .font(TypeStyle.caption2)
        .foregroundStyle(palette.textTertiary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, MacMetrics.sidebarInset + Spacing.sm)
        .padding(.vertical, Spacing.sm)
    }

    // MARK: - Detail

    private var detail: some View {
        VStack(spacing: 0) {
            Group {
                switch viewModel.selectedSection {
                case .dashboard:  DashboardView(viewModel: viewModel)
                case .history:    MacHistoryView(viewModel: viewModel)
                case .dictionary: MacDictionaryView(viewModel: viewModel)
                case .settings:   MacSettingsView(viewModel: viewModel)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .id(viewModel.selectedSection)
            .transition(.opacity)
            MacStatusFooter(viewModel: viewModel)
        }
        .background(palette.background)
    }
}

// MARK: - Sidebar row

/// Navigation row with a restrained selected state: muted accent fill +
/// accent label (not a solid green pill), matching System Settings polish.
private struct MacSidebarRow: View {
    let section: MacSection
    let isSelected: Bool
    let language: AppUILanguage
    let action: () -> Void

    @Environment(\.themePalette) private var palette
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Label(section.title(language: language), systemImage: section.systemImage)
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
        .animation(Motion.quick, value: isHovering)
        .onHover { isHovering = $0 }
    }

    private var rowBackground: Color {
        if isSelected { return palette.accentMuted }
        return isHovering ? palette.textPrimary.opacity(0.05) : .clear
    }
}
