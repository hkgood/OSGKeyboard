// AIKeyboardView.swift
// OSGKeyboard · Keyboard Extension
//
// Product voice-to-AI conversation surface. The latest answer remains visible
// while a follow-up runs and is inserted only through the explicit Send action.

import SwiftUI
import OSGKeyboardShared

struct AIKeyboardView: View {
    private enum Layout {
        static let contentHeight: CGFloat = 174
        static let actionRowHeight: CGFloat = 55
        static let actionButtonHeight: CGFloat = 50
        static let actionButtonMaxWidth: CGFloat = 150
        static let statusHeight: CGFloat = 20
        static let carouselInterval: TimeInterval = 4
        static let skillButtonSize: CGFloat = 52
    }

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var state: KeyboardState
    @ObservedObject var typing: TypingSessionController
    /// A copy made while the keyboard is visible must reach the carousel
    /// immediately, not on the next rotation tick.
    @ObservedObject private var clipboardHistory = ClipboardHistoryStore.shared
    let onInsert: (String) -> Void

    @State private var currentHint: AIHintCard?
    @State private var hintOpacity: Double = 1
    @State private var carouselBag = AIHintCarouselBag()
    @State private var poolCards: [AIHintCard] = []

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
        .onAppear { resetCarousel() }
        .onChange(of: state.aiSession.phase) { _, phase in
            guard phase == .idle || phase == .failed else { return }
            resetCarousel()
        }
        .onChange(of: state.clipboardHistoryEnabled) { _, _ in resetCarousel() }
        .onChange(of: clipboardHistory.entries.first?.id) { _, _ in resetCarousel() }
        .onChange(of: state.enabledClipboardSkillIDs) { _, _ in resetCarousel() }
        .onChange(of: state.skillTipText) { _, tip in
            guard let tip, !tip.isEmpty else { return }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 2_800_000_000)
                if state.skillTipText == tip {
                    state.skillTipText = nil
                }
            }
        }
        .animation(Motion.soft, value: state.skillTipText)
        .onReceive(
            Timer.publish(every: Layout.carouselInterval, on: .main, in: .common).autoconnect()
        ) { _ in
            guard showsPlaceholder else { return }
            // Reduce Motion stops the rotation, not the data: a card whose
            // clipboard window has closed must still leave the carousel.
            reloadHintPool(resetBag: false)
            guard !showsClipboardSkills else { return }
            if reduceMotion, let hint = currentHint,
               poolCards.contains(where: { $0.id == hint.id }) {
                return
            }
            showNextHint(animated: !reduceMotion)
        }
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
        } else if state.canShowClipboardEntry,
                  let suggestion = state.clipboardSuggestionText,
                  !suggestion.isEmpty {
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
                if showsClipboardSkills {
                    clipboardSkillRow
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    hintCarousel
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
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

            if let tip = state.skillTipText, !tip.isEmpty {
                Text(tip)
                    .font(TypeStyle.caption)
                    .foregroundStyle(palette.textPrimary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .glassEffect(.regular, in: Capsule())
                    .padding(.bottom, Layout.statusHeight + Spacing.sm)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
    }

    private var hintCarousel: some View {
        Button {
            guard let hint = currentHint else { return }
            state.submitAIHint(hint)
        } label: {
            HStack(spacing: 6) {
                if let hint = currentHint {
                    Image(systemName: hint.visualKind.systemImage)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(palette.textPrimary.opacity(0.55))
                }
                Text(currentHint.map(\.resolvedDisplayText) ?? ExtL10n.string("keyboard.ai.placeholder"))
                    .font(TypeStyle.bodyEmph)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .padding(.horizontal, 16)
            .frame(height: 44)
            .opacity(hintOpacity)
            .glassEffect(.regular.interactive(), in: Capsule())
        }
        .buttonStyle(.plain)
        .fixedSize()
        // A busy session already owns the surface; the status line explains a
        // missing LLM. Both keep the hint from being a tap with no outcome.
        .disabled(currentHint == nil || !state.aiServiceAvailable || state.aiSession.isBusy)
        .accessibilityLabel(
            Text(
                currentHint.map {
                    "\(ExtL10n.string("keyboard.ai.hintA11yPrefix"))\($0.resolvedDisplayText)"
                } ?? ExtL10n.string("keyboard.ai.placeholder")
            )
        )
    }

    private var clipboardSkillRow: some View {
        let skills = visibleClipboardSkills
        let row = HStack(spacing: Spacing.lg) {
            ForEach(skills) { skill in
                Button {
                    state.submitAIClipboardSkill(skill)
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: skill.systemImage)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(palette.textPrimary.opacity(0.85))
                            .frame(width: Layout.skillButtonSize, height: Layout.skillButtonSize)
                            .glassEffect(.regular.interactive(), in: Circle())
                        Text(clipboardSkillTitle(skill))
                            .font(TypeStyle.caption2)
                            .foregroundStyle(palette.textSecondary)
                    }
                }
                .buttonStyle(.plain)
                .disabled(!state.aiServiceAvailable || state.aiSession.isBusy)
                .accessibilityLabel(Text(clipboardSkillTitle(skill)))
            }
        }
        return Group {
            if skills.count > 4 {
                ScrollView(.horizontal, showsIndicators: false) {
                    row.padding(.horizontal, Spacing.md)
                }
            } else {
                row
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Translate follows the keyboard target; Reply / Summarize stay static.
    private func clipboardSkillTitle(_ skill: AIClipboardSkill) -> String {
        if skill.id == AIClipboardSkillCatalog.translateID {
            return AIClipboardSkillCatalog.translateButtonTitle(
                translationTargetLocaleId: state.translationTargetLocaleId,
                uiLanguage: AppGroupStore().uiLanguage
            )
        }
        return ExtL10n.string(skill.titleKey)
    }

    /// Copy-then-30s window: skill chips replace the rotating hint.
    private var showsClipboardSkills: Bool {
        guard showsPlaceholder, state.clipboardHistoryEnabled else { return false }
        guard !visibleClipboardSkills.isEmpty else { return false }
        return AIHintPool.isClipboardSkillWindowActive(
            clipboardHistoryEnabled: true,
            newestClipboard: clipboardHistory.newestEntry
        )
    }

    private var visibleClipboardSkills: [AIClipboardSkill] {
        AIClipboardSkillCatalog.visible(enabledIDs: state.enabledClipboardSkillIDs)
    }

    /// No draft/answer yet — show the centered hint carousel instead of a scroll body.
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
                Color.clear
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
            // 实心填充、无外扩阴影：避免玻璃投影被键盘底边裁切。
            .background(palette.accent, in: Capsule())
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
            // 实心填充、无外扩阴影：避免玻璃投影被键盘底边裁切。
            .background(answerActionFill, in: Capsule())
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
            return palette.surfaceElevated.opacity(0.55)
        }
        return state.aiSession.canSend
            ? palette.accent
            : palette.surfaceElevated
    }

    private var answerActionForeground: Color {
        guard state.aiSession.canPerformAnswerAction else {
            return palette.textTertiary
        }
        return state.aiSession.canSend
            ? .white
            : NativeKeyboardKeyColors.text(for: colorScheme)
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
            if state.aiSession.transcript.isEmpty
                || AIClipboardPrompt.isInternalPrompt(state.aiSession.transcript) {
                return ExtL10n.string("keyboard.ai.recognizing")
            }
            return state.aiSession.transcript
        case .generating:
            if state.pendingClipboardSkillID == AIClipboardSkillCatalog.extractTodosID {
                return ExtL10n.string("keyboard.ai.skill.extracting")
            }
            if let draft = state.aiSession.draftAnswerText, !draft.isEmpty {
                return ExtL10n.string("keyboard.ai.generating")
            }
            if state.aiSession.transcript.isEmpty
                || AIClipboardPrompt.isInternalPrompt(state.aiSession.transcript) {
                return ExtL10n.string("keyboard.ai.thinking")
            }
            return state.aiSession.transcript
        case .failed:
            return ExtL10n.string("keyboard.ai.error.requestFailed")
        }
    }

    private var microphoneAccessibilityKey: String {
        state.aiSession.phase == .listening
            ? "keyboard.ai.stopA11y"
            : "keyboard.ai.startA11y"
    }

    // MARK: - Carousel

    /// Rebuild the pool and show a card right away, without a fade.
    /// Skip advancing the chip while clipboard skills own the surface, so a
    /// leftover clipboard sentence cannot replace the three buttons.
    private func resetCarousel() {
        reloadHintPool(resetBag: true)
        guard !showsClipboardSkills else { return }
        showNextHint(animated: false)
    }

    private func reloadHintPool(resetBag: Bool) {
        let locale = AIHintLocaleResolver.packLocale()
        let pack = AIHintStore.resolvedPack(locale: locale)
        poolCards = AIHintPool.activeCards(pack: pack)
        if resetBag {
            carouselBag.reset()
        }
    }

    private func showNextHint(animated: Bool) {
        guard let next = carouselBag.next(from: poolCards) else {
            currentHint = nil
            return
        }
        if animated, !reduceMotion {
            withAnimation(Motion.soft) { hintOpacity = 0 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                currentHint = next
                withAnimation(Motion.soft) { hintOpacity = 1 }
            }
        } else {
            currentHint = next
            hintOpacity = 1
        }
    }
}
