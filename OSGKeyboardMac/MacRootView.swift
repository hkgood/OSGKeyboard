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

    /// `List` selection is optional; keep the view model's non-optional section
    /// in sync without letting a nil selection blank the detail pane.
    private var selection: Binding<MacSection?> {
        Binding(
            get: { viewModel.selectedSection },
            set: { if let new = $0 { viewModel.selectedSection = new } }
        )
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
                .navigationSplitViewColumnWidth(MacMetrics.sidebarWidth)
        } detail: {
            detail
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 860, minHeight: 600)
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
                    sidebarRow(section)
                }
            }
            .padding(.horizontal, MacMetrics.sidebarInset)
            Spacer()
            devicesFooter
        }
        .background(palette.surfaceMuted)
    }

    private func sidebarRow(_ section: MacSection) -> some View {
        let isSelected = viewModel.selectedSection == section

        return Button {
            viewModel.selectedSection = section
        } label: {
            Label(section.title(language: uiLanguage), systemImage: section.systemImage)
                .font(.system(size: 13))
                .foregroundStyle(isSelected ? palette.textOnAccent : palette.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, 7)
                .background(
                    isSelected ? palette.accent : Color.clear,
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Brand mark pinned above the nav list. Top padding clears the traffic
    /// lights that now float over the borderless sidebar.
    private var brandHeader: some View {
        HStack {
            Image("OSGLogoWide")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(height: 30)
                .foregroundStyle(palette.accent)
                .accessibilityLabel("OSGKeyboard")
            Spacer()
        }
        .padding(.leading, MacMetrics.sidebarContentInset)
        .padding(.trailing, MacMetrics.sidebarInset)
        .padding(.top, Spacing.lg)
        .padding(.bottom, Spacing.lg)
    }

    private var devicesFooter: some View {
        Label(
            MacL10n.string("mac.devices", language: uiLanguage),
            systemImage: "laptopcomputer.and.iphone"
        )
        .font(TypeStyle.caption)
        .foregroundStyle(palette.textTertiary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, MacMetrics.sidebarInset)
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
            MacStatusFooter(viewModel: viewModel)
        }
        .background(palette.background)
    }
}
