// LastInputEditCoordinator.swift
// OSGKeyboard · Keyboard Extension
//
// Product workflow for explicit editing. Flow transport remains owned by
// KeyboardFlowCoordinator; this coordinator owns only edit state and delivery.

import Foundation
import OSGKeyboardShared

@MainActor
final class LastInputEditCoordinator {
    private let state: KeyboardState
    private let textInserter: KeyboardTextInserter
    private let beginFlow: (EditableInputReference) -> FlowUtteranceStartDisposition
    private let stopFlow: () -> Void
    private let abortFlow: () -> Void
    private let acknowledge: (FlowAck.DeliveryOutcome) -> Void
    private unowned let editHintScheduler: EditHintScheduler
    private var activeUtteranceID: UUID?
    private var reviewedUtteranceID: UUID?
    private var reviewedRevision: Int64?

    init(
        state: KeyboardState,
        textInserter: KeyboardTextInserter,
        beginFlow: @escaping (EditableInputReference) -> FlowUtteranceStartDisposition,
        stopFlow: @escaping () -> Void,
        abortFlow: @escaping () -> Void,
        acknowledge: @escaping (FlowAck.DeliveryOutcome) -> Void,
        editHintScheduler: EditHintScheduler
    ) {
        self.state = state
        self.textInserter = textInserter
        self.beginFlow = beginFlow
        self.stopFlow = stopFlow
        self.abortFlow = abortFlow
        self.acknowledge = acknowledge
        self.editHintScheduler = editHintScheduler
    }

    func begin() {
        switch state.editSession {
        case .inactive, .failed:
            break
        default:
            return
        }

        guard !state.micDisabled else {
            showHint(ExtL10n.string("keyboard.edit.error.llmUnavailable"))
            return
        }
        switch state.micVoiceAvailability {
        case .unavailable(.missingAPIKey):
            showHint(ExtL10n.string("keyboard.edit.error.llmUnavailable"))
            return
        case .unavailable(.noFullAccess):
            showHint(ExtL10n.string("keyboard.error.fullAccessRequired"))
            return
        case .unavailable(.appGroupUnavailable):
            showHint(ExtL10n.string("keyboard.error.appGroupCommunication"))
            return
        case .unavailable(.onboardingIncomplete):
            showHint(ExtL10n.string("keyboard.hint.finishSetupInApp"))
            return
        case .unavailable(.hostNotReady),
             .unavailable(.preparingSession),
             .ready,
             .recording,
             .processing:
            break
        }
        guard let reference = textInserter.editableReference() else {
            showHint(ExtL10n.string("keyboard.edit.error.noTarget"))
            return
        }
        start(reference)
    }

    private func start(_ reference: EditableInputReference) {
        let source = EditSessionSource(reference: reference)
        state.lastTranscript = ""
        let disposition = beginFlow(reference)
        guard let utteranceID = disposition.utteranceID else {
            let message = startFailureMessage(for: disposition)
            state.editSession = .failed(source, message: message)
            state.phase = .idle
            state.lastTranscript = ""
            EditUsageMetricsStore.record(.failed)
            return
        }
        activeUtteranceID = utteranceID
        reviewedUtteranceID = nil
        reviewedRevision = nil
        state.editCanReplaceOriginal = true
        state.editSession = .preparing(source)
        state.phase = .requestingPermissions
        EditUsageMetricsStore.record(.entered)
        KeyboardHapticFeedback.play(
            role: .action,
            intensity: state.keyboardHapticIntensity
        )
        OSGLog.keyboardExt.info(
            "edit.start issued utterance=\(self.activeUtteranceID?.uuidString.prefix(8) ?? "nil", privacy: .public)"
        )
    }

    func hostRecordingConfirmed() {
        guard case .preparing(let source) = state.editSession else { return }
        state.editSession = .listening(source)
        state.phase = .recording
        KeyboardHapticFeedback.play(
            role: .action,
            intensity: state.keyboardHapticIntensity
        )
        OSGLog.keyboardExt.info(
            "edit.hostRecording.confirmed utterance=\(self.activeUtteranceID?.uuidString.prefix(8) ?? "nil", privacy: .public)"
        )
    }

    func stopListening() {
        guard case .listening(let source) = state.editSession else { return }
        state.editSession = .processing(source)
        state.phase = .processing
        stopFlow()
    }

    func receive(result: FlowResult) {
        guard result.resolvedUtteranceMode == .editLastInput,
              result.utteranceId == activeUtteranceID,
              case .processing(let source) = state.editSession,
              reviewedUtteranceID != result.utteranceId
                || reviewedRevision != result.revision,
              let output = result.text else {
            return
        }
        switch EditOutputValidator.validate(
            sourceText: source.reference.displayText,
            output: output
        ) {
        case .success(let validated):
            reviewedUtteranceID = result.utteranceId
            reviewedRevision = result.revision
            let review = EditReview(
                source: source,
                resultText: validated,
                utteranceID: result.utteranceId
            )
            state.editCanReplaceOriginal =
                textInserter.editableReference()?.targetID == source.reference.targetID
            state.editSession = .review(review)
            state.phase = .processing
            KeyboardHapticFeedback.play(
                role: .action,
                intensity: state.keyboardHapticIntensity
            )
        case .failure(.unchanged):
            fail(ExtL10n.string("keyboard.edit.error.unchanged"))
            acknowledge(.rejected)
        case .failure:
            fail(ExtL10n.string("keyboard.edit.error.processing"))
            acknowledge(.rejected)
        }
    }

    func fail(_ message: String) {
        guard let source = state.editSession.source else {
            showHint(message)
            return
        }
        state.editSession = .failed(source, message: message)
        state.phase = .idle
        state.lastTranscript = ""
        EditUsageMetricsStore.record(.failed)
        activeUtteranceID = nil
        reviewedUtteranceID = nil
        reviewedRevision = nil
    }

    func refreshContext() {
        guard let source = state.editSession.source else { return }
        state.editCanReplaceOriginal =
            textInserter.editableReference()?.targetID == source.reference.targetID
    }

    func confirm() {
        guard case .review(let review) = state.editSession else { return }
        let shouldAppend = !state.editCanReplaceOriginal
        state.editSession = shouldAppend ? .appending(review) : .applying(review)
        let applied = textInserter.applyEdit(review, append: shouldAppend)
        guard applied else {
            state.editSession = .review(review)
            state.editCanReplaceOriginal = false
            return
        }
        acknowledge(shouldAppend ? .appended : .replaced)
        EditUsageMetricsStore.record(shouldAppend ? .appended : .replaced)
        state.editSession = .inactive
        state.editCanReplaceOriginal = false
        state.phase = .idle
        state.lastTranscript = ""
        activeUtteranceID = nil
        reviewedUtteranceID = nil
        reviewedRevision = nil
        KeyboardHapticFeedback.play(
            role: .action,
            intensity: state.keyboardHapticIntensity
        )
    }

    func close() {
        if state.editSession.review != nil {
            acknowledge(.rejected)
        } else {
            abortFlow()
        }
        state.editSession = .inactive
        state.editCanReplaceOriginal = false
        state.phase = .idle
        state.lastTranscript = ""
        EditUsageMetricsStore.record(.cancelled)
        activeUtteranceID = nil
        reviewedUtteranceID = nil
        reviewedRevision = nil
    }

    private func showHint(_ message: String) {
        editHintScheduler.show(
            message: message,
            isPositive: false,
            duration: .milliseconds(2_500)
        )
    }

    private func startFailureMessage(
        for disposition: FlowUtteranceStartDisposition
    ) -> String {
        guard case .rejected(let reason) = disposition else {
            return ExtL10n.string("keyboard.edit.error.startTimeout")
        }
        switch reason {
        case .missingAPIKey:
            return ExtL10n.string("keyboard.edit.error.llmUnavailable")
        case .noFullAccess:
            return ExtL10n.string("keyboard.error.fullAccessRequired")
        case .appGroupUnavailable:
            return ExtL10n.string("keyboard.error.appGroupCommunication")
        case .onboardingIncomplete:
            return ExtL10n.string("keyboard.hint.finishSetupInApp")
        case .pipelineBusy:
            return ExtL10n.string("keyboard.edit.error.processing")
        case .hostUnavailable:
            return ExtL10n.string("keyboard.edit.error.startTimeout")
        }
    }
}
