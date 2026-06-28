// KeyboardPreviewStub.swift
// OSGKeyboard · Main App
//
// Stand-in for the keyboard extension's SwiftUI tree. iOS does not allow
// the host app to import symbols from its own keyboard extension target,
// so we ship a minimal mirror here. The actual production layout lives
// in OSGKeyboardExt/Views/KeyboardRootView.swift and is what shows up
// when the user enables the keyboard in iOS Settings.

import SwiftUI
import OSGKeyboardShared

struct KeyboardPreviewStub: View {
    @Environment(\.themePalette) private var palette: ThemePalette

    enum Phase { case idle, recording, processing }

    let phase: Phase
    let level: Double
    let transcript: String
    /// Current input mode id (`off` / `transcribe` / `polish`). Shown in
    /// the mode chip in the top bar. The chip is wired to `onModeCycle`,
    /// so tapping it actually advances the mode and the label updates
    /// in real time — the previous version was a static decoration and
    /// the user couldn't tell the chip was even a button.
    let modeId: String
    /// Current locale id (`auto` / `zh-Hans` / `en-US` / …). Shown in
    /// the locale chip. Same lifecycle as `modeId`.
    let localeId: String
    /// Called when the user taps the record disc. Use this to cycle states in the preview sheet.
    var onTap: () -> Void = {}
    /// Called when the user taps the settings gear icon.
    var openSettings: () -> Void = {}
    /// Cycle to the next mode in `[off, transcribe, polish]`. Owned by
    /// the sheet so `ProviderConfig` (a shared model) stays the source
    /// of truth — the stub just renders whatever it's told.
    var onModeCycle: () -> Void = {}
    /// Cycle to the next locale in the supported list. Same ownership
    /// story as `onModeCycle`.
    var onLocaleCycle: () -> Void = {}

    var body: some View {
        ZStack(alignment: .top) {
            palette.background
            VStack(spacing: 0) {
                topBar.frame(height: 32)
                centreArea.frame(maxWidth: .infinity, maxHeight: .infinity)
                bottomBar.frame(height: 56)
            }
            .padding(.top, 4)
            .padding(.bottom, 6)
        }
        .frame(height: 240)
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: Spacing.xs) {
            modeChip
            localeChip
            Spacer(minLength: 0)
            Button(action: openSettings) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(palette.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(palette.surface, in: Circle())
                    .overlay(Circle().stroke(palette.divider, lineWidth: 0.5))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Spacing.md)
    }

    private var modeChip: some View {
        Button(action: onModeCycle) {
            HStack(spacing: 4) {
                Image(systemName: modeIconName)
                Text(modeChipLabel)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
            }
            .font(TypeStyle.caption2)
            .foregroundStyle(palette.textPrimary)
            .padding(.horizontal, Spacing.xs + 2).padding(.vertical, 4)
            .background(palette.surfaceElevated, in: Capsule())
            .overlay(Capsule().stroke(palette.divider, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("preview.modeChip.cycle"))
    }

    private var localeChip: some View {
        Button(action: onLocaleCycle) {
            HStack(spacing: 4) {
                Image(systemName: "globe")
                Text(localeChipLabel)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
            }
            .font(TypeStyle.caption2)
            .foregroundStyle(palette.textPrimary)
            .padding(.horizontal, Spacing.xs + 2).padding(.vertical, 4)
            .background(palette.surfaceElevated, in: Capsule())
            .overlay(Capsule().stroke(palette.divider, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("preview.localeChip.cycle"))
    }

    /// Display label for the mode chip. The mode ids are
    /// `off` / `transcribe` / `polish`; we show a user-facing label
    /// from `Localizable.strings` and fall back to the raw id if a
    /// translation is missing (shouldn't happen, but cheaper than
    /// crashing in the preview).
    private var modeChipLabel: LocalizedStringKey {
        switch modeId {
        case "off":        return "settings.mode.off"
        case "transcribe": return "settings.mode.transcribe"
        case "polish":     return "settings.mode.polish"
        default:           return LocalizedStringKey(modeId)
        }
    }

    /// Display label for the locale chip. Cycles through the static
    /// locale list the Settings view also uses — see `staticLocales` in
    /// `SettingsView.swift`. We keep the list inline here so the
    /// preview doesn't need a settings dependency.
    private var localeChipLabel: LocalizedStringKey {
        switch localeId {
        case "auto":       return "locale.auto"
        case "zh-Hans":    return "locale.zh-Hans"
        case "zh-Hant":    return "locale.zh-Hant"
        case "en-US":      return "locale.en-US"
        case "ja-JP":      return "locale.ja-JP"
        case "ko-KR":      return "locale.ko-KR"
        default:           return LocalizedStringKey(localeId)
        }
    }

    /// Icon follows the mode so the user has a second visual cue
    /// beyond the label — off=slash, transcribe=mic, polish=wand.
    private var modeIconName: String {
        switch modeId {
        case "off":        return "mic.slash.fill"
        case "transcribe": return "mic.fill"
        case "polish":     return "wand.and.stars"
        default:           return "wand.and.stars"
        }
    }

    // MARK: - Centre area

    private var centreArea: some View {
        VStack(spacing: Spacing.xxs) {
            transcriptLine.frame(height: 22)
            recordDisc.frame(width: 140, height: 140)
        }
        .frame(maxWidth: .infinity)
    }

    private var transcriptLine: some View {
        Group {
            switch phase {
            case .idle:
                Text("keyboard.placeholder.idle")
                    .font(TypeStyle.caption)
                    .foregroundStyle(palette.textTertiary)
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
                    Text("keyboard.placeholder.processing")
                        .font(TypeStyle.caption)
                        .foregroundStyle(palette.textSecondary)
                }
            }
        }
        .padding(.horizontal, Spacing.md)
    }

    private var recordDisc: some View {
        ZStack {
            if phase == .recording {
                Circle()
                    .stroke(palette.recordRed.opacity(0.35), lineWidth: 2)
                    .frame(width: 110, height: 110)
                    .opacity(0.6)
                Circle()
                    .fill(RadialGradient(colors: [palette.recordRed.opacity(0.55), .clear], center: .center, startRadius: 30, endRadius: 70))
                    .frame(width: 160, height: 160)
                    .blur(radius: 12)
                    .opacity(0.4 + level * 0.6)
            } else if phase == .idle {
                // Idle-state ambient glow tinted with the accent — mirrors
                // the "polish / ready" brand colour so the disc is the
                // single most recognisable element on the keyboard.
                Circle()
                    .fill(RadialGradient(
                        colors: [palette.accent.opacity(0.30), .clear],
                        center: .center,
                        startRadius: 40,
                        endRadius: 90
                    ))
                    .frame(width: 180, height: 180)
                    .blur(radius: 18)
                    .opacity(0.7)
            }
            Circle()
                .fill(discGradient)
                .frame(width: 96, height: 96)
                .overlay(Circle().stroke(palette.accentGlow, lineWidth: 1.5))
            Group {
                switch phase {
                case .idle:
                    Image(systemName: "mic.fill")
                        .font(.system(size: 32, weight: .medium))
                        .foregroundStyle(.white)
                case .recording:
                    HStack(spacing: 3) {
                        ForEach(0..<12, id: \.self) { i in
                            Capsule()
                                .fill(palette.recordRed)
                                .frame(width: 2, height: 8 + CGFloat(level * 30) * (i.isMultiple(of: 2) ? 1 : 0.6))
                        }
                    }
                    .frame(width: 60, height: 32)
                case .processing:
                    // Scaled to ~50pt inside a 96pt disc (~52%) so the
                    // spinner is the dominant visual element of the
                    // loading state without crowding the disc's edge.
                    // `palette.textPrimary` (instead of hardcoded
                    // `.white`) keeps the spinner visible in both light
                    // and dark themes — the processing-state disc
                    // gradient is `surfaceElevated → surface`, which is
                    // light in light mode and would swallow a white
                    // spinner.
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(palette.textPrimary)
                        .scaleEffect(2.5)
                }
            }
        }
        .contentShape(Circle())
        .onTapGesture { onTap() }
    }

    private var discGradient: LinearGradient {
        switch phase {
        case .recording:
            return LinearGradient(
                colors: [palette.recordRed.opacity(0.95), palette.recordRed.opacity(0.75)],
                startPoint: .top,
                endPoint: .bottom
            )
        case .processing:
            return LinearGradient(
                colors: [palette.surfaceElevated, palette.surface],
                startPoint: .top,
                endPoint: .bottom
            )
        case .idle:
            // Brand green — same hue as the AccentColor asset and
            // `Palette.{dark,light}.accent`. The disc is the keyboard's
            // primary CTA, and it must read as "the green button" across
            // both light and dark themes.
            return LinearGradient(
                colors: [
                    palette.accent.opacity(0.95),
                    palette.accent.opacity(0.75)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        // Mirror the real keyboard — globe button removed (the iOS
        // system keyboard strip already provides one).
        HStack(spacing: Spacing.xxs) {
            iconButton("delete.left")
            Button(action: {}) {
                Text("common.space")
                    .font(TypeStyle.body)
                    .foregroundStyle(palette.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 42)
                    .background(palette.surfaceElevated, in: RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous).stroke(palette.divider, lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            iconButton("return")
        }
        .padding(.horizontal, Spacing.sm)
    }

    private func iconButton(_ systemName: String) -> some View {
        Button(action: {}) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(palette.textPrimary)
                .frame(width: 40, height: 40)
                .background(palette.surfaceElevated, in: RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous).stroke(palette.divider, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }
}

#if DEBUG
#Preview {
    KeyboardPreviewStub(
        phase: .idle,
        level: 0,
        transcript: "",
        modeId: "polish",
        localeId: "zh-Hans"
    )
    .preferredColorScheme(.dark)
}
#endif
