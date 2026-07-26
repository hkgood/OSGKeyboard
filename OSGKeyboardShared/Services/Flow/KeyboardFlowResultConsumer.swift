// KeyboardFlowResultConsumer.swift
// OSGKeyboard · Shared
//
// Result consumption and ack/clear logic extracted from KeyboardFlowCoordinator.

import Foundation

public enum KeyboardFlowResultConsumer {
    public struct Delivery: Equatable, Sendable {
        public let text: String
        public let warning: String?

        public init(text: String, warning: String?) {
            self.text = text
            self.warning = warning
        }
    }

    public struct TerminalError: Equatable, Sendable {
        public let message: String
        public let kind: FlowSessionKeys.TranscriptionErrorKind

        public init(message: String, kind: FlowSessionKeys.TranscriptionErrorKind) {
            self.message = message
            self.kind = kind
        }
    }

    public enum Outcome: Equatable, Sendable {
        case final(Delivery)
        case terminalError(TerminalError)
        case none
    }

    public static func evaluate(
        latestResult: FlowResult?,
        activeSessionId: UUID?,
        currentUtteranceId: UUID?
    ) -> Outcome {
        let result = KeyboardFlowResultMatcher.matchingResult(
            latest: latestResult,
            activeSessionId: activeSessionId,
            currentUtteranceId: currentUtteranceId
        )
        guard let result else { return .none }

        if KeyboardFlowResultMatcher.isConsumableFinal(result),
           let text = result.text {
            return .final(Delivery(text: text, warning: result.warning))
        }
        if KeyboardFlowResultMatcher.isTerminalFailure(result) {
            return .terminalError(
                TerminalError(
                    message: result.text ?? "",
                    kind: result.errorKind ?? .generic
                )
            )
        }
        return .none
    }

    public static func acknowledgeAndClear(_ result: FlowResult, defaults: UserDefaults? = nil) {
        FlowSessionBridge.writeAck(
            FlowAck(
                sessionId: result.sessionId,
                utteranceId: result.utteranceId,
                commandSeq: result.commandSeq
            ),
            defaults: defaults
        )
        FlowSessionBridge.clearResult(defaults: defaults)
    }

    public static func clearResultOnly(defaults: UserDefaults? = nil) {
        FlowSessionBridge.clearResult(defaults: defaults)
    }
}
