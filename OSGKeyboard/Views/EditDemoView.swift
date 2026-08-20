// EditDemoView.swift
// OSGKeyboard · Main App (DEBUG-only)
//
// What's New "Edit last input" recording host. Uses the **real**
// `LastInputEditView` (compiled into the app target) driven by a scripted
// `KeyboardState` — no ASR / LLM. Opening beat shows the voice mic + hint.
// Launch with `--edit-demo`. Not shipped in Release.

#if DEBUG
import OSGKeyboardShared
import SwiftUI

struct EditDemoView: View {
    private static let originalText = "明天下午三点开会讨论方案"
    private static let editedText = "各位好，明天下午三点在 A 会议室召开方案讨论会，请准时参加。"

    private enum Scene: Equatable {
        case hint
        case editing
    }

    @StateObject private var state = KeyboardState()
    @State private var scene: Scene = .hint

    private var source: EditSessionSource {
        let reference = EditableInputReference(
            displayText: Self.originalText,
            insertedText: Self.originalText,
            postInsertionFingerprint: nil,
            extensionInstanceID: UUID()
        )
        return EditSessionSource(reference: reference)
    }

    private var palette: ThemePalette { Palette.light }

    var body: some View {
        ZStack {
            Color(red: 0.06, green: 0.06, blue: 0.07).ignoresSafeArea()
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                Group {
                    switch scene {
                    case .hint:
                        hintPanel
                    case .editing:
                        LastInputEditView(state: state)
                    }
                }
                .background(palette.background.ignoresSafeArea(edges: .bottom))
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(palette.divider)
                        .frame(height: 0.5)
                }
            }
        }
        .environment(\.themePalette, palette)
        .environment(\.locale, Locale(identifier: "zh-Hans"))
        .preferredColorScheme(.light)
        .task { await runTimeline() }
    }

    // MARK: - Opening hint (voice mic + real copy)

    private var hintPanel: some View {
        VStack(spacing: Spacing.sm) {
            HStack {
                KeyboardBrandLogo(action: {})
                Spacer(minLength: 0)
            }
            .padding(.horizontal, KeyboardTopBarMetrics.nestedHorizontalInset)
            .frame(height: KeyboardTopBarMetrics.height)

            Spacer(minLength: 0)
            Text(ExtL10n.string("keyboard.edit.hint.available"))
                .font(TypeStyle.footnote)
                .foregroundStyle(palette.accent)
            RecordButton(
                phase: .idleReady,
                level: 0,
                isEnabled: true,
                onToggle: {},
                onPressingChanged: { _ in },
                onEditLongPressBegan: nil
            )
            .frame(width: 121, height: 121)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, KeyboardChromeLayout.horizontalInset)
        .frame(maxWidth: .infinity)
        .frame(height: KeyboardChromeLayout.totalHeight)
        .padding(.bottom, 24)
    }

    // MARK: - Timeline

    private func runTimeline() async {
        let src = source
        let review = EditReview(
            source: src,
            resultText: Self.editedText,
            utteranceID: UUID()
        )

        state.editCanReplaceOriginal = true
        state.layoutWidth = 390
        state.micVoiceAvailability = .ready
        state.closeEditMode = {}
        state.confirmEditResult = {}
        state.stopEditListening = {}
        state.beginEditLastInput = {}
        state.openSettings = {}

        try? await sleep(1.4) // hint hold

        withAnimation(.easeInOut(duration: 0.28)) {
            scene = .editing
            state.editSession = .listening(src)
            state.lastTranscript = ExtL10n.string("keyboard.edit.status.listening")
            state.level = 0.45
            state.utteranceRemainingSeconds = 59
        }
        for _ in 0..<4 {
            try? await sleep(0.4)
            state.level = Double.random(in: 0.25...0.85)
            state.utteranceRemainingSeconds = max(0, state.utteranceRemainingSeconds - 1)
        }

        withAnimation(.easeInOut(duration: 0.2)) {
            state.editSession = .processing(src)
            state.lastTranscript = ExtL10n.string("keyboard.edit.status.processing")
        }
        try? await sleep(1.5)

        withAnimation(.easeInOut(duration: 0.25)) {
            state.editSession = .review(review)
            state.lastTranscript = ExtL10n.string("keyboard.edit.status.review")
        }
        // Hold long enough for auto-scroll to「编辑后」+ a beat of reading.
        try? await sleep(3.2)

        withAnimation(.easeInOut(duration: 0.2)) {
            state.editSession = .applying(review)
            state.lastTranscript = ExtL10n.string("keyboard.edit.status.applying")
        }
        // Stay on applying so the last captured frames are still the real UI.
        try? await sleep(2.0)
        try? await Task.sleep(nanoseconds: 60_000_000_000)
    }

    /// Slow-mo for screenshot-sequence recording (~2× wall clock).
    private func sleep(_ seconds: Double) async throws {
        try await Task.sleep(nanoseconds: UInt64(seconds * 2.0 * 1_000_000_000))
    }
}
#endif
