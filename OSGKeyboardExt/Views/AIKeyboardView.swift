// AIKeyboardView.swift
// OSGKeyboard · Keyboard Extension
//
// Temporary voice-to-AI surface. The latest answer remains visible while a
// follow-up is running and is inserted only through the explicit Send action.

import SwiftUI
import OSGKeyboardShared

struct AIKeyboardView: View {
    private enum Layout {
        static let contentHeight: CGFloat = 174
        static let actionRowHeight: CGFloat = 55
        static let actionButtonHeight: CGFloat = 50
        static let actionButtonMaxWidth: CGFloat = 150
        static let statusHeight: CGFloat = 20
    }

    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var state: KeyboardState
    @ObservedObject var typing: TypingSessionController
    let onInsert: (String) -> Void

    private var palette: ThemePalette {
        colorScheme == .dark ? Palette.dark : Palette.light
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar.frame(height: KeyboardTopBarMetrics.height)
            answerArea.frame(height: resolvedAnswerHeight)
            actionRow.frame(height: Layout.actionRowHeight)
        }
        .frame(maxWidth: KeyboardChromeLayout.voiceContentMaxWidth)
        .padding(.vertical, 4)
        .padding(.horizontal, KeyboardChromeLayout.horizontalInset)
        .frame(maxWidth: .infinity)
        .frame(height: resolvedHeight)
        .environment(\.themePalette, palette)
    }

    private var resolvedHeight: CGFloat {
        TypingSurfaceMetrics.contentHeight(
            isIPad: state.usesIPadLayoutMetrics,
            width: state.layoutWidth
        )
    }

    private var resolvedAnswerHeight: CGFloat {
        max(
            Layout.contentHeight,
            resolvedHeight
                - KeyboardTopBarMetrics.height
                - Layout.actionRowHeight
                - 8
        )
    }

    @ViewBuilder
    private var topBar: some View {
        if state.canCancelAIInput {
            HStack(spacing: Spacing.xs) {
                KeyboardBrandLogo(action: state.openSettings)
                Spacer(minLength: 0)
                KeyboardCancelButton(
                    action: state.cancelAIInput,
                    accessibilityLabel: ExtL10n.text("keyboard.ai.cancel"),
                    accessibilityHint: ExtL10n.text("keyboard.ai.cancelHint")
                )
            }
            .padding(.horizontal, KeyboardTopBarMetrics.nestedHorizontalInset)
        } else if let suggestion = state.clipboardSuggestionText, !suggestion.isEmpty {
            // Replaces logo + capsule tabs until dismissed.
            ClipboardSuggestionBar(
                text: suggestion,
                onInsert: { state.insertClipboardText(suggestion) },
                onDismiss: state.dismissClipboardSuggestion
            )
            .padding(.horizontal, KeyboardTopBarMetrics.nestedHorizontalInset)
        } else {
            HStack(spacing: Spacing.xs) {
                KeyboardBrandLogo(action: state.openSettings)
                Spacer(minLength: 0)
                KeyboardTopControls(
                    state: state,
                    typing: typing,
                    palette: palette,
                    onInsert: onInsert
                )
            }
            .padding(.horizontal, KeyboardTopBarMetrics.nestedHorizontalInset)
        }
    }

    private var answerArea: some View {
        ZStack(alignment: .bottom) {
            if showsPlaceholder {
                // Empty-state tip: geometric center of the answer plane.
                Text(ExtL10n.string("keyboard.ai.placeholder"))
                    .font(TypeStyle.body)
                    .foregroundStyle(palette.textTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Spacing.md)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.vertical) {
                        Group {
                            if let draft = state.aiSession.draftAnswerText,
                               !draft.isEmpty {
                                Text(draft)
                                    .foregroundStyle(palette.textPrimary)
                                    .id("ai-draft")
                            } else if let answer = state.aiSession.answer {
                                Text(answer.text)
                                    .foregroundStyle(palette.textPrimary)
                                    .id(answer.id)
                            }
                        }
                        .font(TypeStyle.body)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(.horizontal, Spacing.md)
                        .padding(.top, Spacing.sm)
                        .padding(.bottom, Layout.statusHeight + Spacing.sm)
                    }
                    .scrollIndicators(.visible)
                    .onChange(of: state.aiSession.answer?.id) { _, answerID in
                        guard let answerID else { return }
                        proxy.scrollTo(answerID, anchor: .top)
                    }
                    .onChange(of: state.aiSession.draftAnswerText) { _, draft in
                        guard let draft, !draft.isEmpty else { return }
                        proxy.scrollTo("ai-draft", anchor: .bottom)
                    }
                }
            }

            statusLine
                .frame(height: Layout.statusHeight)
                .padding(.horizontal, Spacing.md)
        }
    }

    /// No draft/answer yet — show the centered mic guidance instead of a scroll body.
    private var showsPlaceholder: Bool {
        let hasDraft = !(state.aiSession.draftAnswerText?.isEmpty ?? true)
        return !hasDraft && state.aiSession.answer == nil
    }

    private var statusLine: some View {
        // Loading spinner lives on the mic button only — avoid a second
        // ProgressView beside the status / draft caption.
        Text(statusText)
            .font(TypeStyle.caption)
            .foregroundStyle(
                state.aiSession.phase == .failed
                    ? palette.warning
                    : palette.textSecondary
            )
            .lineLimit(1)
            .truncationMode(.head)
            .frame(maxWidth: .infinity, alignment: .center)
    }

    private var actionRow: some View {
        HStack(spacing: Spacing.sm) {
            aiMicrophoneButton
            sendButton
        }
        .frame(maxWidth: .infinity)
    }

    private var aiMicrophoneButton: some View {
        Button(action: state.tapAIMic) {
            ZStack {
                Capsule().fill(palette.accent)
                if state.aiSession.phase == .listening {
                    Capsule()
                        .stroke(Color.white.opacity(0.28), lineWidth: 1.5)
                        .scaleEffect(1 + min(max(state.level, 0), 1) * 0.08)
                        .animation(Motion.soft, value: state.level)
                }
                microphoneContent
            }
            .frame(
                maxWidth: Layout.actionButtonMaxWidth,
                minHeight: Layout.actionButtonHeight,
                maxHeight: Layout.actionButtonHeight
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(microphoneDisabled)
        .accessibilityLabel(ExtL10n.text(microphoneAccessibilityKey))
    }

    @ViewBuilder
    private var microphoneContent: some View {
        switch state.aiSession.phase {
        case .listening:
            WaveformView(
                level: state.level,
                barCount: 7,
                color: .white,
                active: true
            )
            .frame(width: 35, height: 22)
            .clipped()
        case .preparing, .recognizing, .generating:
            ProgressView().tint(.white)
        case .inactive, .idle, .ready, .awaitingSend, .inserted, .sent, .failed:
            Image(systemName: "mic.fill")
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(.white)
        }
    }

    private var sendButton: some View {
        Button(action: state.sendAIAnswer) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: answerActionSystemName)
                Text(answerActionTitle)
            }
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(answerActionForeground)
            .frame(
                maxWidth: Layout.actionButtonMaxWidth,
                minHeight: Layout.actionButtonHeight,
                maxHeight: Layout.actionButtonHeight
            )
            .background(
                answerActionFill,
                in: Capsule()
            )
            .overlay(Capsule().stroke(answerActionBorder, lineWidth: 0.5))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!state.aiSession.canPerformAnswerAction)
        .accessibilityLabel(Text(answerActionTitle))
        .accessibilityHint(ExtL10n.text("keyboard.ai.sendA11y"))
    }

    private var answerActionTitle: String {
        switch state.aiSession.phase {
        case .awaitingSend:
            return ExtL10n.string("common.send")
        case .inserted:
            return ExtL10n.string("keyboard.ai.inserted")
        case .sent:
            return ExtL10n.string("keyboard.ai.sent")
        case .inactive, .idle, .preparing, .listening, .recognizing,
             .generating, .ready, .failed:
            return ExtL10n.string("keyboard.ai.insert")
        }
    }

    private var answerActionSystemName: String {
        switch state.aiSession.phase {
        case .awaitingSend:
            return "paperplane.fill"
        case .inserted, .sent:
            return "checkmark"
        case .inactive, .idle, .preparing, .listening, .recognizing,
             .generating, .ready, .failed:
            return "plus"
        }
    }

    private var answerActionFill: Color {
        guard state.aiSession.canPerformAnswerAction else {
            return palette.surfaceElevated
        }
        return state.aiSession.canSend
            ? palette.accent
            : NativeKeyboardKeyColors.fill(for: colorScheme)
    }

    private var answerActionForeground: Color {
        guard state.aiSession.canPerformAnswerAction else {
            return palette.textTertiary
        }
        return state.aiSession.canSend
            ? .white
            : NativeKeyboardKeyColors.text(for: colorScheme)
    }

    private var answerActionBorder: Color {
        guard state.aiSession.canSend else {
            return palette.divider
        }
        return Color.black.opacity(colorScheme == .dark ? 0.10 : 0.08)
    }

    private var microphoneDisabled: Bool {
        switch state.aiSession.phase {
        case .preparing, .recognizing, .generating:
            return true
        case .inactive, .idle, .listening, .ready, .awaitingSend,
             .inserted, .sent, .failed:
            return state.micDisabled || !state.aiServiceAvailable
        }
    }

    private var statusText: String {
        if let error = state.aiSession.errorMessage, !error.isEmpty {
            return error
        }
        if !state.aiServiceAvailable {
            return ExtL10n.string("keyboard.ai.error.missingAPIKey")
        }
        switch state.aiSession.phase {
        case .inactive, .idle, .ready, .awaitingSend, .inserted, .sent:
            return ""
        case .preparing:
            return ExtL10n.string("keyboard.placeholder.preparing")
        case .listening:
            return state.aiSession.transcript.isEmpty
                ? ExtL10n.string("keyboard.ai.listening")
                : state.aiSession.transcript
        case .recognizing:
            return state.aiSession.transcript.isEmpty
                ? ExtL10n.string("keyboard.ai.recognizing")
                : state.aiSession.transcript
        case .generating:
            if let draft = state.aiSession.draftAnswerText, !draft.isEmpty {
                return ExtL10n.string("keyboard.ai.generating")
            }
            return state.aiSession.transcript.isEmpty
                ? ExtL10n.string("keyboard.ai.thinking")
                : state.aiSession.transcript
        case .failed:
            return ExtL10n.string("keyboard.ai.error.requestFailed")
        }
    }

    private var microphoneAccessibilityKey: String {
        state.aiSession.phase == .listening
            ? "keyboard.ai.stopA11y"
            : "keyboard.ai.startA11y"
    }
}
