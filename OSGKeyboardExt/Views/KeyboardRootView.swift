// KeyboardRootView.swift
// OSGKeyboard · Keyboard Extension
//
// Typeless-inspired keyboard surface. The keyboard is laid out in three
// vertical bands, but the entire height is reserved for us — we set
// `KeyboardViewController` drives height on `view` (priority 999) and mirrors
// `KeyboardLayoutMetrics.totalHeight` in SwiftUI — see presentation offset
// in `applyPresentationHeightOffset()`.
//
//   ┌───────────────────────────────────────────┐
//   │  [OSG]                  语音 中文 EN 译     │  ← header band (top)
//   │              (transcript preview)         │
//   │              ┊                          │
//   │              ◯ mic (centred)              │  ← action cluster:
//   │   [delete]  [ return ]  [space]           │     mic + bottom row
//   │              ┊                          │
//   └───────────────────────────────────────────┘

import SwiftUI
import OSGKeyboardShared

private enum KeyboardLayoutMetrics {
    static let micSize: CGFloat = 121
    static let micToButtonGap: CGFloat = 8
    static let bottomActionRowHeight: CGFloat = KeyboardChromeLayout.actionKeyHeight
    static let bottomActionSpacing: CGFloat = KeyboardChromeLayout.actionKeySpacing
    /// Gap between the top control row and the transcript / hint line.
    /// Four points keeps the "点按说话" line visually attached to the controls.
    static let topBarToTranscriptSpacing: CGFloat = Spacing.xs / 2
    /// Match the typing key grid's outer edge.
    static let sideActionHorizontalInset: CGFloat = KeyboardChromeLayout.horizontalInset
    /// iPad: cap the content column. A full-width (~1180 pt) keyboard would
    /// park delete/return at the far screen edges and turn each cursor-drag
    /// pad into a ~450 pt runway — capping keeps the reach ergonomics of the
    /// phone layout. iPhone widths are all below this, so it is a no-op there.
    static let contentMaxWidth: CGFloat = KeyboardChromeLayout.contentMaxWidth

    // MARK: - Content-driven keyboard height (single source of truth)
    static let outerPaddingTop: CGFloat = 4
    static let outerPaddingBottom: CGFloat = 4
    static let topBarHeight: CGFloat = KeyboardTopBarMetrics.height
    static let transcriptLineHeight: CGFloat = 22
    /// mic (121) + gap (8) + bottom row (50) = 179 pt
    static let actionClusterHeight: CGFloat = micSize + micToButtonGap + bottomActionRowHeight
    /// Moves the action cluster down so its keys share the typing row's baseline.
    static let actionClusterTopGap: CGFloat = Spacing.xl
    /// Centres the mic between the transcript hint and bottom action row.
    static let micUpwardAdjustment: CGFloat = (actionClusterTopGap - micToButtonGap) / 2
    /// The shared 4 pt outer padding is the complete bottom inset.
    static let actionClusterBottomGap: CGFloat = 0

    static var headerBandHeight: CGFloat {
        topBarHeight + topBarToTranscriptSpacing + transcriptLineHeight
    }

    /// 4 + 70 + 24 + 179 + 0 + 4 = 281 pt, matching Chinese / English.
    static let totalHeight: CGFloat = KeyboardChromeLayout.totalHeight
}

public struct KeyboardRootView: View {
    @Environment(\.colorScheme) private var colorScheme

    @ObservedObject var state: State
    @ObservedObject var typing: TypingSessionController
    let onInsert: (String) -> Void

    public init(
        state: KeyboardViewController.State,
        typing: TypingSessionController,
        onInsert: @escaping (String) -> Void = { _ in }
    ) {
        self.state = state
        self.typing = typing
        self.onInsert = onInsert
    }

    /// Content-driven keyboard height; mirrored on `UIInputViewController.view`
    /// in `KeyboardViewController` (see `KeyboardLayoutMetrics.totalHeight`).
    static let totalHeight: CGFloat = KeyboardLayoutMetrics.totalHeight

    // MARK: - Cursor-drag pad geometry

    /// Mic disc side length.
    static let micSize: CGFloat = KeyboardLayoutMetrics.micSize
    /// Vertical offset from the keyboard's top edge to the mic disc.
    static let micTopOffset: CGFloat = KeyboardLayoutMetrics.outerPaddingTop
        + KeyboardLayoutMetrics.headerBandHeight
        + KeyboardLayoutMetrics.actionClusterTopGap
        - KeyboardLayoutMetrics.micUpwardAdjustment
    /// Horizontal inset the side pads should respect.
    static let sideInset: CGFloat = KeyboardLayoutMetrics.sideActionHorizontalInset

    private var palette: ThemePalette {
        colorScheme == .dark ? Palette.dark : Palette.light
    }

    public var body: some View {
        ZStack {
            VStack(spacing: 0) {
                headerBand

                Color.clear
                    .frame(height: KeyboardLayoutMetrics.actionClusterTopGap)

                micActionRow
                    .frame(height: KeyboardLayoutMetrics.actionClusterHeight)

                Color.clear
                    .frame(height: KeyboardLayoutMetrics.actionClusterBottomGap)
            }
            .padding(.top, KeyboardLayoutMetrics.outerPaddingTop)
            .padding(.bottom, KeyboardLayoutMetrics.outerPaddingBottom)
            // 透明背景：让系统键盘 chrome 透出，不自行铺色（深浅模式一致）。
            .background(Color.clear)
            .frame(maxWidth: KeyboardLayoutMetrics.contentMaxWidth)
            .frame(maxWidth: .infinity)
            .frame(height: Self.totalHeight)
            // Feed the resolved palette to all nested chips/buttons.
            .environment(\.themePalette, palette)
        }
        .animation(.easeInOut(duration: 0.12), value: state.cursorDragActive)
    }

    /// Top brand / mode row + transcript / hint line.
    private var headerBand: some View {
        VStack(spacing: KeyboardLayoutMetrics.topBarToTranscriptSpacing) {
            topBar
                .frame(height: KeyboardLayoutMetrics.topBarHeight)

            TranscriptLine(
                phase: state.phase,
                transcript: state.lastTranscript,
                micVoiceAvailability: state.micVoiceAvailability,
                micDisabledHint: state.micDisabledHint,
                cursorDragHintActive: state.cursorDragActive,
                openSettings: state.openSettings
            )
            .frame(height: KeyboardLayoutMetrics.transcriptLineHeight)
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: Spacing.xs) {
            KeyboardBrandLogo(action: state.openSettings)
            // Engine controls remain available in the host app.
            // App context is auto-detected on each mic press — no UI.
            Spacer(minLength: 0)
            KeyboardTopControls(
                state: state,
                typing: typing,
                palette: palette,
                onInsert: onInsert
            )
        }
        .padding(.horizontal, KeyboardTopBarMetrics.horizontalInset)
    }

    // MARK: - Action cluster

    /// Mic centred above a bottom row: delete · smart return · space (or swapped).
    /// The side cursor-drag pads are SwiftUI layout wrappers around UIKit
    /// pan recognizers, avoiding SwiftUI gesture delivery issues in
    /// keyboard extensions.
    private var micActionRow: some View {
        let editingBlocked = voiceInputBlocksEditing
        let swapKeys = state.handednessPreference.swapsActionKeys
        let cursorPadsEnabled = state.cursorDragNavigationEnabled && !editingBlocked

        // Dragging hides the mic + bottom keys (kept in the layout via
        // opacity so the pads' hit area never shifts mid-gesture) and lets
        // the cursor-drag chrome take over.
        let dragging = state.cursorDragActive

        return VStack(spacing: KeyboardLayoutMetrics.micToButtonGap) {
            HStack(spacing: 0) {
                cursorDragPad(enabled: cursorPadsEnabled)

                RecordButton(
                    phase: buttonPhase,
                    level: state.level,
                    remainingSeconds: state.phase == .recording ? state.utteranceRemainingSeconds : nil,
                    isEnabled: !state.micDisabled,
                    onToggle: state.tapMic
                )
                .frame(width: KeyboardLayoutMetrics.micSize, height: KeyboardLayoutMetrics.micSize)
                .offset(y: -KeyboardLayoutMetrics.micUpwardAdjustment)
                .opacity(dragging ? 0 : 1)

                cursorDragPad(enabled: cursorPadsEnabled)
            }
            .frame(height: KeyboardLayoutMetrics.micSize)

            GeometryReader { proxy in
                let widths = KeyboardChromeLayout.actionKeyWidths(
                    availableWidth: proxy.size.width
                )

                HStack(spacing: KeyboardLayoutMetrics.bottomActionSpacing) {
                    if swapKeys {
                        bottomSpaceButton(disabled: editingBlocked)
                            .frame(width: widths.side)
                        bottomReturnButton(disabled: editingBlocked)
                            .frame(width: widths.center)
                        bottomDeleteButton(disabled: editingBlocked)
                            .frame(width: widths.side)
                    } else {
                        bottomDeleteButton(disabled: editingBlocked)
                            .frame(width: widths.side)
                        bottomReturnButton(disabled: editingBlocked)
                            .frame(width: widths.center)
                        bottomSpaceButton(disabled: editingBlocked)
                            .frame(width: widths.side)
                    }
                }
            }
            .frame(height: KeyboardLayoutMetrics.bottomActionRowHeight)
            .opacity(dragging ? 0 : 1)
        }
        .padding(.horizontal, KeyboardLayoutMetrics.sideActionHorizontalInset)
        .frame(maxWidth: .infinity)
    }

    private func cursorDragPad(enabled: Bool) -> some View {
        CursorDragPad(
            enabled: enabled,
            onPressingChanged: state.setCursorDragActive,
            moveHorizontal: state.moveCursorHorizontal,
            moveVertical: state.moveCursorVertical
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
    }

    private func bottomDeleteButton(disabled: Bool) -> some View {
        RepeatingDeleteButton(
            disabled: disabled,
            hapticIntensity: state.keyboardHapticIntensity
        ) {
            state.deleteBackward()
        }
        .frame(height: KeyboardLayoutMetrics.bottomActionRowHeight)
    }

    private func bottomSpaceButton(disabled: Bool) -> some View {
        RectangularToolbarButton(
            spaceStyle: true,
            label: "space",
            disabled: disabled,
            hapticIntensity: state.keyboardHapticIntensity
        ) {
            state.insertSpace()
        }
        .frame(height: KeyboardLayoutMetrics.bottomActionRowHeight)
    }

    private func bottomReturnButton(disabled: Bool) -> some View {
        let title = ExtL10n.string(state.returnKeyRole.titleKey)
        return RectangularToolbarButton(
            title: title,
            label: title,
            disabled: disabled,
            isSend: state.returnKeyRole == .send,
            hapticIntensity: state.keyboardHapticIntensity
        ) {
            state.insertNewline()
        }
        .frame(height: KeyboardLayoutMetrics.bottomActionRowHeight)
    }

    /// Option C: block typing keys during the full voice-input pipeline.
    private var voiceInputBlocksEditing: Bool {
        switch state.phase {
        case .requestingPermissions, .recording, .processing:
            return true
        case .idle, .error, .denied:
            return false
        }
    }

    private var buttonPhase: RecordButton.Phase {
        switch state.micVoiceAvailability {
        case .recording:
            return .recording
        case .processing:
            return .processing
        case .ready, .unavailable:
            // Host/PiP readiness is handled by an automatic app handoff. Keep
            // the idle mic visually green instead of exposing startup state.
            return .idleReady
        }
    }
}

// MARK: - State alias

extension KeyboardRootView {
    typealias State = KeyboardViewController.State
}

// MARK: - SwiftUI Preview

#if DEBUG
#Preview("Keyboard · Idle") {
    KeyboardRootView(
        state: KeyboardViewController.State.previewIdle,
        typing: TypingSessionController()
    )
        .frame(width: 390, height: KeyboardRootView.totalHeight)
        .preferredColorScheme(.dark)
}

#Preview("Keyboard · Recording") {
    KeyboardRootView(
        state: KeyboardViewController.State.previewRecording,
        typing: TypingSessionController()
    )
        .frame(width: 390, height: KeyboardRootView.totalHeight)
        .preferredColorScheme(.dark)
}

#Preview("Keyboard · Processing") {
    KeyboardRootView(
        state: KeyboardViewController.State.previewProcessing,
        typing: TypingSessionController()
    )
        .frame(width: 390, height: KeyboardRootView.totalHeight)
        .preferredColorScheme(.dark)
}
#endif

// MARK: - Transcript line

private struct TranscriptLine: View {
    @Environment(\.themePalette) private var palette: ThemePalette

    let phase: KeyboardViewController.State.Phase
    let transcript: String
    let micVoiceAvailability: MicVoiceAvailability
    let micDisabledHint: String
    let cursorDragHintActive: Bool
    let openSettings: () -> Void

    var body: some View {
        ZStack {
            // While dragging the caret, the whole mic cluster + transcript
            // line give way to the cursor-drag overlay, so hide this line's
            // "点按说话" / status text entirely.
            if !cursorDragHintActive {
                phaseContent
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Spacing.md)
    }

    @ViewBuilder
    private var phaseContent: some View {
        switch phase {
        case .idle:
            idleHint
        case .requestingPermissions:
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini).tint(palette.textSecondary)
                ExtL10n.text("keyboard.placeholder.preparing")
                    .font(TypeStyle.caption)
                    .foregroundStyle(palette.textSecondary)
            }
        case .recording:
            Text(transcript.isEmpty ? " " : transcript)
                .font(TypeStyle.caption)
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1)
                .truncationMode(.head)
                .frame(maxWidth: .infinity)
        case .processing:
            Text(transcript.isEmpty ? ExtL10n.string("keyboard.placeholder.processing") : transcript)
                .font(TypeStyle.caption)
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
        case .error(_, let msg):
            Text(msg ?? "")
                .font(TypeStyle.caption)
                .foregroundStyle(palette.warning)
                .lineLimit(1)
                .truncationMode(.tail)
        case .denied(let reason):
            Button(action: openSettings) {
                HStack(spacing: 4) {
                    Text(deniedMessage(for: reason))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                }
                .font(TypeStyle.caption)
                .foregroundStyle(palette.warning)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(ExtL10n.text("keyboard.deniedHint"))
        }
    }

    @ViewBuilder
    private var idleHint: some View {
        let isWarning: Bool = {
            switch micVoiceAvailability {
            case .unavailable(.hostNotReady), .unavailable(.preparingSession):
                return false
            case .unavailable:
                return true
            case .ready, .recording, .processing:
                return false
            }
        }()
        Group {
            switch micVoiceAvailability {
            case .ready:
                ExtL10n.text("keyboard.placeholder.idle")
            case .unavailable(.missingAPIKey):
                Text(micDisabledHint)
            case .unavailable(.hostNotReady):
                ExtL10n.text("keyboard.placeholder.idle")
            case .unavailable(.preparingSession):
                ExtL10n.text("keyboard.placeholder.idle")
            case .unavailable(.noFullAccess):
                ExtL10n.text("keyboard.error.fullAccessRequired")
            case .unavailable(.appGroupUnavailable):
                ExtL10n.text("keyboard.error.appGroupCommunication")
            case .unavailable(.onboardingIncomplete):
                ExtL10n.text("keyboard.hint.finishSetupInApp")
            case .recording, .processing:
                EmptyView()
            }
        }
        .font(TypeStyle.caption)
        .foregroundStyle(isWarning ? palette.warning : palette.textTertiary)
        .lineLimit(1)
        .truncationMode(.tail)
    }

    private func deniedMessage(for reason: KeyboardViewController.State.Phase.Reason) -> String {
        switch reason {
        case .mic:    return ExtL10n.string("keyboard.denied.mic")
        case .speech: return ExtL10n.string("keyboard.denied.speech")
        }
    }
}

// MARK: - Cloud engine chip (cloud always ASR + LLM polish)

private struct CloudEngineChip: View {
    @Environment(\.themePalette) private var palette: ThemePalette

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "wand.and.stars")
            ExtL10n.text("keyboard.placeholder.cloudBadge")
        }
        .font(TypeStyle.caption2)
        .foregroundStyle(palette.accent)
        .padding(.horizontal, Spacing.xs + 2)
        .padding(.vertical, 6)
        .frame(minHeight: 28)
        .background(palette.accent.opacity(0.15), in: Capsule())
        .overlay(Capsule().stroke(palette.accent.opacity(0.35), lineWidth: 0.5))
    }
}

// MARK: - Local engine chip (shown instead of ModeChip when engineMode == "local")

private struct LocalEngineChip: View {
    @Environment(\.themePalette) private var palette: ThemePalette

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "iphone.badge.checkmark")
            ExtL10n.text("keyboard.placeholder.localBadge")
        }
        .font(TypeStyle.caption2)
        .foregroundStyle(palette.accent)
        .padding(.horizontal, Spacing.xs + 2)
        .padding(.vertical, 6)
        .frame(minHeight: 28)
        .background(palette.accent.opacity(0.15), in: Capsule())
        .overlay(Capsule().stroke(palette.accent.opacity(0.35), lineWidth: 0.5))
    }
}

// MARK: - Locale chip

private struct LocaleChip: View {
    @Environment(\.themePalette) private var palette: ThemePalette

    let localeId: String
    let onChange: (String) -> Void

    private let options: [(id: String, labelKey: String)] = [
        ("auto",    "locale.chip.auto"),
        ("zh-Hans", "locale.chip.zh-Hans"),
        ("zh-Hant", "locale.chip.zh-Hant"),
        ("en-US",   "locale.chip.en-US"),
        ("ja-JP",   "locale.chip.ja-JP"),
        ("ko-KR",   "locale.chip.ko-KR")
    ]

    var body: some View {
        Menu {
            ForEach(options, id: \.id) { o in
                Button {
                    onChange(o.id)
                } label: {
                    if o.id == localeId {
                        Label(ExtL10n.string(o.labelKey), systemImage: "checkmark")
                    } else {
                        Text(ExtL10n.string(o.labelKey))
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "globe")
                Text(currentLabel)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
            }
            .font(TypeStyle.caption2)
            .foregroundStyle(palette.textPrimary)
            .padding(.horizontal, Spacing.xs + 2)
            .padding(.vertical, 6)
            .frame(minHeight: 28)
            .background(palette.surfaceElevated, in: Capsule())
            .overlay(Capsule().stroke(palette.divider, lineWidth: 0.5))
        }
        .menuStyle(.button)
    }

    private var currentLabel: String {
        options.first(where: { $0.id == localeId }).map { ExtL10n.string($0.labelKey) }
            ?? ExtL10n.string("locale.chip.auto")
    }
}
