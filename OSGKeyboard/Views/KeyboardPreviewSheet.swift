// KeyboardPreviewSheet.swift
// OSGKeyboard · Main App
//
// Renders a stand-in keyboard layout inside the main app so the user
// can preview what the real keyboard extension looks like without
// enabling the keyboard in iOS Settings. Tap the disc to cycle
// through idle / recording / processing so all visual states are
// inspectable.

import SwiftUI
import OSGKeyboardShared

struct KeyboardPreviewSheet: View {
    @Environment(\.dismiss) private var dismiss

    // We mirror only the fields the stand-in actually needs, instead of
    // crossing the OSGKeyboardExt target boundary to construct a
    // `KeyboardViewController.State` (whose initialiser is internal).
    @State private var phase: StubPhase = .idle
    @State private var level: Double = 0
    @State private var transcript: String = ""

    private enum StubPhase { case idle, recording, processing }

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            VStack(spacing: 0) {
                VStack(spacing: Spacing.md) {
                    Text("Keyboard Preview")
                        .font(TypeStyle.title2)
                        .foregroundStyle(Palette.textPrimary)
                    Text("Tap the disc to cycle states. The real keyboard uses the same layout.")
                        .font(TypeStyle.caption)
                        .foregroundStyle(Palette.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Spacing.lg)
                    mockTextField.padding(.horizontal, Spacing.md)
                }
                .padding(.top, Spacing.lg)
                Spacer(minLength: 0)
                keyboardBlock
            }
        }
    }

    private var mockTextField: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Palette.textSecondary)
            Text("Type here…")
                .foregroundStyle(Palette.textTertiary)
            Spacer()
        }
        .padding(Spacing.md)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.medium))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.medium)
                .stroke(Palette.divider, lineWidth: 0.5)
        )
    }

    private var keyboardBlock: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Palette.divider)
                .frame(height: 0.5)
            KeyboardPreviewStub(
                phase: stubPhase,
                level: level,
                transcript: transcript
            )
            .environment(\.colorScheme, .dark)
            Rectangle()
                .fill(Color.black)
                .frame(height: 34)
                .overlay(alignment: .center) {
                    Capsule()
                        .fill(Color.white.opacity(0.4))
                        .frame(width: 134, height: 5)
                }
        }
    }

    private var stubPhase: KeyboardPreviewStub.Phase {
        switch phase {
        case .idle:        return .idle
        case .recording:   return .recording
        case .processing:  return .processing
        }
    }
}

#if DEBUG
#Preview {
    KeyboardPreviewSheet()
}
#endif
