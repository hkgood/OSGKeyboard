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
//   │  [polish] [中]                 ●   ⚙     │  ← top: 32 pt (incl. safe top)
//   │              (transcript preview)         │  ← 24 pt
//   │                                           │
//   │                  ◯  ▲▲▲▲▲                 │  ← centre: 96 pt disc +
//   │                                           │     breathing ring
//   │                                           │
//   ├───────────────────────────────────────────┤
//   │   🌐   ⌫   [      space      ]     ↩     │  ← bottom: 60 pt (incl. safe bottom)
//   └───────────────────────────────────────────┘

import SwiftUI
import OSGKeyboardShared

public struct KeyboardRootView: View {
    @Environment(\.themePalette) private var palette: ThemePalette

    @ObservedObject var state: State

    public init(state: KeyboardViewController.State) {
        self.state = state
    }

    /// Total keyboard height. We set the same value as a height-anchor
    /// constraint in the view controller so the host UIInputView picks
    /// it up.
    static let totalHeight: CGFloat = 280

    public var body: some View {
        VStack(spacing: 0) {
            topBar
                .frame(height: 32)

            centreArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            bottomBar
                .frame(height: 56)
        }
        .padding(.top, 4)
        .padding(.bottom, 6)
        // iOS keyboard extensions always render dark (Apple's default
        // for custom keyboards), and we let the system UI chrome show
        // through by drawing no background of our own.
        .background(Color.clear)
        .frame(height: Self.totalHeight)
        // Top edge: subtle highlight gradient + 0.5pt divider line.
        // These give the keyboard a "physical surface" feel and visually
        // separate it from the host text field above. We overlay (not
        // background) so the underlying color stays clear.
        .overlay(alignment: .top) {
            VStack(spacing: 0) {
                Rectangle()
                    .fill(LinearGradient(
                        colors: [Color.white.opacity(0.05), .clear],
                        startPoint: .top, endPoint: .bottom
                    ))
                    .frame(height: 1)
                Spacer(minLength: 0)
            }
        }
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
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(palette.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(palette.surface, in: Circle())
                    .overlay(Circle().stroke(palette.divider, lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("打开设置 · Open OSGKeyboard settings"))
        }
        .padding(.horizontal, Spacing.md)
    }

    // MARK: - Centre area

    private var centreArea: some View {
        ZStack {
            VStack(spacing: Spacing.xxs) {
                TranscriptLine(
                    phase: state.phase,
                    transcript: state.lastTranscript,
                    openSettings: state.openSettings
                )
                    .frame(height: 22)
                RecordButton(
                    phase: buttonPhase,
                    level: state.level,
                    onPressBegan: state.beginRecording,
                    onPressEnded:  state.endRecording,
                    onTap:         state.tapMic
                )
                .frame(width: 140, height: 140)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        HStack(spacing: Spacing.xxs) {
            ToolbarIconButton(systemName: "globe", label: "nextKeyboard") {
                state.tapMic()
            }
            ToolbarIconButton(systemName: "delete.left", label: "delete") {
                state.deleteBackward()
            }
            Spacer(minLength: 0)
            Button(action: state.insertSpace) {
                Text("空格 · Space")
                    .font(TypeStyle.body)
                    .foregroundStyle(palette.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 42)
                    .background(palette.surfaceElevated, in: RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                            .stroke(palette.divider, lineWidth: 0.5)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("空格 · Space"))
            Spacer(minLength: 0)
            ToolbarIconButton(systemName: "return", label: "newline") {
                state.insertNewline()
            }
        }
        .padding(.horizontal, Spacing.sm)
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
    let openSettings: () -> Void

    var body: some View {
        ZStack {
            switch phase {
            case .idle:
                Text("按住说话 · Hold to talk")
                    .font(TypeStyle.caption)
                    .foregroundStyle(palette.textTertiary)
            case .requestingPermissions:
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini).tint(palette.textSecondary)
                    Text("准备中… · Preparing")
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
                    Text("处理中 · Processing")
                        .font(TypeStyle.caption)
                        .foregroundStyle(palette.textSecondary)
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
                .accessibilityHint(Text("打开 OSGKeyboard 设置,可授予麦克风 / 语音识别权限。Opens the OSGKeyboard settings page where you can grant microphone or speech recognition access."))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Spacing.md)
    }

    private func deniedMessage(for reason: KeyboardViewController.State.Phase.Reason) -> String {
        switch reason {
        case .mic:    return "麦克风被拒绝 · Mic denied"
        case .speech: return "语音识别被拒绝 · Speech denied"
        }
    }
}

// MARK: - Toolbar icon button

private struct ToolbarIconButton: View {
    @Environment(\.themePalette) private var palette: ThemePalette

    let systemName: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(palette.textPrimary)
                .frame(width: 40, height: 40)
                .background(palette.surfaceElevated, in: RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                        .stroke(palette.divider, lineWidth: 0.5)
                )
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
                    dot(color: palette.recordRed, label: "REC")
                } else {
                    dot(color: palette.warning, label: "REC ⚠️", showWarning: true)
                }
            case .processing:
                dot(color: palette.accent, label: "···")
            case .error:
                dot(color: palette.warning, label: "!")
            case .denied:
                dot(color: palette.warning, label: "!")
            }
        }
    }

    private func dot(color: Color, label: String, showWarning: Bool = false) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            if showWarning {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(palette.warning)
            }
            Text(label)
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
            Text("本地 · On-device")
        }
        .font(TypeStyle.caption2)
        .foregroundStyle(palette.accent)
        .padding(.horizontal, Spacing.xs + 2)
        .padding(.vertical, 4)
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
            .padding(.vertical, 4)
            .background(palette.surfaceElevated, in: Capsule())
            .overlay(Capsule().stroke(palette.divider, lineWidth: 0.5))
        }
        .menuStyle(.button)
    }

    private func label(for m: KeyboardViewController.State.InputMode) -> String {
        switch m {
        case .off:        return "Off"
        case .transcribe: return "转写"
        case .polish:     return "润色"
        }
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

    private let options: [(id: String, label: String)] = [
        ("auto",    "Auto"),
        ("zh-Hans", "简体"),
        ("zh-Hant", "繁體"),
        ("en-US",   "EN"),
        ("ja-JP",   "日"),
        ("ko-KR",   "한")
    ]

    var body: some View {
        Menu {
            ForEach(options, id: \.id) { o in
                Button {
                    onChange(o.id)
                } label: {
                    if o.id == localeId {
                        Label(o.label, systemImage: "checkmark")
                    } else {
                        Text(o.label)
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
            .padding(.vertical, 4)
            .background(palette.surfaceElevated, in: Capsule())
            .overlay(Capsule().stroke(palette.divider, lineWidth: 0.5))
        }
        .menuStyle(.button)
    }

    private var currentLabel: String {
        options.first(where: { $0.id == localeId })?.label ?? "Auto"
    }
}
