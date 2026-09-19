// AIKeyboardView.swift
// OSGKeyboard · Keyboard Extension
//
// Unified assistant surface: tap for ordinary dictation, hold for AI, and use
// the same idle layout for hotwords, clipboard skills, editing, and Send.

import OSGKeyboardShared
import SwiftUI

struct AIKeyboardView: View {
    private enum Layout {
        static let topBarHeight: CGFloat = 44
        static let primaryHeight: CGFloat = 60
        static let primaryWidth: CGFloat = 156
        static let compactPrimaryHeight: CGFloat = 56
        static let compactPrimaryWidth: CGFloat = 148
        static let secondaryHeight: CGFloat = 52
        static let fieldActionWidth: CGFloat = 132
        static let compactIPadFieldActionWidth: CGFloat = 112
        static let circleSize: CGFloat = 48
        static let compactIPadCircleSize: CGFloat = 44
        static let sideButtonEdgeInset: CGFloat = 8
        static let actionClusterMaxWidth: CGFloat = 430
        static let primaryToSecondaryGap: CGFloat = 25
        static let hotwordHeight: CGFloat = 28
        static let hotwordMaxWidth: CGFloat = 180
        static let skillTipMaxWidth: CGFloat = 300
        /// The 30 pt tab sits inside a 44 pt top bar. Half of its bottom inset
        /// belongs visually to the label-to-tab gap, so compensate by 3.5 pt.
        static let contextVisualOffset: CGFloat = -3.5
        static let carouselInterval: TimeInterval = 4
        static let skillButtonSize: CGFloat = 48
        static let skillCellWidth: CGFloat = 60
        static let skillCellSpacing: CGFloat = 10
        static let pageDotSize: CGFloat = 5
        static let skillPaginationBottomInset: CGFloat = 6
        static let maximumSemanticSkills = 5
    }

    private struct SemanticBadgeContent {
        let intentKey: String?
        let domainKey: String?

        var text: String {
            [intentKey, domainKey]
                .compactMap { $0 }
                .map { ExtL10n.string($0) }
                .joined(separator: " · ")
        }
    }

    #if DEBUG
    /// Layout preview for `--ai-skills-demo`. Nil keeps production clipboard-window gating.
    static var debugPreviewSkills: [AIClipboardSkill]?
    /// Deterministic intent/domain labels for the assistant UI harness.
    static var debugPreviewSemanticBadgeKeys: (intent: String?, domain: String?)?
    /// Keeps the deterministic UI harness on the tappable idle hint.
    static var debugSkipsLongPressCoach = false
    /// Prevents deterministic feedback previews from expiring mid-assertion.
    static var debugKeepsSkillTip = false
    #endif

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var state: KeyboardState
    @ObservedObject var typing: TypingSessionController
    @ObservedObject private var clipboardHistory = ClipboardHistoryStore.shared
    @ObservedObject private var semanticRanking = ClipboardSemanticRankingStore.shared
    let onInsert: (String) -> Void

    @AppStorage("keyboard.assistant.longPressCoachCount")
    private var longPressCoachCount = 0
    @State private var showsLongPressCoach = false
    @State private var currentHint: AIHintCard?
    @State private var hintOpacity: Double = 1
    @State private var carouselBag = AIHintCarouselBag()
    @State private var poolCards: [AIHintCard] = []
    @State private var selectedSkillPage = 0
    @State private var debugSkillsDismissed = false
    @State private var micLongPressConsumed = false
    @State private var micIsHoldingForAI = false
    @State private var fieldActionConfirmationVisible = false

    private var palette: ThemePalette {
        colorScheme == .dark ? Palette.dark : Palette.light
    }

    var body: some View {
        Group {
            if state.editSession.isActive {
                LastInputEditView(state: state)
            } else if state.aiSession.canSelectReplyVariant {
                replyVariantsSurface
            } else if state.aiSession.canInsert {
                pendingAnswerSurface
            } else {
                assistantSurface
            }
        }
        .overlay(alignment: .topLeading) {
            Color.clear
                .frame(width: 1, height: 1)
                .accessibilityElement()
                .accessibilityIdentifier("assistant.surface")
                .accessibilityLabel(ExtL10n.text("keyboard.tab.ai"))
                .allowsHitTesting(false)
        }
        .environment(\.themePalette, palette)
        .onAppear {
            resetCarousel()
            if shouldShowLongPressCoach, longPressCoachCount < 3 {
                showsLongPressCoach = true
                longPressCoachCount += 1
            }
        }
        .onChange(of: state.aiSession.phase) { _, phase in
            if phase == .idle || phase == .failed || phase == .inserted || phase == .sent {
                resetCarousel()
            }
        }
        .onChange(of: state.clipboardHistoryEnabled) { _, _ in resetCarousel() }
        .onChange(of: clipboardHistory.entries.first?.id) { _, _ in
            state.dismissedClipboardSkillEntryID = nil
            debugSkillsDismissed = false
            selectedSkillPage = 0
            resetCarousel()
        }
        .onChange(of: state.clipboardSkillCatalog) { _, _ in
            selectedSkillPage = 0
            resetCarousel()
        }
        .onChange(of: semanticRanking.snapshot) { _, _ in
            selectedSkillPage = 0
        }
        .onChange(of: state.skillTipText) { _, tip in
            guard let tip, !tip.isEmpty else { return }
            #if DEBUG
            guard !Self.debugKeepsSkillTip else { return }
            #endif
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(2_800))
                if state.skillTipText == tip {
                    state.skillTipText = nil
                }
            }
        }
        .animation(Motion.soft, value: state.skillTipText)
        .onReceive(
            Timer.publish(every: Layout.carouselInterval, on: .main, in: .common).autoconnect()
        ) { _ in
            guard assistantIsResting else { return }
            reloadHintPool(resetBag: false)
            guard !showsClipboardSkills, !showsLongPressCoach else { return }
            if reduceMotion, let hint = currentHint,
               poolCards.contains(where: { $0.id == hint.id }) {
                return
            }
            showNextHint(animated: !reduceMotion)
        }
    }

    private var shouldShowLongPressCoach: Bool {
        #if DEBUG
        return !Self.debugSkipsLongPressCoach
        #else
        return true
        #endif
    }

    private var assistantSurface: some View {
        VStack(spacing: 0) {
            topBar.frame(height: Layout.topBarHeight)
            // This flexible slot is exactly the gap between the top tabs and
            // microphone. Centering its content guarantees equal whitespace
            // above and below labels on both phone and iPad heights.
            contextArea
                .frame(maxHeight: .infinity)
                .offset(y: Layout.contextVisualOffset)
            primaryActionRow.frame(height: Layout.primaryHeight)
            Color.clear.frame(height: Layout.primaryToSecondaryGap)
            secondaryActionRow.frame(height: Layout.secondaryHeight)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, KeyboardChromeLayout.horizontalInset)
        .frame(maxWidth: KeyboardChromeLayout.voiceContentMaxWidth)
        .frame(maxWidth: .infinity)
        .frame(height: resolvedHeight)
    }

    private var pendingAnswerSurface: some View {
        VStack(spacing: 0) {
            topBar.frame(height: Layout.topBarHeight)
            if state.autoResultReadOnly {
                // Auto-translate / email-reply stay staged: the result is shown,
                // and lands in the field via the labeled liquid-glass button.
                ScrollView(.vertical) {
                    Text(state.aiSession.answer?.text ?? "")
                        .font(TypeStyle.body)
                        .foregroundStyle(palette.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(.horizontal, Spacing.md)
                        .padding(.vertical, Spacing.sm)
                }
                .scrollIndicators(.visible)

                Button(action: state.confirmPendingAIAnswer) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down.to.line")
                            .font(TypeStyle.body.weight(.semibold))
                        ExtL10n.text(state.autoResultInsertLabelKey)
                            .font(TypeStyle.body.weight(.semibold))
                    }
                    .foregroundStyle(palette.textPrimary)
                    .padding(.horizontal, 22)
                    .frame(height: 44)
                    .glassEffect(.regular.interactive(), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("assistant.autoResult.insert")
                .frame(height: 55)
                .accessibilityLabel(ExtL10n.text(state.autoResultInsertLabelKey))
            } else {
                // A single reply is one tappable liquid-glass card — same style
                // as the multi-variant cards; tapping it inserts.
                ScrollView(.vertical) {
                    pendingAnswerCard
                        .padding(.horizontal, Spacing.xs)
                        .padding(.vertical, Spacing.xs)
                }
                .scrollIndicators(.visible)
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, KeyboardChromeLayout.horizontalInset)
        .frame(maxWidth: KeyboardChromeLayout.voiceContentMaxWidth)
        .frame(maxWidth: .infinity)
        .frame(height: resolvedHeight)
    }

    private var pendingAnswerCard: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.medium)
        return Button(action: state.confirmPendingAIAnswer) {
            HStack(alignment: .top, spacing: Spacing.sm) {
                Text(state.aiSession.answer?.text ?? "")
                    .font(TypeStyle.body)
                    .foregroundStyle(palette.textPrimary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "arrow.down.to.line")
                    .font(TypeStyle.body.weight(.semibold))
                    .foregroundStyle(palette.textSecondary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(shape)
            .glassEffect(
                .regular
                    .tint(palette.textPrimary.opacity(0.04))
                    .interactive(),
                in: shape
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("assistant.pending.insert")
        .accessibilityLabel(Text(state.aiSession.answer?.text ?? ""))
        .accessibilityHint(ExtL10n.text("keyboard.assistant.insertPending"))
    }

    private var replyVariantsSurface: some View {
        VStack(spacing: 0) {
            topBar.frame(height: Layout.topBarHeight)
            ScrollView(.vertical) {
                LazyVStack(spacing: Spacing.xs) {
                    ForEach(state.aiSession.replyVariants) { variant in
                        replyVariantButton(variant)
                    }
                }
                .padding(.horizontal, Spacing.xs)
                .padding(.vertical, Spacing.xs)
            }
            .scrollIndicators(.visible)
            .scrollBounceBehavior(.basedOnSize)
            .accessibilityIdentifier("assistant.replyVariants")
        }
        .padding(.vertical, 4)
        .padding(.horizontal, KeyboardChromeLayout.horizontalInset)
        .frame(maxWidth: KeyboardChromeLayout.voiceContentMaxWidth)
        .frame(maxWidth: .infinity)
        .frame(height: resolvedHeight)
    }

    private func replyVariantButton(_ variant: AIReplyVariant) -> some View {
        let title = ExtL10n.string(variant.kind.titleKey)
        let shape = RoundedRectangle(cornerRadius: Radius.medium)
        return Button {
            state.selectAIReplyVariant(variant.id)
        } label: {
            HStack(alignment: .top, spacing: Spacing.sm) {
                Image(
                    systemName: variant.kind.usesEmotionIcon
                        ? variant.emotion.systemImage(fallback: variant.kind)
                        : variant.kind.systemImage
                )
                    .resizable()
                    .scaledToFit()
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 17, height: 17)
                    .frame(width: 24, height: 24)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(TypeStyle.caption)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                    Text(variant.text)
                        .font(TypeStyle.body)
                        .foregroundStyle(palette.textPrimary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(shape)
            .glassEffect(
                .regular
                    .tint(palette.textPrimary.opacity(0.04))
                    .interactive(),
                in: shape
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("assistant.replyVariant.\(variant.kind.rawValue)")
        .accessibilityLabel(Text("\(title), \(variant.text)"))
        .accessibilityHint(ExtL10n.text("keyboard.ai.replyVariant.insertHint"))
    }

    private var resolvedHeight: CGFloat {
        TypingSurfaceMetrics.contentHeight(
            isIPad: state.usesIPadLayoutMetrics,
            width: state.layoutWidth
        )
    }

    // MARK: - Top bar

    @ViewBuilder
    private var topBar: some View {
        if state.aiSession.canInsert || state.aiSession.canSelectReplyVariant {
            cancelTopBar(
                action: state.discardPendingAIAnswer,
                labelKey: "keyboard.assistant.discardPending",
                hintKey: "keyboard.assistant.discardPendingHint"
            )
        } else if state.canCancelAIInput {
            cancelTopBar(
                action: state.cancelAIInput,
                labelKey: "keyboard.ai.cancel",
                hintKey: "keyboard.ai.cancelHint"
            )
        } else if state.canCancelVoiceInput {
            cancelTopBar(
                action: state.cancelVoiceInput,
                labelKey: "keyboard.voice.cancel",
                hintKey: "keyboard.voice.cancelHint"
            )
        } else if showsClipboardSkillBar {
            // Fresh copy, no AI result yet: the top bar becomes the skill entry
            // point (paste + every applicable skill + dismiss).
            clipboardSkillTopBar
        } else if showsClipboardSkills {
            // OOBE / debug chip pager keeps its dismiss bar.
            cancelTopBar(
                action: dismissClipboardPresentation,
                labelKey: "keyboard.assistant.dismissClipboard",
                hintKey: "keyboard.assistant.dismissClipboardHint"
            )
        } else {
            ZStack {
                KeyboardTopControls(
                    state: state,
                    typing: typing,
                    palette: palette,
                    onInsert: onInsert
                )
                HStack {
                    leadingBrandOrPaste
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, KeyboardTopBarMetrics.nestedHorizontalInset)
        }
    }

    /// Fresh-copy top bar (no active result): paste + scrollable skills + dismiss.
    private var clipboardSkillTopBar: some View {
        HStack(spacing: 6) {
            leadingScrollRow
            KeyboardCancelButton(
                action: dismissClipboardPresentation,
                accessibilityLabel: ExtL10n.text("keyboard.assistant.dismissClipboard"),
                accessibilityHint: ExtL10n.text("keyboard.assistant.dismissClipboardHint"),
                accessibilityIdentifier: "assistant.clipboard.dismiss"
            )
        }
        .padding(.horizontal, KeyboardTopBarMetrics.nestedHorizontalInset)
    }

    /// Fresh copy with applicable skills and no active AI result to defer to.
    private var showsClipboardSkillBar: Bool {
        guard assistantIsResting,
              state.oobePracticeSession == nil,
              state.clipboardHistoryEnabled,
              state.aiServiceAvailable,
              !state.aiSession.canInsert,
              !state.aiSession.canSelectReplyVariant,
              let newest = clipboardHistory.newestEntry,
              newest.id != state.dismissedClipboardSkillEntryID,
              !topBarSkills.isEmpty else {
            return false
        }
        return AIHintPool.isClipboardSkillWindowActive(
            clipboardHistoryEnabled: true,
            newestClipboard: newest
        )
    }

    /// The top-bar leading slot: a "Paste" glass capsule whenever a fresh copy is
    /// available (replacing the OSG logo), otherwise the logo itself. Copying is
    /// frequent, so this keeps a one-tap paste always in the same spot without a
    /// full-width suggestion strip.
    @ViewBuilder
    private var leadingBrandOrPaste: some View {
        if shouldShowClipboardSuggestion {
            pasteCapsule
        } else {
            KeyboardBrandLogo(action: state.openSettings)
        }
    }

    private var pasteCapsule: some View {
        Button(action: insertClipboardSuggestion) {
            Text(ExtL10n.string("keyboard.clipboard.paste"))
                .font(TypeStyle.footnote.weight(.semibold))
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1)
                .padding(.horizontal, 14)
                .frame(height: 30)
                .glassEffect(.regular.interactive(), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("assistant.clipboard.paste")
        .accessibilityLabel(ExtL10n.text("keyboard.clipboard.paste"))
    }

    private func cancelTopBar(
        action: @escaping () -> Void,
        labelKey: String,
        hintKey: String
    ) -> some View {
        HStack(spacing: 6) {
            // Paste + every applicable skill scroll together; the X stays put.
            leadingScrollRow
            KeyboardCancelButton(
                action: action,
                accessibilityLabel: ExtL10n.text(labelKey),
                accessibilityHint: ExtL10n.text(hintKey),
                accessibilityIdentifier: cancelIdentifier(for: labelKey)
            )
        }
        .padding(.horizontal, KeyboardTopBarMetrics.nestedHorizontalInset)
    }

    /// Leading region of the clipboard top bars: the OSG logo when there's no
    /// fresh copy, otherwise a horizontally scrollable row whose first item is the
    /// Paste capsule followed by every applicable skill — so Paste scrolls along
    /// with the skills instead of staying pinned.
    @ViewBuilder
    private var leadingScrollRow: some View {
        let paste = shouldShowClipboardSuggestion
        let skills = topBarSkills
        HStack(spacing: 6) {
            if !paste {
                KeyboardBrandLogo(action: state.openSettings)
            }
            if paste || !skills.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        if paste {
                            pasteCapsule
                        }
                        ForEach(skills) { skill in
                            otherSkillCapsule(skill)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .scrollClipDisabled()
            } else {
                Spacer(minLength: 0)
            }
        }
    }

    private func otherSkillCapsule(_ skill: AIClipboardSkill) -> some View {
        Button {
            state.submitAIClipboardSkill(skill, replyScene(for: skill))
        } label: {
            Text(clipboardSkillTitle(skill))
                .font(TypeStyle.footnote.weight(.semibold))
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .frame(height: 30)
                .glassEffect(.regular.interactive(), in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!state.aiServiceAvailable || state.aiSession.isBusy)
        .accessibilityIdentifier("assistant.otherSkill.\(skill.id)")
        .accessibilityLabel(Text(clipboardSkillTitle(skill)))
    }

    /// Skills that apply to the current copy, most-relevant first. This is the
    /// sole skill entry point now that the circular chips are gone; it shows with
    /// or without an active result (the invoked skill is excluded when active).
    ///
    /// Purely relevance-ranked: a skill appears only when its signal is present
    /// (a URL → Open / Summarize page; a phone → Call; a date/list → Events /
    /// Todos / Organize; long text → Summary; plus Reply as the message baseline).
    /// No blanket fallback, so Summary / Organize / Events / Notes do NOT show on
    /// an ordinary short message.
    private var topBarSkills: [AIClipboardSkill] {
        guard state.oobePracticeSession == nil,
              state.aiServiceAvailable,
              let newest = clipboardHistory.newestEntry else {
            return []
        }
        let translatable = clipboardIsTranslatable
        let activeID = state.activeClipboardSkillID
        func present(_ list: [AIClipboardSkill]) -> [AIClipboardSkill] {
            list.filter {
                $0.id != activeID
                    // Don't offer "Translate" for text already in the user's language.
                    && ($0.id != AIClipboardSkillCatalog.translateID || translatable)
            }
        }
        guard let snapshot = semanticRanking.snapshot,
              snapshot.entryID == newest.id else {
            // Analysis not ready yet — keep Reply reachable in the meantime.
            let reply = state.enabledClipboardSkills.first {
                $0.id == AIClipboardSkillCatalog.replyID
            }
            return present([reply].compactMap { $0 })
        }
        return present(
            ClipboardSkillSemanticRanker.recommended(
                skills: state.enabledClipboardSkills,
                sourceText: newest.text,
                analysis: snapshot.analysis,
                uiLanguage: state.uiLanguage,
                limit: 6
            )
        )
    }

    /// True only when the current copy is in a language other than the user's,
    /// so offering Translate makes sense.
    private var clipboardIsTranslatable: Bool {
        guard let newest = clipboardHistory.newestEntry,
              let snapshot = semanticRanking.snapshot,
              snapshot.entryID == newest.id else {
            return false
        }
        return ClipboardSkillSemanticRanker.isForeignLanguage(snapshot.analysis)
    }

    private func cancelIdentifier(for labelKey: String) -> String {
        switch labelKey {
        case "keyboard.assistant.dismissClipboard":
            return "assistant.clipboard.dismiss"
        case "keyboard.assistant.discardPending":
            return "assistant.pending.discard"
        default:
            return "assistant.cancel"
        }
    }

    // MARK: - Context

    @ViewBuilder
    private var contextArea: some View {
        ZStack {
            if showsOOBEClipboardSkill, activeStatus == nil {
                clipboardSkillPager
            } else if let onboardingPracticeHint, activeStatus == nil {
                Text(onboardingPracticeHint)
                    .font(TypeStyle.footnote.weight(.semibold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                    .padding(.horizontal, 14)
                    .frame(height: Layout.hotwordHeight)
                    .background(palette.accentMuted, in: Capsule())
            } else if let tip = state.skillTipText, !tip.isEmpty {
                IntrinsicWidthCap(maxWidth: Layout.skillTipMaxWidth) {
                    Text(tip)
                        .font(TypeStyle.body)
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .truncationMode(.tail)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .glassEffect(.regular, in: Capsule())
                }
                .accessibilityIdentifier("assistant.skillTip")
            } else if showsClipboardSkills {
                VStack(spacing: Spacing.xs) {
                    if let content = semanticBadgeContent {
                        semanticBadge(content)
                    }
                    clipboardSkillPager
                }
            } else if let content = semanticBadgeContent {
                semanticBadge(content)
            } else if let status = activeStatus {
                statusText(status.text, color: status.color)
            } else if showsLongPressCoach {
                Text(ExtL10n.string("keyboard.assistant.longPressCoach"))
                    .font(TypeStyle.footnote.weight(.medium))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
                    .padding(.horizontal, 14)
                    .frame(height: Layout.hotwordHeight)
                    .overlay(Capsule().stroke(palette.dividerStrong, lineWidth: 1))
            } else {
                hintCarousel
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Spacing.md)
    }

    private func semanticBadge(_ content: SemanticBadgeContent) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "tag.fill")
                .font(.system(size: 10, weight: .semibold))
                .accessibilityHidden(true)
            Text(content.text)
                .font(TypeStyle.caption.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(palette.textSecondary)
        .padding(.horizontal, 10)
        .frame(height: 24)
        .background(palette.accentMuted, in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("assistant.semantic.badge")
        .accessibilityLabel(Text(content.text))
    }

    private var semanticBadgeContent: SemanticBadgeContent? {
        #if DEBUG
        if let keys = Self.debugPreviewSemanticBadgeKeys {
            return SemanticBadgeContent(
                intentKey: keys.intent,
                domainKey: keys.domain
            )
        }
        #endif
        // Retired alongside the idle skill chips it accompanied: the copy flow now
        // goes straight to an auto result, so no standalone badge is shown.
        return nil
    }

    private func statusText(_ text: String, color: Color) -> some View {
        Text(text)
            .font(TypeStyle.body)
            .foregroundStyle(color)
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity)
    }

    private var activeStatus: (text: String, color: Color)? {
        if let error = state.aiSession.errorMessage,
           !error.isEmpty,
           !ordinaryPipelineIsActive {
            return (error, palette.warning)
        }
        switch state.aiSession.phase {
        case .preparing:
            return (ExtL10n.string("keyboard.placeholder.preparing"), palette.textSecondary)
        case .listening:
            return (
                state.aiSession.transcript.isEmpty
                    ? ExtL10n.string("keyboard.ai.listening")
                    : state.aiSession.transcript,
                palette.textPrimary
            )
        case .recognizing:
            return (
                state.aiSession.transcript.isEmpty
                    ? ExtL10n.string("keyboard.ai.recognizing")
                    : state.aiSession.transcript,
                palette.textSecondary
            )
        case .generating:
            return (aiGeneratingStatus, palette.textSecondary)
        case .inactive, .idle, .ready, .awaitingSend, .inserted, .sent, .failed:
            break
        }

        switch state.phase {
        case .idle:
            if !state.micDisabledHint.isEmpty {
                return (state.micDisabledHint, palette.warning)
            }
            return nil
        case .requestingPermissions:
            return (
                state.lastTranscript.isEmpty
                    ? ExtL10n.string("keyboard.placeholder.preparing")
                    : state.lastTranscript,
                palette.textSecondary
            )
        case .recording:
            return (state.lastTranscript.isEmpty ? " " : state.lastTranscript, palette.textPrimary)
        case .processing:
            return (
                state.lastTranscript.isEmpty
                    ? ExtL10n.string("keyboard.placeholder.processing")
                    : state.lastTranscript,
                palette.textSecondary
            )
        case .error(_, let message):
            return (message ?? ExtL10n.string("keyboard.placeholder.error"), palette.warning)
        case .denied(let reason):
            let key = reason == .mic ? "keyboard.denied.mic" : "keyboard.denied.speech"
            return (ExtL10n.string(key), palette.warning)
        }
    }

    private var aiGeneratingStatus: String {
        switch state.pendingClipboardSkillID {
        case AIClipboardSkillCatalog.extractTodosID:
            return ExtL10n.string("keyboard.ai.skill.extracting")
        case AIClipboardSkillCatalog.extractEventsID:
            return ExtL10n.string("keyboard.ai.skill.extractingEvents")
        case AIClipboardSkillCatalog.navigateID:
            return ExtL10n.string("keyboard.ai.skill.extractingAddress")
        case AIClipboardSkillCatalog.saveToNotesID:
            return ExtL10n.string("keyboard.ai.skill.namingNote")
        default:
            if !state.aiSession.transcript.isEmpty,
               !AIClipboardPrompt.isInternalPrompt(state.aiSession.transcript) {
                return state.aiSession.transcript
            }
            return ExtL10n.string("keyboard.ai.thinking")
        }
    }

    private var hintCarousel: some View {
        IntrinsicWidthCap(maxWidth: Layout.hotwordMaxWidth) {
            Button {
                guard let hint = currentHint else { return }
                state.submitAIHint(hint)
            } label: {
                HStack(spacing: 6) {
                    if let hint = currentHint {
                        Image(systemName: hint.visualKind.systemImage)
                            .font(TypeStyle.footnote.weight(.semibold))
                    }
                    Text(currentHint.map(\.resolvedDisplayText)
                        ?? ExtL10n.string("keyboard.ai.placeholder"))
                        .font(TypeStyle.footnote.weight(.medium))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .foregroundStyle(palette.textSecondary)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity)
                .frame(height: Layout.hotwordHeight)
                .contentShape(Capsule())
                .overlay(Capsule().stroke(palette.dividerStrong, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .contentShape(Capsule())
            .disabled(currentHint == nil || !state.aiServiceAvailable || !assistantIsResting)
            .accessibilityIdentifier("assistant.hint")
            .accessibilityLabel(
                Text(currentHint.map(\.resolvedDisplayText)
                    ?? ExtL10n.string("keyboard.ai.placeholder"))
            )
        }
        .opacity(hintOpacity)
        .contentShape(Capsule())
    }

    // MARK: - Clipboard skills

    private var clipboardSkillPager: some View {
        GeometryReader { proxy in
            let skillsPerPage = proxy.size.width < 352 ? 4 : 5
            let pages = skillPages(from: visibleClipboardSkills, count: skillsPerPage)
            VStack(spacing: 5) {
                TabView(selection: $selectedSkillPage) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { page, skills in
                        HStack(spacing: Layout.skillCellSpacing) {
                            ForEach(skills) { skill in
                                skillChip(skill)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .tag(page)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .accessibilityIdentifier("assistant.skills.pager")

                HStack(spacing: Layout.pageDotSize) {
                    ForEach(pages.indices, id: \.self) { page in
                        Circle()
                            .fill(page == selectedSkillPage
                                ? palette.textPrimary
                                : palette.textTertiary.opacity(0.45))
                            .frame(width: Layout.pageDotSize, height: Layout.pageDotSize)
                    }
                }
                .opacity(pages.count > 1 ? 1 : 0)
                .accessibilityHidden(true)
            }
            .padding(.bottom, Layout.skillPaginationBottomInset)
        }
    }

    private func skillPages(
        from skills: [AIClipboardSkill],
        count: Int
    ) -> [[AIClipboardSkill]] {
        stride(from: 0, to: skills.count, by: count).map { start in
            Array(skills[start ..< min(start + count, skills.count)])
        }
    }

    private func skillChip(_ skill: AIClipboardSkill) -> some View {
        Button {
            state.submitAIClipboardSkill(skill, replyScene(for: skill))
        } label: {
            VStack(spacing: 6) {
                Image(systemName: skill.systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(palette.textPrimary.opacity(0.85))
                    .frame(width: Layout.skillButtonSize, height: Layout.skillButtonSize)
                    .glassEffect(.regular.interactive(), in: Circle())
                Text(clipboardSkillTitle(skill))
                    .font(TypeStyle.caption)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(width: Layout.skillCellWidth)
        }
        .buttonStyle(.plain)
        .disabled(!state.aiServiceAvailable || state.aiSession.isBusy)
        .accessibilityIdentifier("assistant.skill.\(skill.id)")
        .accessibilityLabel(Text(clipboardSkillTitle(skill)))
    }

    private func replyScene(for skill: AIClipboardSkill) -> AIClipboardReplyScene? {
        guard skill.id == AIClipboardSkillCatalog.replyID,
              state.oobePracticeSession == nil,
              let newest = clipboardHistory.newestEntry,
              let snapshot = semanticRanking.snapshot,
              snapshot.entryID == newest.id else {
            return nil
        }
        return AIClipboardReplyScene.resolve(
            from: snapshot.analysis,
            sourceText: newest.text
        )
    }

    private func clipboardSkillTitle(_ skill: AIClipboardSkill) -> String {
        // Capsules stay short: use the plain skill title, not the verbose
        // "Translate to <language>" form.
        if let custom = skill.customName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !custom.isEmpty {
            return custom
        }
        return ExtL10n.string(skill.titleKey)
    }

    private var showsClipboardSkills: Bool {
        #if DEBUG
        if let preview = Self.debugPreviewSkills,
           !preview.isEmpty,
           !debugSkillsDismissed {
            return assistantIsResting
        }
        #endif
        if showsOOBEClipboardSkill {
            return assistantIsResting
        }
        // The idle circular skill chips are retired: auto mode runs one skill and
        // the result panel's top-bar capsules offer the rest. Only OOBE / debug
        // still present the chip pager above.
        return false
    }

    private var visibleClipboardSkills: [AIClipboardSkill] {
        #if DEBUG
        if let preview = Self.debugPreviewSkills, !preview.isEmpty {
            return preview
        }
        #endif
        if let expectedSkillID = oobeExpectedSkillID {
            return AIClipboardSkillCatalog.catalog.filter { $0.id == expectedSkillID }
        }
        guard let newest = clipboardHistory.newestEntry else { return [] }
        guard let snapshot = semanticRanking.snapshot,
              snapshot.entryID == newest.id else {
            return state.clipboardSkillCatalog.filter {
                $0.id == AIClipboardSkillCatalog.replyID
            }
        }
        return ClipboardSkillSemanticRanker.recommended(
            skills: state.clipboardSkillCatalog,
            sourceText: newest.text,
            analysis: snapshot.analysis,
            uiLanguage: state.uiLanguage,
            limit: Layout.maximumSemanticSkills
        )
    }

    private var showsOOBEClipboardSkill: Bool {
        oobeExpectedSkillID != nil
    }

    private var oobeExpectedSkillID: String? {
        switch state.oobePracticeSession?.expectedFeature {
        case .clipboardTranslate:
            return AIClipboardSkillCatalog.translateID
        case .clipboardReply:
            return AIClipboardSkillCatalog.replyID
        case .voiceInput, .askAI, nil:
            return nil
        }
    }

    private var onboardingPracticeHint: String? {
        switch state.oobePracticeSession?.expectedFeature {
        case .voiceInput:
            return ExtL10n.string("keyboard.onboarding.practice.mic")
        case .clipboardTranslate:
            return ExtL10n.string("keyboard.onboarding.practice.translate")
        case .clipboardReply:
            return ExtL10n.string("keyboard.onboarding.practice.reply")
        case .askAI:
            return ExtL10n.string("keyboard.onboarding.practice.askAI")
        case nil:
            return state.isOnboardingPracticeActive
                ? ExtL10n.string("keyboard.onboarding.practice.mic")
                : nil
        }
    }

    // MARK: - Primary actions

    private var primaryActionRow: some View {
        ZStack {
            HStack {
                primarySideButton(leading: true)
                    .offset(x: Layout.sideButtonEdgeInset)
                Spacer(minLength: 0)
                primarySideButton(leading: false)
                    .offset(x: -Layout.sideButtonEdgeInset)
            }
            .opacity(sideButtonsVisible ? 1 : 0)
            .allowsHitTesting(sideButtonsVisible)
            .accessibilityHidden(!sideButtonsVisible)

            microphoneButton
        }
        .frame(maxWidth: Layout.actionClusterMaxWidth)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func primarySideButton(leading: Bool) -> some View {
        let swapped = state.handednessPreference.swapsActionKeys
        let showsSpace = leading ? swapped : !swapped
        if showsSpace {
            circleActionButton(
                systemName: "space",
                label: ExtL10n.string("keyboard.assistant.space"),
                action: state.insertSpace
            )
            .accessibilityIdentifier("assistant.space")
        } else {
            repeatingDeleteButton
        }
    }

    private var microphoneButton: some View {
        ZStack {
            Capsule()
                .fill(.clear)
                .glassEffect(
                    .regular.tint(microphoneTint).interactive(),
                    in: Capsule()
                )
            microphoneContent
        }
        .frame(width: primaryButtonWidth, height: primaryButtonHeight)
        .contentShape(Capsule())
        .scaleEffect(microphoneIsPressable ? 1 : 0.99)
        .onLongPressGesture(
            minimumDuration: 0.45,
            maximumDistance: 120,
            pressing: handleMicrophonePressing,
            perform: beginAIMicrophone
        )
        // Processing is an explicit waiting state: the capsule stays visible
        // for feedback but must not react to taps or Liquid Glass presses.
        .allowsHitTesting(microphoneIsPressable)
        .accessibilityElement()
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("assistant.mic.\(microphoneStateIdentifier)")
        .accessibilityLabel(ExtL10n.text("keyboard.assistant.micA11y"))
        .accessibilityHint(ExtL10n.text("keyboard.assistant.micHint"))
        .accessibilityAction(named: ExtL10n.text("keyboard.assistant.dictationAction")) {
            guard microphoneIsPressable else { return }
            state.tapMic()
        }
        .accessibilityAction(named: ExtL10n.text("keyboard.assistant.aiAction")) {
            guard assistantIsResting else { return }
            state.tapAIMic()
        }
        .disabled(!microphoneIsPressable)
    }

    @ViewBuilder
    private var microphoneContent: some View {
        if state.assistantInsertionSucceeded {
            Image(systemName: "checkmark")
                .font(.system(size: 27, weight: .bold))
                .foregroundStyle(OSGColor.fixedLightContent)
        } else {
            switch state.aiSession.phase {
            case .listening:
                waveform(color: OSGColor.fixedLightContent)
            case .preparing, .recognizing, .generating:
                ProgressView().tint(OSGColor.fixedLightContent)
            case .inactive, .idle, .ready, .awaitingSend, .inserted, .sent, .failed:
                ordinaryMicrophoneContent
            }
        }
    }

    @ViewBuilder
    private var ordinaryMicrophoneContent: some View {
        switch state.phase {
        case .recording:
            waveform(color: OSGColor.recordingWaveform)
        case .requestingPermissions, .processing:
            ProgressView().tint(OSGColor.fixedLightContent)
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 25, weight: .semibold))
                .foregroundStyle(OSGColor.fixedLightContent)
        case .idle, .denied:
            Image(systemName: "mic.fill")
                .font(TypeStyle.title.weight(.semibold))
                .foregroundStyle(OSGColor.fixedLightContent)
                .symbolEffect(.breathe, isActive: micIsHoldingForAI)
        }
    }

    private func waveform(color: Color) -> some View {
        WaveformView(
            level: state.level,
            barCount: 7,
            color: color,
            active: true
        )
        .frame(width: 38, height: 26)
        .clipped()
    }

    private var microphoneTint: Color {
        if state.assistantInsertionSucceeded {
            return palette.accent
        }
        if micIsHoldingForAI {
            return palette.aiTeal
        }
        switch state.aiSession.phase {
        case .listening:
            return palette.aiTeal
        case .preparing, .recognizing, .generating:
            // Match ordinary dictation's non-interactive waiting appearance,
            // including hint-card requests that start directly in generation.
            return palette.recordRed.opacity(0.72)
        case .inactive, .idle, .ready, .awaitingSend, .inserted, .sent, .failed:
            break
        }
        switch state.phase {
        case .recording:
            return palette.recordRed
        case .requestingPermissions, .processing:
            return palette.recordRed.opacity(0.72)
        case .error, .denied:
            return palette.warning
        case .idle:
            return palette.accent
        }
    }

    private var microphoneStateIdentifier: String {
        switch state.aiSession.phase {
        case .preparing:
            return "aiPreparing"
        case .listening:
            return "aiListening"
        case .recognizing:
            return "aiRecognizing"
        case .generating:
            return "aiGenerating"
        case .inactive, .idle, .ready, .awaitingSend, .inserted, .sent, .failed:
            break
        }
        switch state.phase {
        case .requestingPermissions:
            return "dictationPreparing"
        case .recording:
            return "dictationRecording"
        case .processing:
            return "dictationProcessing"
        case .error:
            return "error"
        case .denied:
            return "denied"
        case .idle:
            return state.assistantInsertionSucceeded ? "success" : "idle"
        }
    }

    private var primaryButtonWidth: CGFloat {
        state.layoutWidth > 0 && state.layoutWidth < 350
            ? Layout.compactPrimaryWidth
            : Layout.primaryWidth
    }

    private var primaryButtonHeight: CGFloat {
        state.layoutWidth > 0 && state.layoutWidth < 350
            ? Layout.compactPrimaryHeight
            : Layout.primaryHeight
    }

    private func handleMicrophonePressing(_ pressing: Bool) {
        if pressing {
            micLongPressConsumed = false
            guard microphoneIsPressable else { return }
            state.setMicTouchActive(true)
            if assistantIsResting {
                withAnimation(.easeOut(duration: 0.12)) {
                    micIsHoldingForAI = true
                }
            }
            return
        }
        state.setMicTouchActive(false)
        withAnimation(.easeOut(duration: 0.12)) {
            micIsHoldingForAI = false
        }
        if micLongPressConsumed {
            micLongPressConsumed = false
            return
        }
        handleMicrophoneTap()
    }

    private func beginAIMicrophone() {
        guard assistantIsResting else { return }
        micLongPressConsumed = true
        showsLongPressCoach = false
        KeyboardHapticFeedback.play(
            role: .action,
            intensity: state.keyboardHapticIntensity
        )
        state.tapAIMic()
    }

    private func handleMicrophoneTap() {
        guard microphoneIsPressable else { return }
        if state.aiSession.phase == .listening {
            state.tapAIMic()
        } else {
            state.tapMic()
        }
    }

    private var microphoneIsPressable: Bool {
        if state.aiSession.isBusy {
            return state.aiSession.phase == .listening
        }
        switch state.phase {
        case .processing, .requestingPermissions:
            return false
        case .idle, .recording, .error, .denied:
            return !state.micDisabled
        }
    }

    // MARK: - Secondary actions

    private var secondaryActionRow: some View {
        ZStack {
            HStack(spacing: 0) {
                lowerActionCluster(leading: true)
                Spacer(minLength: 0)
                lowerActionCluster(leading: false)
            }
            .opacity(sideButtonsVisible ? 1 : 0)
            .allowsHitTesting(sideButtonsVisible)
            .accessibilityHidden(!sideButtonsVisible)

            fieldActionButton
        }
        .frame(maxWidth: Layout.actionClusterMaxWidth)
        .frame(maxWidth: .infinity)
        .opacity(activePipeline ? 0 : 1)
        .allowsHitTesting(!activePipeline)
        .accessibilityHidden(activePipeline)
    }

    @ViewBuilder
    private func lowerActionCluster(leading: Bool) -> some View {
        let button = lowerSideButton(leading: leading)
            .offset(x: leading
                ? Layout.sideButtonEdgeInset
                : -Layout.sideButtonEdgeInset)
        if state.showsSystemGlobeKey {
            if leading {
                HStack(spacing: 8) {
                    SystemGlobeKey(
                        state: state,
                        width: compactIPadLayout ? 40 : 44,
                        height: lowerCircleSize
                    )
                    button
                }
            } else {
                HStack(spacing: 8) {
                    button
                    Color.clear.frame(width: compactIPadLayout ? 40 : 44)
                }
            }
        } else {
            button
        }
    }

    @ViewBuilder
    private func lowerSideButton(leading: Bool) -> some View {
        let swapped = state.handednessPreference.swapsActionKeys
        let showsEdit = leading ? swapped : !swapped
        if showsEdit {
            circleActionButton(
                systemName: "pencil.line",
                label: ExtL10n.string("keyboard.edit.apply"),
                disabled: !state.editAvailable,
                onPressingChanged: state.setMicTouchActive,
                action: state.beginEditLastInput
            )
            .accessibilityIdentifier("assistant.edit")
            .opacity(state.editAvailable ? 1 : 0)
            .accessibilityHidden(!state.editAvailable)
        } else {
            circleActionButton(
                systemName: "arrow.uturn.backward",
                label: ExtL10n.string("keyboard.undoA11y"),
                disabled: !state.undoAvailable,
                action: state.undoLastInsertion
            )
            .accessibilityIdentifier("assistant.undo")
            .opacity(state.undoAvailable ? 1 : 0)
            .accessibilityHidden(!state.undoAvailable)
        }
    }

    private var fieldActionButton: some View {
        Button(action: performFieldAction) {
            Image(systemName: fieldActionSystemImage)
                .font(TypeStyle.title3)
                .foregroundStyle(fieldActionButtonForeground)
                .frame(
                    width: fieldActionButtonWidth,
                    height: KeyboardChromeLayout.assistantActionCapsuleHeight
                )
                .background(fieldActionButtonFill, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!state.assistantActionAvailable)
        .accessibilityIdentifier(
            "assistant.action.\(state.returnKeyRole.assistantActionIdentifier)"
        )
        .accessibilityLabel(ExtL10n.text(state.returnKeyRole.titleKey))
    }

    private var fieldActionSystemImage: String {
        fieldActionConfirmationVisible
            ? "checkmark"
            : state.returnKeyRole.assistantActionSystemImage
    }

    private var fieldActionButtonFill: Color {
        state.assistantActionAvailable
            ? NativeKeyboardKeyColors.fill(for: colorScheme)
            : NativeKeyboardKeyColors.pressedFill(for: colorScheme)
    }

    private var fieldActionButtonForeground: Color {
        state.assistantActionAvailable
            ? NativeKeyboardKeyColors.text(for: colorScheme)
            : NativeKeyboardKeyColors.text(for: colorScheme).opacity(0.58)
    }

    private func performFieldAction() {
        guard state.assistantActionAvailable else { return }
        state.performAssistantFieldAction()
        fieldActionConfirmationVisible = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(550))
            fieldActionConfirmationVisible = false
        }
    }

    private var fieldActionButtonWidth: CGFloat {
        compactIPadLayout
            ? Layout.compactIPadFieldActionWidth
            : Layout.fieldActionWidth
    }

    private var lowerCircleSize: CGFloat {
        compactIPadLayout ? Layout.compactIPadCircleSize : Layout.circleSize
    }

    private var compactIPadLayout: Bool {
        state.usesIPadLayoutMetrics && state.layoutWidth > 0 && state.layoutWidth < 420
    }

    private func circleActionButton(
        systemName: String,
        label: String,
        disabled: Bool = false,
        onPressingChanged: @escaping (Bool) -> Void = { _ in },
        action: @escaping () -> Void
    ) -> some View {
        RectangularToolbarButton(
            systemName: systemName,
            label: label,
            disabled: disabled,
            usesLiquidGlass: true,
            usesCircleGlass: true,
            hapticIntensity: state.keyboardHapticIntensity,
            onPressingChanged: onPressingChanged,
            action: action
        )
        .frame(width: lowerCircleSize, height: lowerCircleSize)
    }

    private var repeatingDeleteButton: some View {
        RepeatingPressButton(
            disabled: false,
            hapticIntensity: state.keyboardHapticIntensity,
            action: state.deleteBackward
        ) { isPressed in
            ZStack {
                Color.clear
                Image(systemName: "delete.left")
                    .font(TypeStyle.headline)
                    .foregroundStyle(NativeKeyboardKeyColors.text(for: colorScheme))
            }
            .frame(width: lowerCircleSize, height: lowerCircleSize)
            .glassEffect(.regular.interactive(), in: Circle())
            .scaleEffect(isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.08), value: isPressed)
        }
        .accessibilityIdentifier("assistant.delete")
        .accessibilityLabel(Text(ExtL10n.string("keyboard.assistant.delete")))
    }

    // MARK: - Visibility and clipboard

    private var assistantIsResting: Bool {
        guard !state.aiSession.isBusy,
              !state.aiSession.canInsert,
              !state.aiSession.canSelectReplyVariant else {
            return false
        }
        switch state.phase {
        case .idle, .error, .denied:
            return true
        case .requestingPermissions, .recording, .processing:
            return false
        }
    }

    private var activePipeline: Bool {
        if state.aiSession.isBusy { return true }
        return ordinaryPipelineIsActive
    }

    private var ordinaryPipelineIsActive: Bool {
        switch state.phase {
        case .requestingPermissions, .recording, .processing:
            return true
        case .idle, .error, .denied:
            return false
        }
    }

    private var sideButtonsVisible: Bool {
        assistantIsResting
    }

    private var shouldShowClipboardSuggestion: Bool {
        guard state.canShowClipboardEntry else { return false }
        guard let text = state.clipboardSuggestionText, !text.isEmpty else { return false }
        return true
    }

    private func insertClipboardSuggestion() {
        state.dismissedClipboardSkillEntryID = clipboardHistory.newestEntry?.id
        if let text = state.clipboardSuggestionText {
            state.insertClipboardText(text)
        }
    }

    private func dismissClipboardPresentation() {
        #if DEBUG
        if Self.debugPreviewSkills != nil {
            debugSkillsDismissed = true
        }
        #endif
        state.dismissedClipboardSkillEntryID = clipboardHistory.newestEntry?.id
        state.dismissClipboardSuggestion()
    }

    // MARK: - Carousel

    private func resetCarousel() {
        reloadHintPool(resetBag: true)
        guard !showsClipboardSkills, semanticBadgeContent == nil else { return }
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
            withAnimation(.easeOut(duration: 0.18)) { hintOpacity = 0 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                currentHint = next
                withAnimation(.easeIn(duration: 0.18)) { hintOpacity = 1 }
            }
        } else {
            currentHint = next
            hintOpacity = 1
        }
    }
}

/// Uses a subview's intrinsic width until it reaches a visual cap. Unlike
/// `frame(maxWidth:)`, this layout does not expand short labels to the cap,
/// so each capsule and its complete hit target follow the actual content.
private struct IntrinsicWidthCap: Layout {
    let maxWidth: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        guard let subview = subviews.first else { return .zero }
        let ideal = subview.sizeThatFits(.unspecified)
        let availableWidth = min(proposal.width ?? maxWidth, maxWidth)
        let width = min(ideal.width, availableWidth)
        let fitted = subview.sizeThatFits(
            ProposedViewSize(width: width, height: proposal.height)
        )
        return CGSize(width: width, height: fitted.height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        guard let subview = subviews.first else { return }
        subview.place(
            at: CGPoint(x: bounds.midX, y: bounds.midY),
            anchor: .center,
            proposal: ProposedViewSize(width: bounds.width, height: bounds.height)
        )
    }
}
