// MainSplitView.swift
// OSGKeyboard · Main App
//
// iPad / regular-width shell: sidebar navigation + detail workspace.
// Mirrors the macOS `NavigationSplitView` structure while keeping iOS tabs
// and Flow session behaviour unchanged underneath.

import OSGKeyboardShared
import SwiftUI
import UIKit

struct MainSplitView: View {
    @Binding var selection: AppTab

    @Environment(\.themePalette) private var palette
    @Environment(\.wideTopCornerClearance) private var topCornerClearance

    var body: some View {
        // Sidebar is always visible: once collapsed, iPhone Duo offers no
        // control to bring it back.
        NavigationSplitView(columnVisibility: .constant(.all)) {
            sidebar
                .navigationSplitViewColumnWidth(WideLayoutMetrics.sidebarWidth)
                .toolbar(removing: .sidebarToggle)
        } detail: {
            detail
        }
        .navigationSplitViewStyle(.balanced)
        .background(palette.background)
        // No floating tab bar in split mode; shared footer spacing remains
        // useful for the final rows in each scroll view.
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
            WideSidebarStatusBar()
                .padding(.bottom, Spacing.xxs)
        }
        .background(palette.background)
    }

    private var brandHeader: some View {
        HStack {
            // Match macOS sidebar: template wide mark tinted with the primary
            // text color so light / dark both stay readable (PNG `osglogo` can
            // fail to show under NavigationSplitView chrome on some iPad sizes).
            Image("OSGLogoWide")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(height: 28)
                .foregroundStyle(palette.textPrimary)
                .accessibilityLabel("OSGKeyboard")
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
        .padding(.leading, WideLayoutMetrics.sidebarContentInset)
        .padding(.trailing, WideLayoutMetrics.sidebarInset)
        .padding(.top, Spacing.lg + topCornerClearance)
        // Roughly double the gap between the brand header and the first
        // sidebar row on iPad so the logo gets visual breathing room above
        // the menu list (was `Spacing.md`, now `Spacing.xxxl`).
        .padding(.bottom, Spacing.xxxl)
    }

    // MARK: - Detail

    private var detail: some View {
        MainTabContent(tab: selection)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .id(selection)
            .transition(.opacity)
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
            Label(
                AppL10n.string(tab.sidebarTitle),
                systemImage: tab.sidebarSystemImage(selected: isSelected)
            )
                .labelStyle(SidebarIconColumnLabelStyle())
                // Slightly larger label + taller vertical padding so each
                // sidebar row hits the Apple HIG 44pt touch target on iPad
                // (was size 13 / vertical 7 → ~32pt row; now size 15 /
                // vertical 12 → ~44pt row).
                .font(.system(size: 15, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? palette.accent : palette.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, 12)
                .background(
                    rowBackground,
                    in: RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
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

/// Reserves a uniform icon column so every sidebar title starts at the same x.
///
/// `DefaultLabelStyle` sizes the icon to each SF Symbol's intrinsic width, and
/// this sidebar's symbols range from ~13pt (`character.book.closed`) to ~17.5pt
/// (`house`) — enough to push titles apart by ~5pt. `List` reserves that column
/// automatically; this hand-rolled `VStack` sidebar has to do it itself.
private struct SidebarIconColumnLabelStyle: LabelStyle {
    /// Wider than the widest symbol in `AppTab.sidebarSystemImage(selected:)`.
    static let iconColumnWidth: CGFloat = 22

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: Spacing.xs) {
            configuration.icon
                .frame(width: Self.iconColumnWidth)
            configuration.title
        }
    }
}

// MARK: - Sidebar status

/// Sidebar bottom toolbar: Flow session toggle, engine, and translation as
/// icon buttons, with the session state as a single trailing word.
private struct WideSidebarStatusBar: View {
    /// 36pt hit target per button; the icon glyph stays at sidebar size.
    static let buttonSize: CGFloat = 36

    @Environment(\.themePalette) private var palette
    @ObservedObject private var config = ProviderConfig.shared
    @EnvironmentObject private var flowManager: FlowSessionManager
    @EnvironmentObject private var accountSession: AccountSessionCoordinator

    @State private var micStatus = AppPermissions.micStatus
    @State private var speechStatus = AppPermissions.speechStatus

    /// Same readiness rule as Home, so the footer and the Home account card
    /// never disagree about whether dictation works.
    private var needsAPIKeySetup: Bool {
        !HomeAccountSurfacePolicy.readiness(
            credentialSource: config.credentialSource,
            account: accountSession.sessionPhase == .signedOut ? .signedOut : .signedIn,
            isASRConfigured: config.isASRConfigured,
            isPolishConfigured: config.isPolishConfigured
        ).canDictate
    }

    private var needsPermissionSetup: Bool {
        micStatus != .granted || speechStatus != .granted
    }

    private var canManuallyStartSession: Bool {
        !flowManager.isActive && !flowManager.isStarting && !needsPermissionSetup
    }

    private var isCloudEngine: Bool {
        config.engineMode == "cloud"
    }

    private var isTranslating: Bool {
        !TranslationLanguageCatalog.isOff(config.translationTargetLocaleId)
    }

    /// Centers the first button on the sidebar menu's icon column.
    private var leadingInset: CGFloat {
        WideLayoutMetrics.sidebarContentInset
            + (SidebarIconColumnLabelStyle.iconColumnWidth - Self.buttonSize) / 2
    }

    var body: some View {
        VStack(spacing: Spacing.xs) {
            Divider()
                .overlay(palette.divider)
                .padding(.horizontal, WideLayoutMetrics.sidebarInset)

            HStack(spacing: Spacing.xxs) {
                sessionButton
                engineButton
                translationButton

                Spacer(minLength: Spacing.xs)

                sessionStatusText
                    .font(TypeStyle.caption)
                    .foregroundStyle(flowStatusColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.leading, leadingInset)
            .padding(.trailing, WideLayoutMetrics.sidebarContentInset)
        }
        .animation(Motion.quick, value: config.engineMode)
        .animation(Motion.quick, value: config.translationTargetLocaleId)
        .animation(Motion.soft, value: flowManager.isActive)
        .onAppear { refreshPermissionStatuses() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            refreshPermissionStatuses()
        }
    }

    // MARK: Session

    /// Starts or ends the session; when the service isn't set up it opens
    /// Settings instead, since starting would only fail.
    private var sessionButton: some View {
        Button(action: handleSessionTap) {
            toolbarIcon(
                flowManager.isActive ? "mic.fill" : "mic",
                tint: sessionIconTint,
                isHighlighted: flowManager.isActive
            )
            .overlay(alignment: .topTrailing) {
                // An idle session needs no badge; the grey glyph says enough.
                if showsStatusDot {
                    Circle()
                        .fill(flowStatusColor)
                        .frame(width: 6, height: 6)
                        .padding(Spacing.xs)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(!canTapSession)
        .help(AppL10n.string(sessionActionKey))
        .accessibilityLabel(AppL10n.string(sessionActionKey))
    }

    private var sessionIconTint: Color {
        if needsAPIKeySetup { return palette.warning }
        return flowManager.isActive ? palette.accent : palette.textSecondary
    }

    private var showsStatusDot: Bool {
        needsAPIKeySetup || flowManager.isActive || flowManager.isStarting
    }

    private var canTapSession: Bool {
        flowManager.isActive || needsAPIKeySetup || canManuallyStartSession
    }

    private var sessionActionKey: String {
        if flowManager.isActive { return "home.flow.end" }
        if needsAPIKeySetup { return "home.wide.status.setUp" }
        return "home.flow.start"
    }

    private func handleSessionTap() {
        if flowManager.isActive {
            flowManager.endSession()
        } else if needsAPIKeySetup {
            openSettings(.aiService)
        } else if canManuallyStartSession {
            flowManager.activateOnForeground(
                reason: "MainSplitView.startButton",
                startCapture: true
            )
        }
    }

    @ViewBuilder
    private var sessionStatusText: some View {
        if needsAPIKeySetup {
            Text(AppL10n.string("home.flow.notReady"))
        } else if flowManager.isUtteranceRecording {
            Text(AppL10n.string("home.flow.recording"))
        } else if flowManager.isUtteranceProcessing {
            Text(AppL10n.string("home.flow.processing"))
        } else if flowManager.isActive,
                  FlowSessionBridge.isHostReady(),
                  let expires = flowManager.sessionExpiresAt {
            HStack(spacing: Spacing.xxs) {
                Text(AppL10n.string("home.flow.label"))
                Text(expires, style: .timer)
                    .monospacedDigit()
            }
        } else {
            Text(AppL10n.string(flowStatusLabel))
        }
    }

    // MARK: Engine and translation

    /// Engine changes involve sign-in, credits, and cloud consent, so the
    /// button opens Settings instead of switching in place.
    private var engineButton: some View {
        Button {
            openSettings(.aiService)
        } label: {
            toolbarIcon(isCloudEngine ? "cloud" : "cpu", tint: palette.textSecondary)
        }
        .buttonStyle(.plain)
        .help(toolbarHelp(titleKey: "home.wide.status.engine", value: engineLabel))
        .accessibilityLabel(AppL10n.string("home.wide.status.engine"))
        .accessibilityValue(engineLabel)
    }

    private var translationButton: some View {
        Menu {
            Picker("", selection: translationSelection) {
                ForEach(TranslationLanguageCatalog.all) { language in
                    Text(translationDisplayLabel(for: language))
                        .tag(language.id)
                }
            }
            .labelsHidden()
        } label: {
            toolbarIcon(
                "globe",
                tint: isTranslating ? palette.accent : palette.textSecondary,
                isHighlighted: isTranslating
            )
        }
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .help(toolbarHelp(titleKey: "home.wide.status.translation", value: translationLabel))
        .accessibilityLabel(AppL10n.string("home.wide.status.translation"))
        .accessibilityValue(translationLabel)
    }

    private var engineLabel: String {
        AppL10n.string(isCloudEngine ? "home.wide.mode.cloud" : "home.wide.mode.local")
    }

    private func toolbarHelp(titleKey: String, value: String) -> String {
        "\(AppL10n.string(titleKey)) · \(value)"
    }

    private func toolbarIcon(
        _ systemImage: String,
        tint: Color,
        isHighlighted: Bool = false
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
        return Image(systemName: systemImage)
            .font(.system(size: 15, weight: .regular))
            .foregroundStyle(tint)
            .frame(width: Self.buttonSize, height: Self.buttonSize)
            .background(isHighlighted ? palette.accentMuted : .clear, in: shape)
            .contentShape(shape)
            .hoverEffect(.highlight)
            .contentTransition(.symbolEffect(.replace))
    }

    private func openSettings(_ link: SettingsDeepLink) {
        SettingsDeepLink.setPending(link)
        NotificationCenter.default.post(name: .osgOpenSettingsDeepLink, object: nil)
    }

    /// Same single field as Settings ▸ Translation (`TranslationPickerRow`).
    private var translationSelection: Binding<String> {
        Binding(
            get: { config.translationTargetLocaleId },
            set: { config.translationTargetLocaleId = TranslationLanguageCatalog.resolve($0).id }
        )
    }

    private func translationDisplayLabel(for language: TranslationLanguage) -> String {
        TranslationLanguageCatalog.isOff(language.id)
            ? AppL10n.string("settings.translation.off")
            : language.nativeName
    }

    private func refreshPermissionStatuses() {
        micStatus = AppPermissions.micStatus
        speechStatus = AppPermissions.speechStatus
    }

    private var translationLabel: String {
        translationDisplayLabel(for: TranslationLanguageCatalog.resolve(config.translationTargetLocaleId))
    }

    private var flowStatusColor: Color {
        if needsAPIKeySetup { return palette.warning }
        if flowManager.isUtteranceRecording || flowManager.isUtteranceProcessing {
            return palette.accent
        }
        if flowManager.isActive, FlowSessionBridge.isHostReady() { return palette.accent }
        if flowManager.isStarting { return palette.accent }
        if flowManager.isActive { return palette.warning }
        return palette.textTertiary
    }

    private var flowStatusLabel: String {
        if needsAPIKeySetup {
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
