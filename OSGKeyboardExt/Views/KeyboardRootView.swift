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
    static let sideActionButtonSize: CGFloat = 44
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
    private static let sideActionStackSpacing: CGFloat = 10

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
        // Let the system UI chrome show through by drawing no background
        // of our own.
        .background(Color.clear)
        .frame(height: Self.totalHeight)
        // Feed the resolved palette to all nested chips/buttons.
        .environment(\.themePalette, palette)
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: Spacing.xs) {
            if state.isLocalEngine {
                // Local engine: always transcribe, no mode menu needed.
                LocalEngineChip()
            } else {
                ModeChip(mode: state.mode) { newMode in
                    state.setMode(newMode)
                }
            }
            LocaleChip(localeId: state.localeId) { newId in
                state.setLocale(newId)
            }
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
                openSettings: state.openSettings
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
        HStack(alignment: .center, spacing: 20) {
            CircularToolbarButton(systemName: "delete.left", label: "delete") {
                state.deleteBackward()
            }

            RecordButton(
                phase: buttonPhase,
                level: state.level,
                remainingSeconds: state.phase == .recording ? state.utteranceRemainingSeconds : nil,
                onToggle: state.tapMic
            )
            .frame(width: 132, height: 132)

            VStack(spacing: Self.sideActionStackSpacing) {
                CircularToolbarButton(systemName: "return", label: "newline") {
                    state.insertNewline()
                }
                CircularToolbarButton(spaceStyle: true, label: "space") {
                    state.insertSpace()
                }
            }
        }
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
    let openSettings: () -> Void

    var body: some View {
        ZStack {
            switch phase {
            case .idle:
                if flowSessionActive {
                    ExtL10n.text("keyboard.placeholder.idle")
                        .font(TypeStyle.caption)
                        .foregroundStyle(palette.textTertiary)
                } else {
                    ExtL10n.text("keyboard.flow.sessionInactive")
                        .font(TypeStyle.caption)
                        .foregroundStyle(palette.textTertiary)
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
                        .frame(width: 16, height: 3)
                } else if let systemName {
                    Image(systemName: systemName)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(palette.textPrimary)
                }
            }
            .frame(width: KeyboardLayoutMetrics.sideActionButtonSize, height: KeyboardLayoutMetrics.sideActionButtonSize)
            .background(palette.surfaceElevated, in: Circle())
            .overlay(Circle().stroke(palette.divider, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
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

// MARK: - Mode chip

private struct ModeChip: View {
    @Environment(\.themePalette) private var palette: ThemePalette

    let mode: KeyboardViewController.State.InputMode
    let onChange: (KeyboardViewController.State.InputMode) -> Void

    var body: some View {
        Menu {
            ForEach(KeyboardViewController.State.InputMode.allCases) { m in
                Button {
                    onChange(m)
                } label: {
                    if m == mode {
                        Label(label(for: m), systemImage: "checkmark")
                    } else {
                        Text(label(for: m))
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon(for: mode))
                Text(label(for: mode))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
            }
            .font(TypeStyle.caption2)
            .foregroundStyle(mode == .off ? palette.textTertiary : palette.textPrimary)
            .padding(.horizontal, Spacing.xs + 2)
            .padding(.vertical, 5)
            .frame(minHeight: 26)
            .background(palette.surfaceElevated, in: Capsule())
            .overlay(Capsule().stroke(palette.divider, lineWidth: 0.5))
        }
        .menuStyle(.button)
    }

    private func label(for m: KeyboardViewController.State.InputMode) -> String {
        ExtL10n.string(m.labelKey)
    }

    private func icon(for m: KeyboardViewController.State.InputMode) -> String {
        switch m {
        case .off:        return "mic.slash.fill"
        case .transcribe: return "text.bubble.fill"
        case .polish:     return "wand.and.stars"
        }
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
