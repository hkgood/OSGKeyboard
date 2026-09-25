// ClipboardSemanticShadowMetricsStore.swift
// OSGKeyboard · Shared
//
// Stores only bounded aggregate verifier counters. Clipboard text, identifiers,
// model confidences, and individual predictions are intentionally never saved.

import Foundation

public struct ClipboardSemanticShadowMetrics: Codable, Equatable, Sendable {
    public var verifierRuns: Int
    public var candidateRoutes: Int
    public var verifierRoutes: Int
    public var disagreements: Int

    public static let empty = ClipboardSemanticShadowMetrics(
        verifierRuns: 0,
        candidateRoutes: 0,
        verifierRoutes: 0,
        disagreements: 0
    )
}

@MainActor
public final class ClipboardSemanticShadowMetricsStore {
    public static let shared = ClipboardSemanticShadowMetricsStore()
    public static let maximumCounterValue = 1_000_000

    private static let storageKey = "clipboard.semanticShadowMetrics.v1"
    private let defaults: UserDefaults?

    public init(defaults: UserDefaults? = AppGroup.defaultsIfAvailable) {
        self.defaults = defaults
    }

    public func metrics() -> ClipboardSemanticShadowMetrics {
        guard let data = defaults?.data(forKey: Self.storageKey),
              let value = try? JSONDecoder().decode(
                  ClipboardSemanticShadowMetrics.self,
                  from: data
              ) else {
            return .empty
        }
        return value
    }

    public func record(_ analysis: ClipboardSemanticAnalysis) {
        var next = metrics()
        if let decision = analysis.actionVerifier, decision.isShadow {
            increment(&next.verifierRuns)
            let candidateLabel = actionCandidateLabel(analysis)
            if candidateLabel != "neither" {
                increment(&next.candidateRoutes)
            }
            if decision.isRouted {
                increment(&next.verifierRoutes)
            }
            if candidateLabel != routedLabel(decision) {
                increment(&next.disagreements)
            }
        }
        if let decision = analysis.coordinationVerifier, decision.isShadow {
            increment(&next.verifierRuns)
            let candidateLabel = coordinationCandidateLabel(analysis)
            if candidateLabel != "neither" {
                increment(&next.candidateRoutes)
            }
            if decision.isRouted {
                increment(&next.verifierRoutes)
            }
            if candidateLabel != routedLabel(decision) {
                increment(&next.disagreements)
            }
        }
        guard let encoded = try? JSONEncoder().encode(next) else { return }
        defaults?.set(encoded, forKey: Self.storageKey)
    }

    public func clear() {
        defaults?.removeObject(forKey: Self.storageKey)
    }

    private func actionCandidateLabel(_ analysis: ClipboardSemanticAnalysis) -> String {
        if analysis.task.isDetected && analysis.complaint.isDetected {
            return "both"
        }
        if analysis.task.isDetected {
            return "taskOnly"
        }
        if analysis.complaint.isDetected {
            return "complaintOnly"
        }
        if analysis.question.isDetected {
            return "questionRequest"
        }
        return "neither"
    }

    private func coordinationCandidateLabel(
        _ analysis: ClipboardSemanticAnalysis
    ) -> String {
        let labels = [
            analysis.invitation.isDetected ? "invitation" : nil,
            analysis.scheduleNegotiation.isDetected ? "scheduleNegotiation" : nil,
            analysis.confirmationDecision.isDetected ? "confirmationDecision" : nil,
            analysis.followUpReminder.isDetected ? "followUpReminder" : nil
        ].compactMap { $0 }
        return labels.count == 1 ? labels[0] : "neither"
    }

    private func routedLabel(_ decision: ClipboardVerifierDecision) -> String {
        decision.isRouted ? decision.label : "neither"
    }

    private func increment(_ value: inout Int) {
        value = min(value + 1, Self.maximumCounterValue)
    }
}
