// KeyboardRootView.swift
// OSGKeyboard · Keyboard Extension
//
// Typeless-inspired keyboard surface. The keyboard is laid out in three
// vertical bands, but the entire height is reserved for us — we set
// `inputView.allowsSelfSizing = true` in the view controller so SwiftUI's
// frame is honoured, and we add safe-area insets at the top and bottom so
// the system Spotlight / home-indicator chrome never clips our controls.
//
//   ┌───────────────────────────────────────────┐
//   │  [polish] [中]                 ●   ⚙     │  ← top: ~38 pt (+20%)
//   │              (transcript preview)         │
//   │                                           │
//   │        (⌫)      ◯ mic      (↩)          │  ← action row: circular
//   │                           (space)        │     flanking buttons
//   └───────────────────────────────────────────┘

import SwiftUI
import OSGKeyboardShared

private enum KeyboardLayoutMetrics {
    static let sideActionButtonSize: CGFloat = 53
    static let sideActionIconSize: CGFloat = 19
    static let sideSpaceBarWidth: CGFloat = 19
    static let micFlankMinSpacing: CGFloat = 36
    static let sideActionStackSpacing: CGFloat = 16
    /// Outer inset for delete / return·space from screen edges (8 pt → 24 pt, +200%).
    static let sideActionHorizontalInset: CGFloat = Spacing.xs * 3
}

public struct KeyboardRootView: View {
    @Environment(\.colorScheme) private var colorScheme

    @ObservedObject var state: State

    public init(state: KeyboardViewController.State) {
        self.state = state
    }

    /// Total keyboard height. We set the same value as a height-anchor
    /// constraint in the view controller so the host UIInputView picks
    /// it up.
    static let totalHeight: CGFloat = 280
    private static let topBarHeight: CGFloat = 38

    private var palette: ThemePalette {
        colorScheme == .dark ? Palette.dark : Palette.light
    }

    public var body: some View {
        VStack(spacing: 0) {
            topBar
                .frame(height: Self.topBarHeight)

            centreArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.top, 4)
        .padding(.bottom, 6)
        // 透明背景：让系统键盘 chrome 透出，不自行铺色（深浅模式一致）。
        .background(Color.clear)
        .frame(height: Self.totalHeight)
        // Feed the resolved palette to all nested chips/buttons.
        .environment(\.themePalette, palette)
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: Spacing.xs) {
            if state.isLocalEngine {
                LocalEngineChip()
            } else {
                CloudEngineChip()
            }
            LocaleChip(localeId: state.localeId) { newId in
                state.setLocale(newId)
            }
            // v0.2.1: translation chip — sits next to the locale picker
            // and doubles as both the on/off switch and the target-
            // language picker (Menu pattern matches LocaleChip so the
            // top bar stays visually consistent).
            TranslationChip(state: state)
            Spacer(minLength: 0)
            StatusBadge(phase: state.phase, onDeviceSupported: state.onDeviceSupported)
            Button(action: state.openSettings) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(palette.textSecondary)
                    .frame(width: 34, height: 34)
                    .background(palette.surface, in: Circle())
                    .overlay(Circle().stroke(palette.divider, lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(ExtL10n.text("keyboard.openSettingsA11y"))
        }
        .padding(.horizontal, Spacing.md)
    }

    // MARK: - Centre area

    private var centreArea: some View {
        VStack(spacing: Spacing.xxs) {
            TranscriptLine(
                phase: state.phase,
                transcript: state.lastTranscript,
                flowSessionActive: state.flowSessionActive,
                isLocalEngine: state.isLocalEngine,
                localModelsReady: state.localModelsReady,
                localModelsLoaded: state.localModelsLoaded,
                openSettings: state.openSettings,
                startFlowSession: state.startFlowSession
            )
            .frame(height: 22)

            Spacer(minLength: 0)

            micActionRow
                .padding(.bottom, Spacing.xs)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }

    /// Delete (left), mic (centre), return + space stacked on the right.
    /// HStack vertical alignment keeps delete, mic centre, and the gap
    /// between return/space on one horizontal axis.
    private var micActionRow: some View {
        HStack(alignment: .center, spacing: 0) {
            CircularToolbarButton(systemName: "delete.left", label: "delete") {
                state.deleteBackward()
            }

            Spacer(minLength: KeyboardLayoutMetrics.micFlankMinSpacing)

            RecordButton(
                phase: buttonPhase,
                level: state.level,
                remainingSeconds: state.phase == .recording ? state.utteranceRemainingSeconds : nil,
                onToggle: state.tapMic
            )
            .frame(width: 132, height: 132)

            Spacer(minLength: KeyboardLayoutMetrics.micFlankMinSpacing)

            VStack(spacing: KeyboardLayoutMetrics.sideActionStackSpacing) {
                CircularToolbarButton(systemName: "return", label: "newline") {
                    state.insertNewline()
                }
                CircularToolbarButton(spaceStyle: true, label: "space") {
                    state.insertSpace()
                }
            }
        }
        .padding(.horizontal, KeyboardLayoutMetrics.sideActionHorizontalInset)
        .frame(maxWidth: .infinity)
    }

    private var buttonPhase: RecordButton.Phase {
        switch state.phase {
        case .idle:                       return .idle
        case .requestingPermissions:      return .idle
        case .recording:                  return .recording
        case .processing:                 return .processing
        case .error:                      return .error
        case .denied:                     return .error
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
    KeyboardRootView(state: KeyboardViewController.State.previewIdle)
        .frame(width: 390, height: 280)
        .preferredColorScheme(.dark)
}

#Preview("Keyboard · Recording") {
    KeyboardRootView(state: KeyboardViewController.State.previewRecording)
        .frame(width: 390, height: 280)
        .preferredColorScheme(.dark)
}

#Preview("Keyboard · Processing") {
    KeyboardRootView(state: KeyboardViewController.State.previewProcessing)
        .frame(width: 390, height: 280)
        .preferredColorScheme(.dark)
}
#endif

// MARK: - Transcript line

private struct TranscriptLine: View {
    @Environment(\.themePalette) private var palette: ThemePalette

    let phase: KeyboardViewController.State.Phase
    let transcript: String
    let flowSessionActive: Bool
    let isLocalEngine: Bool
    let localModelsReady: Bool
    let localModelsLoaded: Bool
    let openSettings: () -> Void
    let startFlowSession: () -> Void

    var body: some View {
        ZStack {
            switch phase {
            case .idle:
                if isLocalEngine, !localModelsReady {
                    Button(action: openSettings) {
                        HStack(spacing: 4) {
                            Text(ExtL10n.string("keyboard.models.notDownloaded"))
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .font(TypeStyle.caption)
                        .foregroundStyle(palette.warning)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(ExtL10n.text("keyboard.models.downloadHint"))
                } else if isLocalEngine, localModelsReady, !localModelsLoaded {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.mini).tint(palette.textSecondary)
                        ExtL10n.text("keyboard.models.warming")
                            .font(TypeStyle.caption)
                            .foregroundStyle(palette.textSecondary)
                    }
                } else if flowSessionActive {
                    ExtL10n.text("keyboard.placeholder.idle")
                        .font(TypeStyle.caption)
                        .foregroundStyle(palette.textTertiary)
                } else {
                    HStack(spacing: 6) {
                        ExtL10n.text("keyboard.flow.sessionInactive")
                            .font(TypeStyle.caption)
                            .foregroundStyle(palette.textTertiary)
                        Button(action: startFlowSession) {
                            ExtL10n.text("keyboard.flow.start")
                                .font(TypeStyle.caption)
                                .foregroundStyle(palette.accent)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint(ExtL10n.text("keyboard.flow.startA11y"))
                    }
                }
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
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini).tint(palette.accent)
                    Text(transcript.isEmpty ? ExtL10n.string("keyboard.placeholder.processing") : transcript)
                        .font(TypeStyle.caption)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
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
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Spacing.md)
    }

    private func deniedMessage(for reason: KeyboardViewController.State.Phase.Reason) -> String {
        switch reason {
        case .mic:    return ExtL10n.string("keyboard.denied.mic")
        case .speech: return ExtL10n.string("keyboard.denied.speech")
        }
    }
}

// MARK: - Circular toolbar button

private struct CircularToolbarButton: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.themePalette) private var palette: ThemePalette

    let systemName: String?
    let spaceStyle: Bool
    let label: String
    let action: () -> Void

    init(systemName: String, label: String, action: @escaping () -> Void) {
        self.systemName = systemName
        self.spaceStyle = false
        self.label = label
        self.action = action
    }

    init(spaceStyle: Bool, label: String, action: @escaping () -> Void) {
        self.systemName = nil
        self.spaceStyle = spaceStyle
        self.label = label
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Group {
                if spaceStyle {
                    Capsule()
                        .fill(palette.textPrimary)
                        .frame(width: KeyboardLayoutMetrics.sideSpaceBarWidth, height: 3)
                } else if let systemName {
                    Image(systemName: systemName)
                        .font(.system(size: KeyboardLayoutMetrics.sideActionIconSize, weight: .medium))
                        .foregroundStyle(palette.textPrimary)
                }
            }
            .frame(width: KeyboardLayoutMetrics.sideActionButtonSize, height: KeyboardLayoutMetrics.sideActionButtonSize)
            .background(sideButtonFill, in: Circle())
            .overlay(Circle().stroke(palette.dividerStrong, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }

    private var sideButtonFill: Color {
        colorScheme == .dark
            ? Color(red: 0.20, green: 0.20, blue: 0.22)
            : palette.surfaceElevated
    }
}

// MARK: - Status badge

private struct StatusBadge: View {
    @Environment(\.themePalette) private var palette: ThemePalette

    let phase: KeyboardViewController.State.Phase
    /// Reflects whether the active ASR session is on-device. We surface
    /// a small ⚠️ during recording so the user knows their audio is
    /// going to the cloud for this locale (and so devs catch it during
    /// QA without staring at the Xcode console).
    let onDeviceSupported: Bool

    var body: some View {
        Group {
            switch phase {
            case .idle:
                EmptyView()
            case .requestingPermissions:
                EmptyView()
            case .recording:
                if onDeviceSupported {
                    dot(color: palette.recordRed, labelKey: "keyboard.status.rec")
                } else {
                    dot(color: palette.warning, labelKey: "keyboard.status.recWarning", showWarning: true)
                }
            case .processing:
                dot(color: palette.accent, labelKey: "keyboard.status.processing")
            case .error:
                dot(color: palette.warning, labelKey: "keyboard.status.error")
            case .denied:
                dot(color: palette.warning, labelKey: "keyboard.status.error")
            }
        }
    }

    private func dot(color: Color, labelKey: String, showWarning: Bool = false) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            if showWarning {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(palette.warning)
            }
            Text(ExtL10n.string(labelKey))
                .font(TypeStyle.caption2)
                .foregroundStyle(palette.textSecondary)
        }
        .padding(.horizontal, Spacing.xs)
        .padding(.vertical, 3)
        .background(palette.surface, in: Capsule())
        .overlay(Capsule().stroke(palette.divider, lineWidth: 0.5))
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
        .padding(.vertical, 5)
        .frame(minHeight: 26)
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
        .padding(.vertical, 5)
        .frame(minHeight: 26)
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
            .padding(.vertical, 5)
            .frame(minHeight: 26)
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
