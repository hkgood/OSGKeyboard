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
    @Environment(\.themePalette) private var palette: ThemePalette

    @Environment(\.dismiss) private var dismiss

    @ObservedObject private var config = ProviderConfig.shared

    @State private var phase: StubPhase = .idle
    @State private var level: Double = 0
    @State private var showSettings = false
    /// The text that accumulates in the top textbox. The real keyboard
    /// inserts directly into the host text field via `textDocumentProxy`;
    /// in this preview we maintain a parallel `@State` so the user can
    /// visually verify the flow ("record → recognize → text appears here")
    /// without enabling the keyboard in iOS Settings.
    @State private var typedText: String = ""

    private enum StubPhase { case idle, recording, processing }

    var body: some View {
        ZStack {
            palette.background.ignoresSafeArea()
            VStack(spacing: 0) {
                VStack(spacing: Spacing.md) {
                    Text("Keyboard Preview")
                        .font(TypeStyle.title2)
                        .foregroundStyle(palette.textPrimary)
                    Text("Tap the disc to cycle states. The real keyboard uses the same layout.")
                        .font(TypeStyle.caption)
                        .foregroundStyle(palette.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Spacing.lg)
                    mockTextField.padding(.horizontal, Spacing.md)
                }
                .padding(.top, Spacing.lg)
                Spacer(minLength: 0)
                keyboardBlock
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }

    /// Real `TextField` (was a static placeholder HStack before fix). The
    /// user can both type into it AND see recognized text land in it as
    /// `cyclePhase` advances through the pipeline.
    private var mockTextField: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: "text.cursor")
                .foregroundStyle(palette.textSecondary)
            TextField("试着输入或按 disc 录音", text: $typedText, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.plain)
                .foregroundStyle(palette.textPrimary)
                .tint(palette.accent)
            if !typedText.isEmpty {
                Button {
                    typedText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(palette.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear text")
            }
        }
        .padding(Spacing.md)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: Radius.medium))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.medium)
                .stroke(palette.divider, lineWidth: 0.5)
        )
    }

    private var keyboardBlock: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(palette.divider)
                .frame(height: 0.5)
            KeyboardPreviewStub(
                phase: stubPhase,
                level: level,
                transcript: stubTranscript,
                onTap: cyclePhase,
                openSettings: { showSettings = true }
            )
        }
    }

    private var stubPhase: KeyboardPreviewStub.Phase {
        switch phase {
        case .idle:        return .idle
        case .recording:   return .recording
        case .processing:  return .processing
        }
    }

    private var stubTranscript: String {
        switch phase {
        case .recording: return "你好,我想说一段测试文字"
        default:         return ""
        }
    }

    private func cyclePhase() {
        withAnimation(Motion.quick) {
            switch phase {
            case .idle:
                phase = .recording
            case .recording:
                // Local engine: recognition is "instant" — flip straight
                // to idle and drop the recognized text into the textbox.
                // Cloud engine: hop to .processing to fake the LLM
                // round-trip; the text lands in the textbox on the
                // processing → idle step.
                if config.engineMode == "local" {
                    insertRecognizedText()
                    phase = .idle
                } else {
                    phase = .processing
                }
            case .processing:
                insertRecognizedText()
                phase = .idle
            }
        }
    }

    /// Append the (mock) recognized transcript to the textbox, with a
    /// leading space when the existing text doesn't already end in one
    /// — matches what `textDocumentProxy.insertText` would do when the
    /// user's existing draft has no trailing whitespace.
    private func insertRecognizedText() {
        let recognized = stubTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !recognized.isEmpty else { return }
        if typedText.isEmpty {
            typedText = recognized
        } else if typedText.last == " " || typedText.last == "\n" {
            typedText += recognized
        } else {
            typedText += " " + recognized
        }
    }
}

#if DEBUG
#Preview {
    KeyboardPreviewSheet()
}
#endif
