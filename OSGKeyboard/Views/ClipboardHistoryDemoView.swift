// ClipboardHistoryDemoView.swift
// OSGKeyboard · Main App (DEBUG-only)
//
// What's New 1.7.0 recording host. Voice chrome + clipboard panel are the
// **real** extension views (`KeyboardTopControls`, `RecordButton`,
// `KeyboardTranslationMenuButton`, `ClipboardHistoryPanelView`, …) driven by
// scripted `KeyboardState`. Launch with `--clipboard-demo`.

#if DEBUG
import SwiftUI
import OSGKeyboardShared

struct ClipboardHistoryDemoView: View {
    private enum Layout {
        static let micSize: CGFloat = 121
        static let undoSize: CGFloat = 52
        static let micToButtonGap: CGFloat = 8
        static let actionClusterTopGap: CGFloat = Spacing.xl
        static let micUpwardAdjustment: CGFloat =
            (actionClusterTopGap - micToButtonGap) / 2
    }

    @StateObject private var state = KeyboardState()
    @StateObject private var typing = TypingSessionController()
    @StateObject private var history = ClipboardHistoryStore(
        defaults: UserDefaults(suiteName: "osg.whatsnew.clipboard.demo")
    )

    @Environment(\.colorScheme) private var colorScheme

    private var palette: ThemePalette {
        colorScheme == .dark ? Palette.dark : Palette.light
    }

    var body: some View {
        ZStack {
            Color(red: 0.06, green: 0.06, blue: 0.07).ignoresSafeArea()
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                keyboardChrome
                    .background(palette.background.ignoresSafeArea(edges: .bottom))
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(palette.divider)
                            .frame(height: 0.5)
                    }
            }
        }
        .environment(\.themePalette, palette)
        .environment(\.locale, Locale(identifier: "zh-Hans"))
        .preferredColorScheme(.light)
        .task { await runTimeline() }
    }

    // MARK: - Real keyboard chrome (voice + clipboard overlay)

    private var keyboardChrome: some View {
        ZStack {
            voiceSurface
                .opacity(state.clipboardOverlay == .none ? 1 : 0)
                .allowsHitTesting(state.clipboardOverlay == .none)

            if state.clipboardOverlay == .historyPanel {
                ClipboardHistoryPanelView(
                    history: history,
                    onClose: { state.clipboardOverlay = .none },
                    onClear: { history.clearAll() },
                    onInsert: { text in
                        state.clipboardSuggestionText = text
                        state.clipboardOverlay = .none
                    },
                    onDelete: { history.remove(id: $0) },
                    pastePermissionHint: nil
                )
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, KeyboardChromeLayout.horizontalInset)
        .frame(maxWidth: .infinity)
        .frame(height: KeyboardChromeLayout.totalHeight)
        .padding(.bottom, 24)
        .environment(\.themePalette, palette)
    }

    private var voiceSurface: some View {
        VStack(spacing: 0) {
            topBar.frame(height: KeyboardTopBarMetrics.height)
            Color.clear.frame(height: Layout.actionClusterTopGap)
            Spacer(minLength: 0)
            micActionRow
        }
        .frame(maxWidth: KeyboardChromeLayout.voiceContentMaxWidth)
        .frame(maxWidth: .infinity)
    }

    private var topBar: some View {
        HStack(spacing: Spacing.xs) {
            if let suggestion = state.clipboardSuggestionText, !suggestion.isEmpty {
                ClipboardSuggestionBar(
                    text: suggestion,
                    onInsert: {},
                    onDismiss: { state.clipboardSuggestionText = nil }
                )
            } else {
                KeyboardBrandLogo(action: {})
                Spacer(minLength: 0)
                KeyboardTopControls(
                    state: state,
                    typing: typing,
                    palette: palette,
                    onInsert: { _ in }
                )
            }
        }
        .padding(.horizontal, KeyboardTopBarMetrics.nestedHorizontalInset)
    }

    private var micActionRow: some View {
        VStack(spacing: Layout.micToButtonGap) {
            HStack(spacing: 0) {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(alignment: .leading) {
                        demoKey(
                            systemName: "arrow.uturn.backward",
                            width: Layout.undoSize,
                            height: Layout.undoSize
                        )
                        .offset(y: -Layout.micUpwardAdjustment)
                    }

                RecordButton(
                    phase: .idleReady,
                    level: 0,
                    isEnabled: true,
                    onToggle: {},
                    onPressingChanged: { _ in },
                    onEditLongPressBegan: nil
                )
                .frame(width: Layout.micSize, height: Layout.micSize)
                .offset(y: -Layout.micUpwardAdjustment)

                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(alignment: .trailing) {
                        KeyboardTranslationMenuButton(
                            palette: palette,
                            targetLocaleId: TranslationLanguageCatalog.offLocaleId,
                            onSelect: { _ in }
                        )
                        .equatable()
                        .frame(width: Layout.undoSize, height: Layout.undoSize)
                        .offset(y: -Layout.micUpwardAdjustment)
                    }
            }
            .frame(height: Layout.micSize)

            GeometryReader { proxy in
                let widths = KeyboardChromeLayout.actionKeyWidthsWithoutGlobe(
                    availableWidth: proxy.size.width
                )
                HStack(spacing: KeyboardChromeLayout.actionKeySpacing) {
                    demoKey(systemName: "delete.backward", width: widths.side)
                    demoKey(
                        title: ExtL10n.string("common.newline"),
                        width: widths.center
                    )
                    demoKey(spaceStyle: true, width: widths.side2)
                }
            }
            .frame(height: KeyboardChromeLayout.actionKeyHeight)
        }
        .padding(.horizontal, KeyboardChromeLayout.horizontalInset)
    }

    /// Same chrome as Ext `RectangularToolbarButton` / native key surface.
    private func demoKey(
        systemName: String? = nil,
        title: String? = nil,
        spaceStyle: Bool = false,
        width: CGFloat,
        height: CGFloat = KeyboardChromeLayout.actionKeyHeight
    ) -> some View {
        NativeKeyboardKeySurface(
            isPressed: false,
            fill: NativeKeyboardKeyColors.fill(for: colorScheme),
            pressedFill: NativeKeyboardKeyColors.pressedFill(for: colorScheme),
            border: palette.divider,
            cornerRadius: KeyboardChromeLayout.actionKeyCornerRadius
        ) {
            Group {
                if spaceStyle {
                    Capsule()
                        .fill(NativeKeyboardKeyColors.text(for: colorScheme).opacity(0.22))
                        .frame(width: 31, height: 4)
                } else if let systemName {
                    Image(systemName: systemName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(NativeKeyboardKeyColors.text(for: colorScheme))
                } else if let title {
                    Text(title)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(NativeKeyboardKeyColors.text(for: colorScheme))
                }
            }
        }
        .frame(width: width, height: height)
    }

    // MARK: - Timeline

    private func runTimeline() async {
        prepareState()
        seedHistory()

        // Hold on voice idle so translation + clipboard chip are readable.
        try? await sleep(2.2)

        withAnimation(.easeInOut(duration: 0.2)) {
            state.clipboardOverlay = .historyPanel
        }
        try? await sleep(2.0)

        if let head = history.newestEntry {
            withAnimation(.easeInOut(duration: 0.25)) {
                state.clipboardSuggestionText = head.text
                state.clipboardOverlay = .none
            }
        }
        try? await sleep(2.4)
    }

    private func prepareState() {
        state.surface = .voice
        state.micVoiceAvailability = .ready
        state.layoutWidth = 390
        state.usesIPadLayoutMetrics = false
        state.showsSystemGlobeKey = false
        state.clipboardOverlay = .none
        state.clipboardSuggestionText = nil
        state.openClipboardPanel = {
            state.clipboardOverlay = .historyPanel
        }
        state.dismissClipboardOverlay = {
            state.clipboardOverlay = .none
        }
        state.insertClipboardText = { text in
            state.clipboardSuggestionText = text
            state.clipboardOverlay = .none
        }
    }

    private func seedHistory() {
        history.clearAll()
        _ = history.ingest(rawText: "订单号 OSG-20260811-8842", changeCount: 3)
        _ = history.ingest(rawText: "https://osglab.com", changeCount: 2)
        _ = history.ingest(rawText: "明天下午三点会议室见", changeCount: 1)
        history.reload()
    }

    private func sleep(_ seconds: Double) async throws {
        try await Task.sleep(nanoseconds: UInt64(seconds * 2.4 * 1_000_000_000))
    }
}
#endif
