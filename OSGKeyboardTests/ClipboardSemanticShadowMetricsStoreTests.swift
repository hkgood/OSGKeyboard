// ClipboardSemanticShadowMetricsStoreTests.swift
// OSGKeyboardTests

@testable import OSGKeyboardShared
import XCTest

@MainActor
final class ClipboardSemanticShadowMetricsStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var store: ClipboardSemanticShadowMetricsStore!

    override func setUp() {
        super.setUp()
        suiteName = "ClipboardSemanticShadowMetricsStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        store = ClipboardSemanticShadowMetricsStore(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        store = nil
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testRecordsOnlyAggregateShadowDisagreements() {
        store.record(
            analysis(
                task: detected(),
                actionVerifier: ClipboardVerifierDecision(
                    group: "action",
                    label: "complaintOnly",
                    confidence: 0.97,
                    margin: 0.42,
                    isShadow: true,
                    isRouted: true
                )
            )
        )

        XCTAssertEqual(
            store.metrics(),
            ClipboardSemanticShadowMetrics(
                verifierRuns: 1,
                candidateRoutes: 1,
                verifierRoutes: 1,
                disagreements: 1
            )
        )
    }

    func testIgnoresAutomaticVerifierDecisions() {
        store.record(
            analysis(
                actionVerifier: ClipboardVerifierDecision(
                    group: "action",
                    label: "neither",
                    confidence: 0.99,
                    margin: 0.91,
                    isShadow: false,
                    isRouted: false
                )
            )
        )

        XCTAssertEqual(store.metrics(), .empty)
    }

    private func detected() -> ClipboardIntentLabel {
        ClipboardIntentLabel(
            confidence: 0.95,
            threshold: 0.7,
            isDetected: true,
            isApprovedForAutomaticRouting: true
        )
    }

    private func absent() -> ClipboardIntentLabel {
        ClipboardIntentLabel(
            confidence: 0,
            threshold: 1,
            isDetected: false,
            isApprovedForAutomaticRouting: false
        )
    }

    private func analysis(
        task: ClipboardIntentLabel? = nil,
        actionVerifier: ClipboardVerifierDecision? = nil
    ) -> ClipboardSemanticAnalysis {
        ClipboardSemanticAnalysis(
            language: nil,
            dates: [],
            addresses: [],
            phoneNumbers: [],
            urls: [],
            personNames: [],
            organizationNames: [],
            sentiment: .unknown,
            sentimentConfidence: 0,
            task: task ?? absent(),
            question: absent(),
            invitation: absent(),
            complaint: absent(),
            replyableMessage: absent(),
            scheduleNegotiation: absent(),
            confirmationDecision: absent(),
            followUpReminder: absent(),
            blessing: absent(),
            actionVerifier: actionVerifier,
            coordinationVerifier: nil
        )
    }
}
