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

    enum Phase { case idle, recording, processing }

    let phase: Phase
    let level: Double
    let transcript: String

    var body: some View {
        ZStack(alignment: .top) {
            Palette.background
            VStack(spacing: 0) {
                topBar.frame(height: 32)
                centreArea.frame(maxWidth: .infinity, maxHeight: .infinity)
                bottomBar.frame(height: 56)
            }
            .padding(.top, 4)
            .padding(.bottom, 6)
        }
        .frame(height: 280)
        .preferredColorScheme(.dark)
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: Spacing.xs) {
            modeChip
            localeChip
            Spacer(minLength: 0)
            statusBadge
            Button(action: {}) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Palette.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(Palette.surface, in: Circle())
                    .overlay(Circle().stroke(Palette.divider, lineWidth: 0.5))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Spacing.md)
    }

    private var modeChip: some View {
        HStack(spacing: 4) {
            Image(systemName: "wand.and.stars")
            Text("润色")
            Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
        }
        .font(TypeStyle.caption2)
        .foregroundStyle(Palette.textPrimary)
        .padding(.horizontal, Spacing.xs + 2).padding(.vertical, 4)
        .background(Palette.surfaceElevated, in: Capsule())
        .overlay(Capsule().stroke(Palette.divider, lineWidth: 0.5))
    }

    private var localeChip: some View {
        HStack(spacing: 4) {
            Image(systemName: "globe")
            Text("简体")
            Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
        }
        .font(TypeStyle.caption2)
        .foregroundStyle(Palette.textPrimary)
        .padding(.horizontal, Spacing.xs + 2).padding(.vertical, 4)
        .background(Palette.surfaceElevated, in: Capsule())
        .overlay(Capsule().stroke(Palette.divider, lineWidth: 0.5))
    }

    private var statusBadge: some View {
        Group {
            switch phase {
            case .idle:
                EmptyView()
            case .recording:
                HStack(spacing: 4) {
                    Circle().fill(Palette.recordRed).frame(width: 6, height: 6)
                    Text("REC").font(TypeStyle.caption2).foregroundStyle(Palette.textSecondary)
                }
                .padding(.horizontal, Spacing.xs).padding(.vertical, 3)
                .background(Palette.surface, in: Capsule())
                .overlay(Capsule().stroke(Palette.divider, lineWidth: 0.5))
            case .processing:
                HStack(spacing: 4) {
                    Circle().fill(Palette.accent).frame(width: 6, height: 6)
                    Text("···").font(TypeStyle.caption2).foregroundStyle(Palette.textSecondary)
                }
                .padding(.horizontal, Spacing.xs).padding(.vertical, 3)
                .background(Palette.surface, in: Capsule())
                .overlay(Capsule().stroke(Palette.divider, lineWidth: 0.5))
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
            }
        }
        .padding(.horizontal, Spacing.md)
    }

    private var recordDisc: some View {
        ZStack {
            if phase == .recording {
                Circle()
                    .stroke(Palette.recordRed.opacity(0.35), lineWidth: 2)
                    .frame(width: 110, height: 110)
                    .opacity(0.6)
                Circle()
                    .fill(RadialGradient(colors: [Palette.recordRed.opacity(0.55), .clear], center: .center, startRadius: 30, endRadius: 70))
                    .frame(width: 160, height: 160)
                    .blur(radius: 12)
                    .opacity(0.4 + level * 0.6)
            }
            Circle()
                .fill(discGradient)
                .frame(width: 96, height: 96)
                .overlay(Circle().stroke(Color.white.opacity(0.16), lineWidth: 1))
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
                                .fill(Palette.recordRed)
                                .frame(width: 2, height: 8 + CGFloat(level * 30) * (i.isMultiple(of: 2) ? 1 : 0.6))
                        }
                    }
                    .frame(width: 60, height: 32)
                case .processing:
                    ProgressView().tint(.white).scaleEffect(1.1)
                }
            }
        }
    }

    private var discGradient: LinearGradient {
        switch phase {
        case .recording:
            return LinearGradient(colors: [Palette.recordRed.opacity(0.95), Palette.recordRed.opacity(0.75)], startPoint: .top, endPoint: .bottom)
        case .processing:
            return LinearGradient(colors: [Palette.surfaceElevated, Palette.surface], startPoint: .top, endPoint: .bottom)
        case .idle:
            return LinearGradient(colors: [Color(white: 0.22), Color(white: 0.10)], startPoint: .top, endPoint: .bottom)
        }
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        HStack(spacing: Spacing.xxs) {
            iconButton("globe")
            iconButton("delete.left")
            Spacer(minLength: 0)
            Button(action: {}) {
                Text("空格")
                    .font(TypeStyle.body)
                    .foregroundStyle(Palette.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 42)
                    .background(Palette.surfaceElevated, in: RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous).stroke(Palette.divider, lineWidth: 0.5))
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
                .foregroundStyle(Palette.textPrimary)
                .frame(width: 40, height: 40)
                .background(Palette.surfaceElevated, in: RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous).stroke(Palette.divider, lineWidth: 0.5))
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
