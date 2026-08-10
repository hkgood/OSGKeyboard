// EditDemoView.swift
// OSGKeyboard · Main App (DEBUG-only)
//
// Scripted, keyboard-sized recreation of the extension's `LastInputEditView`
// used ONLY to record the "Edit last input" What's New clip in the simulator.
// It reuses the real shared `EditTextPager`, design tokens, and the real
// `EditSessionState` machine, and steps a fixed timeline (idle hint → listening
// → processing → review swipe → apply) with canned text — no ASR, no LLM.
// Launched via `--edit-demo` (see OSGKeyboardApp). Not shipped in Release.

#if DEBUG
import SwiftUI
import OSGKeyboardShared

struct EditDemoView: View {
    // Canned material for the clip.
    private static let originalText = "明天下午三点开会讨论方案"
    private static let editedText = "各位好，明天下午三点在 A 会议室召开方案讨论会，请准时参加。"

    private let palette = Palette.light

    @State private var editSession: EditSessionState = .inactive
    @State private var showHint = true
    @State private var selectedPage: Int? = 0
    @State private var remainingSeconds = 59

    private var source: EditSessionSource {
        let reference = EditableInputReference(
            displayText: Self.originalText,
            insertedText: Self.originalText,
            postInsertionFingerprint: nil,
            extensionInstanceID: UUID()
        )
        return EditSessionSource(reference: reference)
    }

    var body: some View {
        ZStack {
            Color(red: 0.06, green: 0.06, blue: 0.07).ignoresSafeArea()
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                keyboardPanel
                    .background(panelBackground)
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(palette.divider)
                            .frame(height: 0.5)
                    }
            }
        }
        .environment(\.themePalette, palette)
        .task { await runTimeline() }
    }

    private var panelBackground: some View {
        palette.background.ignoresSafeArea(edges: .bottom)
    }

    // MARK: - Panel (mirrors LastInputEditView layout)

    private var keyboardPanel: some View {
        VStack(spacing: 0) {
            topBar.frame(height: 44)
            if showHint {
                hintBody
            } else {
                pages.frame(height: 144)
                statusLine.frame(height: 18)
                pageIndicator.frame(height: 12)
                primaryRow.frame(height: 55)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, KeyboardChromeLayout.horizontalInset)
        .frame(maxWidth: .infinity)
        .frame(height: KeyboardChromeLayout.totalHeight)
        .padding(.bottom, 24)
    }

    private var topBar: some View {
        HStack {
            Text("OSG")
                .font(.system(size: 17, weight: .heavy, design: .rounded))
                .foregroundStyle(palette.accent)
            Spacer(minLength: 0)
            Image(systemName: "xmark")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(palette.textPrimary)
                .frame(width: 44, height: 44)
                .background(palette.surfaceElevated.opacity(0.72), in: Circle())
        }
        // keyboardPanel already contributes 8pt; add the nested 4pt so the
        // effective top-bar inset matches the normal voice surface's 12pt.
        .padding(.horizontal, Spacing.xs)
    }

    // Opening frame: idle mic + "长按可编辑上一条" hint.
    private var hintBody: some View {
        VStack(spacing: Spacing.sm) {
            Spacer(minLength: 0)
            Text("长按可编辑上一条")
                .font(TypeStyle.footnote)
                .foregroundStyle(palette.accent)
            ZStack {
                Circle().fill(palette.accent)
                Image(systemName: "mic.fill")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 64, height: 64)
            .shadow(color: palette.accentGlow, radius: 12)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var pages: some View {
        EditTextPager(
            originalTitle: "原文",
            originalText: Self.originalText,
            editedTitle: "编辑后",
            editedText: editSession.review?.resultText,
            selectedPage: $selectedPage
        )
    }

    private var statusLine: some View {
        Text(statusText)
            .font(TypeStyle.caption2)
            .foregroundStyle(palette.textSecondary)
            .lineLimit(1)
            .frame(maxWidth: .infinity)
    }

    private var pageIndicator: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(selectedPage != 1 ? palette.textPrimary : palette.textTertiary.opacity(0.45))
                .frame(width: 5, height: 5)
            Circle()
                .fill(selectedPage == 1 ? palette.textPrimary : palette.textTertiary.opacity(0.45))
                .frame(width: 5, height: 5)
        }
        .opacity(editSession.review == nil ? 0 : 1)
    }

    private var primaryRow: some View {
        HStack(spacing: Spacing.sm) {
            helperText(leftHelper)
            ZStack {
                Capsule().fill(palette.accent)
                primaryIcon
            }
            .frame(width: 150, height: 50)
            helperText(rightHelper)
        }
    }

    private func helperText(_ value: String) -> some View {
        Text(value)
            .font(TypeStyle.caption2)
            .foregroundStyle(palette.textSecondary.opacity(0.55))
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.75)
            .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var primaryIcon: some View {
        switch editSession {
        case .processing, .applying, .appending:
            ProgressView().tint(.white)
        case .review:
            Image(systemName: "checkmark")
                .font(.system(size: 21, weight: .bold))
                .foregroundStyle(.white)
        case .listening:
            VStack(spacing: 0) {
                Text(formatRemaining(remainingSeconds))
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Image(systemName: "mic.fill")
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundStyle(.white)
        default:
            Image(systemName: "mic.fill")
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(.white)
        }
    }

    // MARK: - Copy (mirrors ExtL10n zh keyboard.edit.*)

    private var statusText: String {
        switch editSession {
        case .listening:  return "正在聆听编辑指令"
        case .processing: return "正在编辑…"
        case .review:     return "左右滑动对比原文和结果"
        case .applying, .appending: return "正在应用编辑…"
        default:          return ""
        }
    }

    private var leftHelper: String {
        editSession.review == nil ? "说话编辑文字" : "左右滑动对比"
    }

    private var rightHelper: String {
        editSession.review != nil ? "点击应用编辑" : "点击完成编辑"
    }

    private func formatRemaining(_ seconds: Int) -> String {
        "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
    }

    // MARK: - Scripted timeline

    private func runTimeline() async {
        let src = source
        let review = EditReview(source: src, resultText: Self.editedText, utteranceID: UUID())

        try? await sleep(1.3) // idle hint

        withAnimation(.easeInOut(duration: 0.25)) {
            showHint = false
            editSession = .listening(src)
        }
        // Tick the utterance countdown while listening.
        for _ in 0..<3 {
            try? await sleep(0.5)
            remainingSeconds -= 1
        }

        withAnimation(.easeInOut(duration: 0.2)) { editSession = .processing(src) }
        try? await sleep(1.3)

        withAnimation(.easeInOut(duration: 0.25)) {
            editSession = .review(review)
            selectedPage = 0
        }
        try? await sleep(1.1)

        withAnimation(.interactiveSpring(response: 0.34, dampingFraction: 0.86)) {
            selectedPage = 1
        }
        try? await sleep(1.6)

        withAnimation(.easeInOut(duration: 0.2)) { editSession = .applying(review) }
        try? await sleep(0.9)
    }

    private func sleep(_ seconds: Double) async throws {
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }
}
#endif
