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
//   │  [polish] [中]                      ⚙     │  ← header band (top)
//   │              (transcript preview)         │
//   │              ┊                          │
//   │              ◯ mic (centred)              │  ← action cluster:
//   │   [delete]  [  space  ]  [return]         │     mic + bottom row
//   │              ┊                          │
//   └───────────────────────────────────────────┘

import SwiftUI
import OSGKeyboardShared

private enum KeyboardLayoutMetrics {
    static let micSize: CGFloat = 121
    static let micToButtonGap: CGFloat = 8
    static let bottomActionRowHeight: CGFloat = 48
    static let bottomActionFixedWidth: CGFloat = 86
    static let bottomActionSpacing: CGFloat = Spacing.xs
    /// Gap between the top chip row and the transcript / hint line (4 pt → 8 pt, +100%).
    static let topBarToTranscriptSpacing: CGFloat = Spacing.xs
    /// Outer inset for the bottom action row from screen edges (8 pt → 24 pt, +200%).
    static let sideActionHorizontalInset: CGFloat = Spacing.xs * 3

    // MARK: - Content-driven keyboard height (single source of truth)
    static let outerPaddingTop: CGFloat = 2
    static let outerPaddingBottom: CGFloat = 1
    static let topBarHeight: CGFloat = 38
    static let transcriptLineHeight: CGFloat = 22
    /// mic (121) + gap (8) + bottom row (48) = 177 pt
    static let actionClusterHeight: CGFloat = micSize + micToButtonGap + bottomActionRowHeight
    /// Gap between transcript line and mic (−30% from former 16 pt).
    static let actionClusterTopGap: CGFloat = Spacing.md * 0.7
    /// Minimal gap below the bottom action row.
    static let actionClusterBottomGap: CGFloat = Spacing.xs / 2

    static var headerBandHeight: CGFloat {
        topBarHeight + topBarToTranscriptSpacing + transcriptLineHeight
    }

    /// 2 + 68 + 11.2 + 177 + 4 + 1 = 263.2 pt
    static var totalHeight: CGFloat {
        outerPaddingTop
            + headerBandHeight
            + actionClusterTopGap
            + actionClusterHeight
            + actionClusterBottomGap
            + outerPaddingBottom
    }
}

public struct KeyboardRootView: View {
    @Environment(\.colorScheme) private var colorScheme

    @ObservedObject var state: State

    public init(state: KeyboardViewController.State) {
        self.state = state
    }

    /// Content-driven keyboard height; mirrored on `UIInputViewController.view`
    /// in `KeyboardViewController` (see `KeyboardLayoutMetrics.totalHeight`).
    static let totalHeight: CGFloat = KeyboardLayoutMetrics.totalHeight

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
            .frame(height: Self.totalHeight)
            // Feed the resolved palette to all nested chips/buttons.
            .environment(\.themePalette, palette)

            // v0.3.0: in-keyboard first-launch onboarding. Mounted as
            // an overlay so the normal keyboard chrome stays
            // responsive underneath (mic button still works, chip
            // taps register). Only rendered until
            // `state.hasCompletedOnboarding` flips to true; from
            // then on the overlay is unmounted and never re-rendered.
            if !state.hasCompletedOnboarding {
                KeyboardOnboardingOverlay(state: state)
                    .environment(\.themePalette, palette)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: state.hasCompletedOnboarding)
    }

    /// Top chip row + transcript / hint line.
    private var headerBand: some View {
        VStack(spacing: KeyboardLayoutMetrics.topBarToTranscriptSpacing) {
            topBar
                .frame(height: KeyboardLayoutMetrics.topBarHeight)

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
            .frame(height: KeyboardLayoutMetrics.transcriptLineHeight)
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: Spacing.xs) {
            if state.isLocalEngine {
                LocalEngineChip()
            } else {
                CloudEngineChip()
            }
            if state.isPolishScenarioChipVisible {
                ScenarioChip(state: state)
            }
            LocaleChip(localeId: state.localeId) { newId in
                state.setLocale(newId)
            }
            // v0.3.0: detected app context — the per-app polish mode.
            // The chip mirrors `AppGroupStore.detectedAppContext` and
            // writes overrides back so the next LLM call uses the new
            // tone. Hidden during onboarding (the overlay reads better
            // without chip clutter).
            if state.hasCompletedOnboarding {
                AppContextChip(state: state)
            }
            // v0.3: always show the translation chip when the active
            // engine can run the cloud LLM step — off-by-default keeps
            // the menu reachable so the user can pick a target language
            // without opening Settings.
            if state.isTranslationChipVisible {
                TranslationChip(state: state)
            }
            Spacer(minLength: 0)
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

    // MARK: - Action cluster

    /// Mic centred above a bottom row: delete · space · return (or swapped).
    private var micActionRow: some View {
        let editingBlocked = voiceInputBlocksEditing
        let swapKeys = state.handednessPreference.swapsActionKeys

        return VStack(spacing: KeyboardLayoutMetrics.micToButtonGap) {
            RecordButton(
                phase: buttonPhase,
                level: state.level,
                remainingSeconds: state.phase == .recording ? state.utteranceRemainingSeconds : nil,
                onToggle: state.tapMic
            )
            .frame(width: KeyboardLayoutMetrics.micSize, height: KeyboardLayoutMetrics.micSize)

            HStack(spacing: KeyboardLayoutMetrics.bottomActionSpacing) {
                if swapKeys {
                    bottomReturnButton(disabled: editingBlocked)
                    bottomSpaceButton(disabled: editingBlocked)
                    bottomDeleteButton(disabled: editingBlocked)
                } else {
                    bottomDeleteButton(disabled: editingBlocked)
                    bottomSpaceButton(disabled: editingBlocked)
                    bottomReturnButton(disabled: editingBlocked)
                }
            }
        }
        .padding(.horizontal, KeyboardLayoutMetrics.sideActionHorizontalInset)
        .frame(maxWidth: .infinity)
    }

    private func bottomDeleteButton(disabled: Bool) -> some View {
        RepeatingDeleteButton(disabled: disabled) {
            state.deleteBackward()
        }
        .frame(
            width: KeyboardLayoutMetrics.bottomActionFixedWidth,
            height: KeyboardLayoutMetrics.bottomActionRowHeight
        )
    }

    private func bottomSpaceButton(disabled: Bool) -> some View {
        RectangularToolbarButton(spaceStyle: true, label: "space", disabled: disabled) {
            state.insertSpace()
        }
        .frame(height: KeyboardLayoutMetrics.bottomActionRowHeight)
    }

    private func bottomReturnButton(disabled: Bool) -> some View {
        RectangularToolbarButton(systemName: "return", label: "newline", disabled: disabled) {
            state.insertNewline()
        }
        .frame(
            width: KeyboardLayoutMetrics.bottomActionFixedWidth,
            height: KeyboardLayoutMetrics.bottomActionRowHeight
        )
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
        .frame(width: 390, height: KeyboardRootView.totalHeight)
        .preferredColorScheme(.dark)
}

#Preview("Keyboard · Recording") {
    KeyboardRootView(state: KeyboardViewController.State.previewRecording)
        .frame(width: 390, height: KeyboardRootView.totalHeight)
        .preferredColorScheme(.dark)
}

#Preview("Keyboard · Processing") {
    KeyboardRootView(state: KeyboardViewController.State.previewProcessing)
        .frame(width: 390, height: KeyboardRootView.totalHeight)
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
