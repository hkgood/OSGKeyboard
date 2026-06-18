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
    /// Called when the user taps the record disc. Use this to cycle states in the preview sheet.
    var onTap: () -> Void = {}
    /// Called when the user taps the settings gear icon.
    var openSettings: () -> Void = {}

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
        .frame(height: 280)
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: Spacing.xs) {
            modeChip
            localeChip
            Spacer(minLength: 0)
            statusBadge
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
        HStack(spacing: 4) {
            Image(systemName: "wand.and.stars")
            Text("润色 · Polish")
            Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
        }
        .font(TypeStyle.caption2)
        .foregroundStyle(palette.textPrimary)
        .padding(.horizontal, Spacing.xs + 2).padding(.vertical, 4)
        .background(palette.surfaceElevated, in: Capsule())
        .overlay(Capsule().stroke(palette.divider, lineWidth: 0.5))
    }

    private var localeChip: some View {
        HStack(spacing: 4) {
            Image(systemName: "globe")
            Text("简体 · ZH-Hans")
            Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
        }
        .font(TypeStyle.caption2)
        .foregroundStyle(palette.textPrimary)
        .padding(.horizontal, Spacing.xs + 2).padding(.vertical, 4)
        .background(palette.surfaceElevated, in: Capsule())
        .overlay(Capsule().stroke(palette.divider, lineWidth: 0.5))
    }

    private var statusBadge: some View {
        Group {
            switch phase {
            case .idle:
                EmptyView()
            case .recording:
                HStack(spacing: 4) {
                    Circle().fill(palette.recordRed).frame(width: 6, height: 6)
                    Text("REC · 录音中").font(TypeStyle.caption2).foregroundStyle(palette.textSecondary)
                }
                .padding(.horizontal, Spacing.xs).padding(.vertical, 3)
                .background(palette.surface, in: Capsule())
                .overlay(Capsule().stroke(palette.divider, lineWidth: 0.5))
            case .processing:
                HStack(spacing: 4) {
                    Circle().fill(palette.accent).frame(width: 6, height: 6)
                    Text("···").font(TypeStyle.caption2).foregroundStyle(palette.textSecondary)
                }
                .padding(.horizontal, Spacing.xs).padding(.vertical, 3)
                .background(palette.surface, in: Capsule())
                .overlay(Capsule().stroke(palette.divider, lineWidth: 0.5))
            }
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
                Text("按住说话 · Hold to talk")
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
                    Text("处理中 · Processing")
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
                .shadow(color: .black.opacity(0.4), radius: 10, y: 6)
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
                    ProgressView().tint(.white).scaleEffect(1.1)
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
        HStack(spacing: Spacing.xxs) {
            iconButton("globe")
            iconButton("delete.left")
            Spacer(minLength: 0)
            Button(action: {}) {
                Text("空格 · Space")
                    .font(TypeStyle.body)
                    .foregroundStyle(palette.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 42)
                    .background(palette.surfaceElevated, in: RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous).stroke(palette.divider, lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
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
    KeyboardPreviewStub(phase: .idle, level: 0, transcript: "")
        .preferredColorScheme(.dark)
}
#endif
