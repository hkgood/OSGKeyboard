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

    @ObservedObject var state: State

    public init(state: KeyboardViewController.State) {
        self.state = state
    }

    /// Total keyboard height. We set the same value as a height-anchor
    /// constraint in the view controller so the host UIInputView picks
    /// it up.
    static let totalHeight: CGFloat = 280

    public var body: some View {
        ZStack(alignment: .top) {
            background

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
        }
        .frame(height: Self.totalHeight)
        .preferredColorScheme(.dark)
    }

    // MARK: - Background

    /// Solid dark fill plus a hairline highlight at the top edge, so the
    /// keyboard reads as a physical surface rather than a floating card.
    private var background: some View {
        ZStack {
            Palette.background
            VStack(spacing: 0) {
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.05), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(height: 1)
                Spacer(minLength: 0)
            }
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Palette.divider)
                .frame(height: 0.5)
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: Spacing.xs) {
            ModeChip(mode: state.mode) { newMode in
                state.setMode(newMode)
            }
            LocaleChip(localeId: state.localeId) { newId in
                state.setLocale(newId)
            }
            Spacer(minLength: 0)
            StatusBadge(phase: state.phase)
            Button(action: state.openSettings) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Palette.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(Palette.surface, in: Circle())
                    .overlay(Circle().stroke(Palette.divider, lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Open OSGKeyboard settings"))
        }
        .padding(.horizontal, Spacing.md)
    }

    // MARK: - Centre area

    private var centreArea: some View {
        ZStack {
            VStack(spacing: Spacing.xxs) {
                TranscriptLine(phase: state.phase, transcript: state.lastTranscript)
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
                Text("空格")
                    .font(TypeStyle.body)
                    .foregroundStyle(Palette.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 42)
                    .background(Palette.surfaceElevated, in: RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                            .stroke(Palette.divider, lineWidth: 0.5)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Space"))
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
        case .recording:                  return .recording
        case .processing:                 return .processing
        case .error:                      return .error
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
    let phase: KeyboardViewController.State.Phase
    let transcript: String

    var body: some View {
        ZStack {
            switch phase {
            case .idle:
                Text("按住说话 · Hold to talk")
                    .font(TypeStyle.caption)
                    .foregroundStyle(Palette.textTertiary)
            case .recording:
                Text(transcript.isEmpty ? " " : transcript)
                    .font(TypeStyle.caption)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .frame(maxWidth: .infinity)
            case .processing:
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini).tint(Palette.accent)
                    Text("润色中 · Polishing")
                        .font(TypeStyle.caption)
                        .foregroundStyle(Palette.textSecondary)
                }
            case .error(let msg):
                Text(msg)
                    .font(TypeStyle.caption)
                    .foregroundStyle(Palette.warning)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Spacing.md)
    }
}

// MARK: - Toolbar icon button

private struct ToolbarIconButton: View {
    let systemName: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Palette.textPrimary)
                .frame(width: 40, height: 40)
                .background(Palette.surfaceElevated, in: RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                        .stroke(Palette.divider, lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }
}

// MARK: - Status badge

private struct StatusBadge: View {
    let phase: KeyboardViewController.State.Phase

    var body: some View {
        Group {
            switch phase {
            case .idle:
                EmptyView()
            case .recording:
                dot(color: Palette.recordRed, label: "REC")
            case .processing:
                dot(color: Palette.accent, label: "···")
            case .error:
                dot(color: Palette.warning, label: "!")
            }
        }
    }

    private func dot(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(label)
                .font(TypeStyle.caption2)
                .foregroundStyle(Palette.textSecondary)
        }
        .padding(.horizontal, Spacing.xs)
        .padding(.vertical, 3)
        .background(Palette.surface, in: Capsule())
        .overlay(Capsule().stroke(Palette.divider, lineWidth: 0.5))
    }
}

// MARK: - Mode chip

private struct ModeChip: View {
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
            .foregroundStyle(mode == .off ? Palette.textTertiary : Palette.textPrimary)
            .padding(.horizontal, Spacing.xs + 2)
            .padding(.vertical, 4)
            .background(Palette.surfaceElevated, in: Capsule())
            .overlay(Capsule().stroke(Palette.divider, lineWidth: 0.5))
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
            .foregroundStyle(Palette.textPrimary)
            .padding(.horizontal, Spacing.xs + 2)
            .padding(.vertical, 4)
            .background(Palette.surfaceElevated, in: Capsule())
            .overlay(Capsule().stroke(Palette.divider, lineWidth: 0.5))
        }
        .menuStyle(.button)
    }

    private var currentLabel: String {
        options.first(where: { $0.id == localeId })?.label ?? "Auto"
    }
}
