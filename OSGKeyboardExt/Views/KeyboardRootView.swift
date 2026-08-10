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
//   │  ⟲           ◯ mic (centred)              │  ← action cluster:
//   │   [delete]  [ return ]  [space]           │     mic + undo + bottom row
//   │              ┊                          │
//   └───────────────────────────────────────────┘

import SwiftUI
import OSGKeyboardShared

private enum KeyboardLayoutMetrics {
    static let micSize: CGFloat = 121
    static let micToButtonGap: CGFloat = 8
    /// Square undo key beside the mic (outer edge, aligned with delete).
    static let undoButtonSize: CGFloat = 44
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
    /// The typing surface deliberately does not share this cap.
    static let contentMaxWidth: CGFloat = KeyboardChromeLayout.voiceContentMaxWidth

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

    /// `RecordButton` draws its outer ring at 106 pt inside the 121 pt touch
    /// frame, so the disc's *visible* top edge sits below the frame's top.
    static let micRingInset: CGFloat = (micSize - 106) / 2
    /// 语音/中文/EN capsule: 30 pt buttons + 2 pt padding, centred in the top bar.
    static let topBarTabCapsuleHeight: CGFloat = 34
    /// Pushes the transcript / hint line down to the vertical centre of the gap
    /// between the tab capsule's bottom edge and the mic's visible top edge.
    /// Applied as an offset so the band heights — and therefore `totalHeight`
    /// and `micUpwardAdjustment` — stay untouched. `extraSpace` is the slack a
    /// taller iPad keyboard adds above the action cluster, which moves the mic
    /// down and so must move this line with it.
    static func transcriptLineDownwardAdjustment(extraSpace: CGFloat) -> CGFloat {
        let capsuleBottom = (topBarHeight + topBarTabCapsuleHeight) / 2
        let micVisibleTop = topBarHeight
            + topBarToTranscriptSpacing
            + transcriptLineHeight
            + actionClusterTopGap
            + extraSpace
            - micUpwardAdjustment
            + micRingInset
        let currentCentre = topBarHeight + topBarToTranscriptSpacing + transcriptLineHeight / 2
        return (capsuleBottom + micVisibleTop) / 2 - currentCentre
    }

    static var headerBandHeight: CGFloat {
        topBarHeight + topBarToTranscriptSpacing + transcriptLineHeight
    }

    /// 4 + 70 + 24 + 179 + 0 + 4 = 281 pt on phones.
    static let totalHeight: CGFloat = KeyboardChromeLayout.totalHeight

    /// Voice and typing must resolve to the same height or switching surfaces
    /// visibly resizes the keyboard — 113 pt on an iPad in landscape. The
    /// typing surface is content-driven, so voice adopts its height and parks
    /// the surplus above the action cluster (keeping the bottom row on the
    /// same baseline as the typing bottom row).
    static func totalHeight(isIPad: Bool, width: CGFloat) -> CGFloat {
        TypingSurfaceMetrics.contentHeight(isIPad: isIPad, width: width)
    }

    static func extraVerticalSpace(isIPad: Bool, width: CGFloat) -> CGFloat {
        max(0, totalHeight(isIPad: isIPad, width: width) - totalHeight)
    }
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

    /// Matches the typing surface so switching surfaces never resizes the
    /// keyboard. Surplus height is parked above the action cluster.
    static func totalHeight(isIPad: Bool, width: CGFloat) -> CGFloat {
        KeyboardLayoutMetrics.totalHeight(isIPad: isIPad, width: width)
    }

    // MARK: - Cursor-drag pad geometry

    /// Mic disc side length.
    static let micSize: CGFloat = KeyboardLayoutMetrics.micSize
    /// Vertical offset from the keyboard's top edge to the mic disc. iPad adds
    /// `KeyboardLayoutMetrics.extraVerticalSpace` on top of this.
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
        Group {
            if state.editSession.isActive {
                LastInputEditView(state: state)
            } else {
                ZStack {
                    VStack(spacing: 0) {
                        headerBand

                        Color.clear
                            .frame(height: KeyboardLayoutMetrics.actionClusterTopGap)

                        // Absorbs the surplus of a taller iPad keyboard here so
                        // the action cluster stays pinned to the bottom and its
                        // keys share the typing surface's bottom-row baseline.
                        Spacer(minLength: 0)

                        micActionRow
                            .frame(height: KeyboardLayoutMetrics.actionClusterHeight)

                        Color.clear
                            .frame(height: KeyboardLayoutMetrics.actionClusterBottomGap)
                    }
                    .padding(.top, KeyboardLayoutMetrics.outerPaddingTop)
                    .padding(.bottom, KeyboardLayoutMetrics.outerPaddingBottom)
                    // 透明背景：让系统键盘 chrome 透出，不自行铺色（深浅模式一致）。
                    .background(Color.clear)
                    // No content-width cap: the surface fills the host width so
                    // switching between voice and typing never changes width.
                    .frame(maxWidth: .infinity)
                    .frame(
                        height: Self.totalHeight(
                            isIPad: state.usesIPadLayoutMetrics,
                            width: state.layoutWidth
                        )
                    )
                    // Feed the resolved palette to all nested chips/buttons.
                    .environment(\.themePalette, palette)
                }
            }
        }
        .animation(.easeInOut(duration: 0.12), value: state.cursorDragActive)
        .animation(.easeInOut(duration: 0.12), value: state.editSession.isActive)
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
                editHint: state.editHint,
                editHintIsPositive: state.editHintIsPositive,
                cursorDragHintActive: state.cursorDragActive,
                openSettings: state.openSettings
            )
            .frame(height: KeyboardLayoutMetrics.transcriptLineHeight)
            .offset(y: KeyboardLayoutMetrics.transcriptLineDownwardAdjustment(
                extraSpace: KeyboardLayoutMetrics.extraVerticalSpace(
                    isIPad: state.usesIPadLayoutMetrics,
                    width: state.layoutWidth
                )
            ))
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: Spacing.xs) {
            KeyboardBrandLogo(action: state.openSettings)
            // Globe key now lives at the bottom-left of the keyboard (matching
            // iOS system layout); see micActionRow's bottom HStack.
            // Engine controls remain available in the host app.
            // App context is auto-detected on each mic press — no UI.
            Spacer(minLength: 0)
            if state.canCancelVoiceInput {
                KeyboardCancelButton(
                    action: state.cancelVoiceInput,
                    accessibilityLabel: ExtL10n.text("keyboard.voice.cancel"),
                    accessibilityHint: ExtL10n.text("keyboard.voice.cancelHint")
                )
            } else {
                KeyboardTopControls(
                    state: state,
                    typing: typing,
                    palette: palette,
                    onInsert: onInsert
                )
            }
        }
        .padding(.horizontal, KeyboardTopBarMetrics.horizontalInset)
    }

    // MARK: - Action cluster

    /// Mic centred above a bottom row: delete · smart return · space (or swapped).
    /// The side cursor-drag pads are SwiftUI layout wrappers around UIKit
    /// pan recognizers, avoiding SwiftUI gesture delivery issues in
    /// keyboard extensions. A square undo key sits on the outer pad,
    /// vertically centred with the mic and mirrored with handedness.
    private var micActionRow: some View {
        let editingBlocked = voiceInputBlocksEditing
        let swapKeys = state.handednessPreference.swapsActionKeys
        let cursorPadsEnabled = state.cursorDragNavigationEnabled && !editingBlocked

        // Dragging hides the mic + bottom keys (kept in the layout via
        // opacity so the pads' hit area never shifts mid-gesture) and lets
        // the cursor-drag chrome take over.
        let dragging = state.cursorDragActive
        let recording = state.phase == .recording
        let undoVisible = !dragging && !recording

        return VStack(spacing: KeyboardLayoutMetrics.micToButtonGap) {
            HStack(spacing: 0) {
                cursorDragPad(enabled: cursorPadsEnabled)
                    .overlay(alignment: .leading) {
                        // Left-handed: undo shares the outer edge with delete.
                        if !swapKeys {
                            undoButton(
                                disabled: editingBlocked || !state.undoAvailable,
                                visible: undoVisible
                            )
                        }
                    }

                RecordButton(
                    phase: buttonPhase,
                    level: state.level,
                    remainingSeconds: state.phase == .recording ? state.utteranceRemainingSeconds : nil,
                    isEnabled: micButtonEnabled,
                    onToggle: state.tapMic,
                    onPressingChanged: micButtonEnabled
                        ? state.setMicTouchActive
                        : { _ in },
                    onEditLongPressBegan: micButtonEnabled
                        ? state.beginEditLastInput
                        : nil
                )
                .frame(width: KeyboardLayoutMetrics.micSize, height: KeyboardLayoutMetrics.micSize)
                .offset(y: -KeyboardLayoutMetrics.micUpwardAdjustment)
                .opacity(dragging ? 0 : 1)

                cursorDragPad(enabled: cursorPadsEnabled)
                    .overlay(alignment: .trailing) {
                        // Right-handed: undo mirrors to the outer (delete) side.
                        if swapKeys {
                            undoButton(
                                disabled: editingBlocked || !state.undoAvailable,
                                visible: undoVisible
                            )
                        }
                    }
            }
            .frame(height: KeyboardLayoutMetrics.micSize)

            GeometryReader { proxy in
                if state.showsSystemGlobeKey {
                    // iPad uses a flatter split: at full width the phone's 50%
                    // centre fraction would hand return ~577 pt.
                    let widths = state.usesIPadLayoutMetrics
                        ? KeyboardChromeLayout.iPadVoiceActionKeyWidths(
                            availableWidth: proxy.size.width
                        )
                        : KeyboardChromeLayout.actionKeyWidths(
                            availableWidth: proxy.size.width
                        )

                    HStack(spacing: KeyboardLayoutMetrics.bottomActionSpacing) {
                        // Globe key pins to the far-left of the iPad action row.
                        // Tap advances; long-press presents the system list.
                        SystemGlobeKey(
                            state: state,
                            width: widths.globe,
                            height: KeyboardLayoutMetrics.bottomActionRowHeight
                        )
                        .frame(
                            width: widths.globe,
                            height: KeyboardLayoutMetrics.bottomActionRowHeight
                        )
                        if swapKeys {
                            bottomSpaceButton(disabled: editingBlocked)
                                .frame(width: widths.side)
                            bottomReturnButton(disabled: editingBlocked)
                                .frame(width: widths.center)
                            bottomDeleteButton(disabled: editingBlocked)
                                .frame(width: widths.side2)
                        } else {
                            bottomDeleteButton(disabled: editingBlocked)
                                .frame(width: widths.side)
                            bottomReturnButton(disabled: editingBlocked)
                                .frame(width: widths.center)
                            bottomSpaceButton(disabled: editingBlocked)
                                .frame(width: widths.side2)
                        }
                    }
                } else {
                    let widths = KeyboardChromeLayout.actionKeyWidthsWithoutGlobe(
                        availableWidth: proxy.size.width
                    )

                    HStack(spacing: KeyboardLayoutMetrics.bottomActionSpacing) {
                        if swapKeys {
                            bottomSpaceButton(disabled: editingBlocked)
                                .frame(width: widths.side)
                            bottomReturnButton(disabled: editingBlocked)
                                .frame(width: widths.center)
                            bottomDeleteButton(disabled: editingBlocked)
                                .frame(width: widths.side2)
                        } else {
                            bottomDeleteButton(disabled: editingBlocked)
                                .frame(width: widths.side)
                            bottomReturnButton(disabled: editingBlocked)
                                .frame(width: widths.center)
                            bottomSpaceButton(disabled: editingBlocked)
                                .frame(width: widths.side2)
                        }
                    }
                }
            }
            .frame(height: KeyboardLayoutMetrics.bottomActionRowHeight)
            .opacity(dragging || recording ? 0 : 1)
            .allowsHitTesting(!dragging && !recording)
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

    /// Square undo key on the outer drag pad — same chrome / haptic / click
    /// as space & return. Vertically matches the mic disc.
    private func undoButton(disabled: Bool, visible: Bool) -> some View {
        RectangularToolbarButton(
            systemName: "arrow.uturn.backward",
            label: ExtL10n.string("keyboard.undoA11y"),
            disabled: disabled,
            hapticIntensity: state.keyboardHapticIntensity
        ) {
            state.undoLastInsertion()
        }
        .frame(
            width: KeyboardLayoutMetrics.undoButtonSize,
            height: KeyboardLayoutMetrics.undoButtonSize
        )
        .offset(y: -KeyboardLayoutMetrics.micUpwardAdjustment)
        .opacity(visible ? 1 : 0)
        .allowsHitTesting(visible && !disabled)
        .accessibilityHidden(!visible)
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

    /// Disabled only when the shared voice prerequisites are unavailable.
    private var micButtonEnabled: Bool {
        if state.micDisabled { return false }
        return true
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
    let editHint: String?
    let editHintIsPositive: Bool
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
                Text(
                    transcript.isEmpty
                        ? ExtL10n.string("keyboard.placeholder.preparing")
                        : transcript
                )
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
        if let editHint, !editHint.isEmpty {
            Text(editHint)
                .font(TypeStyle.caption)
                .foregroundStyle(editHintIsPositive ? palette.accent : palette.warning)
                .lineLimit(1)
                .truncationMode(.tail)
        } else {
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
