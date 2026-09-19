// FlowFailureDiagnosticsTests.swift
// OSGKeyboardTests

import Foundation
import OSGKeyboardShared
import XCTest

final class FlowFailureDiagnosticsTests: XCTestCase {
    /// The keyboard witnesses the failure; the host knows why. The handshake is
    /// what puts both windows in one export.
    func testHostConsumesKeyboardDumpRequestOnce() throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let requestedAt = Date()
        FlowFailureDiagnostics.requestHostSnapshot(
            reason: "startTimeout",
            now: requestedAt,
            defaults: defaults
        )

        let request = try XCTUnwrap(
            FlowFailureDiagnostics.consumeHostSnapshotRequest(
                now: requestedAt.addingTimeInterval(1),
                defaults: defaults
            )
        )
        XCTAssertEqual(request.reason, "startTimeout")

        // Consuming clears it: a second host launch must not re-report.
        XCTAssertNil(
            FlowFailureDiagnostics.consumeHostSnapshotRequest(
                now: requestedAt.addingTimeInterval(2),
                defaults: defaults
            )
        )
    }

    /// A request left behind while the host was dead must not make an unrelated
    /// later launch write a bogus companion report.
    func testStaleDumpRequestIsDiscarded() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let requestedAt = Date()
        FlowFailureDiagnostics.requestHostSnapshot(
            reason: "hostDisconnected",
            now: requestedAt,
            defaults: defaults
        )

        XCTAssertNil(
            FlowFailureDiagnostics.consumeHostSnapshotRequest(
                now: requestedAt.addingTimeInterval(
                    FlowFailureDiagnostics.dumpRequestMaxAge + 1
                ),
                defaults: defaults
            )
        )
    }

    func testBridgeContextAlwaysIdentifiesTheRecordingProcess() {
        let context = FlowFailureDiagnostics.bridgeContext()
        XCTAssertEqual(context["process"], FlowDiagnosticsProcess.current.rawValue)
        XCTAssertNotNil(context["appGroupAvailable"])
    }

    private func makeDefaults() -> (UserDefaults, String) {
        let suiteName = "FlowFailureDiagnosticsTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("could not open test suite")
            return (.standard, suiteName)
        }
        return (defaults, suiteName)
    }
}
