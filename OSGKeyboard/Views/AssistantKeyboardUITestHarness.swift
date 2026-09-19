#if DEBUG
import OSGKeyboardShared
import SwiftUI
import UIKit

/// Deterministic host for simulator UI tests of the real assistant keyboard.
/// It exercises gesture routing and closed UI states without requiring a
/// keyboard-extension process, microphone permission, ASR, or an LLM.
struct AssistantKeyboardUITestHarness: View {
    private enum Scenario: String {
        case idle
        case completed
        case pending
        case skillFailure
        case skills
        case semanticBadge
        case search
        case autoReplyGuidance
        case translateResult
        case yesNoReply
    }

    @StateObject private var state = KeyboardState()
    @StateObject private var typing = TypingSessionController()
    @State private var configured = false
    @Environment(\.colorScheme) private var colorScheme

    init() {
        AIKeyboardView.debugSkipsLongPressCoach = true
        AIKeyboardView.debugKeepsSkillTip = true
    }

    private let scenario: Scenario = {
        let prefix = "--assistant-state="
        let raw = ProcessInfo.processInfo.arguments
            .first(where: { $0.hasPrefix(prefix) })?
            .dropFirst(prefix.count)
        return raw.flatMap { Scenario(rawValue: String($0)) } ?? .idle
    }()

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                // Mirror KeyboardSurfaceRoot: the auto-reply guide dims the live
                // keyboard and floats its pitch on top (keyboard stays visible).
                ZStack {
                    AIKeyboardView(
                        state: state,
                        typing: typing,
                        onInsert: { _ in }
                    )

                    if scenario == .autoReplyGuidance {
                        ClipboardAutoReplyGuideView(
                            onClose: { state.clipboardOverlay = .none },
                            onTry: {}
                        )
                    }
                }
                // Constrain to a realistic keyboard band so the scrim dims only
                // the keyboard region, as it does over a real host app.
                .frame(height: scenario == .autoReplyGuidance ? 300 : nil)
                .background(backgroundColor)
            }
            .onAppear {
                configure(width: proxy.size.width)
            }
            .onChange(of: proxy.size.width) { _, width in
                configureLayout(width: width)
            }
        }
        .background(backgroundColor.ignoresSafeArea())
        .onDisappear {
            AIKeyboardView.debugPreviewSkills = nil
            AIKeyboardView.debugPreviewSemanticBadgeKeys = nil
            AIKeyboardView.debugSkipsLongPressCoach = false
            AIKeyboardView.debugKeepsSkillTip = false
        }
    }

    private var backgroundColor: Color {
        colorScheme == .dark ? Palette.dark.background : Palette.light.background
    }

    private func configure(width: CGFloat) {
        configureLayout(width: width)
        guard !configured else { return }
        configured = true

        state.surface = .voice
        state.phase = .idle
        state.aiServiceAvailable = true
        state.micDisabled = false
        state.returnKeyRole = .send
        AIKeyboardView.debugPreviewSemanticBadgeKeys = nil

        let keyboardState = state
        state.tapMic = { [weak keyboardState] in
            guard let keyboardState else { return }
            if case .recording = keyboardState.phase {
                keyboardState.phase = .idle
            } else {
                keyboardState.phase = .recording
            }
        }
        state.tapAIMic = { [weak keyboardState] in
            guard let keyboardState else { return }
            if keyboardState.aiSession.phase == .listening {
                if let utteranceID = keyboardState.aiSession.activeUtteranceID {
                    keyboardState.aiSession.beginRecognizing(utteranceID: utteranceID)
                }
                return
            }
            keyboardState.aiSession.enter()
            let utteranceID = UUID()
            keyboardState.aiSession.beginPreparing(utteranceID: utteranceID)
            keyboardState.aiSession.beginListening(utteranceID: utteranceID)
        }
        state.performAssistantFieldAction = { [weak keyboardState] in
            keyboardState?.assistantActionAvailable = false
        }
        state.undoLastInsertion = { [weak keyboardState] in
            keyboardState?.undoAvailable = false
        }
        state.beginEditLastInput = { [weak keyboardState] in
            guard let keyboardState else { return }
            let reference = EditableInputReference(
                displayText: "Original dictated input",
                insertedText: "Original dictated input",
                postInsertionFingerprint: nil,
                extensionInstanceID: UUID()
            )
            keyboardState.editSession = .listening(EditSessionSource(reference: reference))
            keyboardState.phase = .recording
        }
        state.stopEditListening = { [weak keyboardState] in
            guard let keyboardState,
                  let source = keyboardState.editSession.source else {
                return
            }
            keyboardState.editSession = .review(
                EditReview(
                    source: source,
                    resultText: "Edited dictated input",
                    utteranceID: UUID()
                )
            )
            keyboardState.phase = .processing
        }
        state.confirmEditResult = { [weak keyboardState] in
            keyboardState?.editSession = .inactive
            keyboardState?.phase = .idle
        }
        state.submitAIHint = { [weak keyboardState] _ in
            guard let keyboardState else { return }
            let utteranceID = UUID()
            keyboardState.aiSession.enter()
            keyboardState.aiSession.beginPreparing(utteranceID: utteranceID)
            keyboardState.aiSession.beginGenerating(
                question: "Deterministic hint",
                utteranceID: utteranceID
            )
        }

        switch scenario {
        case .idle:
            AIKeyboardView.debugPreviewSkills = nil
        case .completed:
            AIKeyboardView.debugPreviewSkills = nil
            state.undoAvailable = true
            state.editAvailable = true
            state.assistantActionAvailable = true
        case .pending:
            AIKeyboardView.debugPreviewSkills = nil
            let utteranceID = UUID()
            state.aiSession.enter()
            state.aiSession.beginPreparing(utteranceID: utteranceID)
            state.aiSession.receiveAnswer(
                "A retained answer that requires explicit insertion.",
                utteranceID: utteranceID
            )
            state.confirmPendingAIAnswer = { [weak keyboardState] in
                guard let keyboardState else { return }
                keyboardState.aiSession.markAnswerInserted(offersSend: true)
                keyboardState.undoAvailable = true
                keyboardState.editAvailable = true
                keyboardState.assistantActionAvailable = true
            }
            state.discardPendingAIAnswer = { [weak keyboardState] in
                keyboardState?.aiSession.discardReadyAnswer()
            }
        case .translateResult:
            // Staged auto-translate: result shown on the keyboard, inserted only
            // via the liquid-glass button.
            AIKeyboardView.debugPreviewSkills = nil
            state.activeClipboardSkillID = AIClipboardSkillCatalog.translateID
            state.autoResultReadOnly = true
            let utteranceID = UUID()
            state.aiSession.enter()
            state.aiSession.beginPreparing(utteranceID: utteranceID)
            state.aiSession.receiveAnswer(
                "Let's meet at the cafe tomorrow at 3pm — does that work for you?",
                utteranceID: utteranceID
            )
            state.confirmPendingAIAnswer = { [weak keyboardState] in
                keyboardState?.aiSession.markAnswerInserted(offersSend: true)
            }
            state.discardPendingAIAnswer = { [weak keyboardState] in
                keyboardState?.aiSession.discardReadyAnswer()
            }
        case .yesNoReply:
            // Both-stance answers for a yes/no question (4 variants > 3).
            AIKeyboardView.debugPreviewSkills = nil
            state.activeClipboardSkillID = AIClipboardSkillCatalog.replyID
            // Fresh copy present → the leading slot shows the Paste capsule and the
            // alternates row can rank the skills for this text.
            state.clipboardSuggestionText = "明天下午三点方便吗？"
            state.clipboardSuggestionChangeCount = 1
            ClipboardHistoryStore.shared.ingest(rawText: "明天下午三点方便吗？", changeCount: 1)
            let utteranceID = UUID()
            state.aiSession.enter()
            state.aiSession.beginPreparing(utteranceID: utteranceID)
            state.aiSession.receiveReplyVariants(
                [
                    AIReplyVariant(kind: .answerAffirmative, emotion: .neutral,
                                   text: "可以的，这个时间我没问题，就这么定。"),
                    AIReplyVariant(kind: .answerNegative, emotion: .neutral,
                                   text: "不行，我那天已经排满了，来不了。"),
                    AIReplyVariant(kind: .answerConditional, emotion: .neutral,
                                   text: "如果能改到下午三点之后，我就可以。"),
                    AIReplyVariant(kind: .answerDefer, emotion: .neutral,
                                   text: "我先确认一下日程，稍后回复你。")
                ],
                utteranceID: utteranceID
            )
            state.selectAIReplyVariant = { [weak keyboardState] id in
                _ = keyboardState?.aiSession.selectReplyVariant(id: id)
            }
            // Deterministic stand-in for the coordinator: switch the active skill
            // so the alternates row updates when a capsule is tapped.
            state.submitAIClipboardSkill = { [weak keyboardState] skill, _ in
                keyboardState?.activeClipboardSkillID = skill.id
            }
        case .skillFailure:
            AIKeyboardView.debugPreviewSkills = nil
            state.skillTipText = "Skill failed"
        case .skills:
            // Keep the pagination assertion independent from production catalog
            // ordering: Navigate is guaranteed to appear after one swipe on both
            // four- and five-item pages.
            let navigate = AIClipboardSkillCatalog.catalog.first {
                $0.id == AIClipboardSkillCatalog.navigateID
            }
            let leading = AIClipboardSkillCatalog.catalog
                .filter { $0.id != AIClipboardSkillCatalog.navigateID }
                .prefix(5)
            var previewSkills = Array(leading)
            if let navigate {
                previewSkills.append(navigate)
            }
            AIKeyboardView.debugPreviewSkills = previewSkills
            state.undoAvailable = true
            state.editAvailable = true
        case .semanticBadge:
            AIKeyboardView.debugPreviewSkills = nil
            AIKeyboardView.debugPreviewSemanticBadgeKeys = (
                intent: "keyboard.semantic.intent.informationQuery",
                domain: "keyboard.semantic.domain.weather"
            )
        case .search:
            AIKeyboardView.debugPreviewSkills = nil
            state.returnKeyRole = .search
            state.assistantActionAvailable = true
        case .autoReplyGuidance:
            AIKeyboardView.debugPreviewSkills = nil
            state.clipboardOverlay = .autoReplyGuide
        }
    }

    private func configureLayout(width: CGFloat) {
        let isIPad = UIDevice.current.userInterfaceIdiom == .pad
        state.layoutWidth = width
        state.usesIPadLayoutMetrics = isIPad
        state.showsSystemGlobeKey = isIPad
    }
}

/// Physical-device harness that gives XCUITest a real user tap for PiP.
///
/// `devicectl process launch` is not a user interaction, so iOS may silently
/// ignore a programmatic foreground PiP request even when AVKit reports it as
/// possible. This harness isolates the production controller behind one tap.
struct FlowPiPDeviceUITestHarness: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var flowManager = FlowSessionManager()

    var body: some View {
        VStack(spacing: 20) {
            Button("Start PiP") {
                flowManager.startSession(reason: "uiTest.userTap")
            }
            .accessibilityIdentifier("pip.start")
            .disabled(flowManager.isStarting || flowManager.isActive)

            Text(statusIdentifier)
                .accessibilityIdentifier(statusIdentifier)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            FlowPiPHostView { view in
                flowManager.attachPiPHostView(view)
            }
            .frame(width: 64, height: 36)
            .opacity(0.02)
        }
        .onAppear {
            flowManager.setAppForeground(scenePhase == .active)
        }
        .onChange(of: scenePhase) { _, phase in
            flowManager.handleScenePhase(phase)
        }
    }

    private var statusIdentifier: String {
        if flowManager.isActive, FlowSessionBridge.isHostReady() {
            return "pip.status.ready"
        }
        if flowManager.sessionWarning != nil {
            return "pip.status.failed"
        }
        if flowManager.isStarting {
            return "pip.status.starting"
        }
        return "pip.status.idle"
    }
}
#endif
