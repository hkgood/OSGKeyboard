// AnalyticsExtensionPrivacyTests.swift
// OSGKeyboardExtTests
//
// The keyboard analytics runtime is anonymous and emits only typed dimensions.

import Foundation
@testable import OSGKeyboardShared
import XCTest

final class AnalyticsExtensionPrivacyTests: XCTestCase {
    func testKeyboardRuntimeRecordsWithoutAutomaticallyUploading() async throws {
        let network = ExtensionAnalyticsNetwork()
        let runtime = AnalyticsRuntime.keyboardExtension(
            environment: AnalyticsEnvironment(appVersion: "2.0.0", osVersion: "26.0"),
            repositoryConfiguration: AnalyticsRepositoryConfiguration(
                databaseURL: try temporaryDatabaseURL()
            ),
            uploadConfiguration: AnalyticsUploadConfiguration(
                endpoint: URL(string: "https://analytics.test/v1/events")!
            ),
            network: network,
            wallClock: ExtensionAnalyticsClock(),
            monotonicClock: ExtensionAnalyticsMonotonicClock(),
            uuidGenerator: ExtensionAnalyticsUUIDGenerator(),
            random: ExtensionAnalyticsRandomGenerator()
        )

        runtime.client.recordKeyboardActivated()
        for _ in 0..<200 {
            if await runtime.repository.debugSnapshot().pendingEvents.count == 1 {
                break
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        try await Task.sleep(for: .milliseconds(50))

        let pendingSnapshot = await runtime.repository.debugSnapshot()
        let requests = await network.requests()
        XCTAssertEqual(pendingSnapshot.pendingEvents.count, 1)
        XCTAssertTrue(requests.isEmpty)
    }

    func testKeyboardRuntimeUploadsWithoutAuthorizationOrSensitiveInputFields() async throws {
        let databaseURL = try temporaryDatabaseURL()
        let network = ExtensionAnalyticsNetwork()
        let runtime = AnalyticsRuntime.keyboardExtension(
            environment: AnalyticsEnvironment(appVersion: "2.0.0", osVersion: "26.0"),
            repositoryConfiguration: AnalyticsRepositoryConfiguration(
                databaseURL: databaseURL
            ),
            uploadConfiguration: AnalyticsUploadConfiguration(
                endpoint: URL(string: "https://analytics.test/v1/events")!
            ),
            network: network,
            wallClock: ExtensionAnalyticsClock(),
            monotonicClock: ExtensionAnalyticsMonotonicClock(),
            uuidGenerator: ExtensionAnalyticsUUIDGenerator(),
            random: ExtensionAnalyticsRandomGenerator()
        )

        runtime.client.recordKeyboardActivated()
        for _ in 0..<200 {
            if await runtime.repository.debugSnapshot().pendingEvents.count == 1 {
                break
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        let pendingSnapshot = await runtime.repository.debugSnapshot()
        XCTAssertEqual(pendingSnapshot.pendingEvents.count, 1)

        await runtime.uploadCoordinator.uploadAvailableEvents()

        let requests = await network.requests()
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(requests.count, 1)
        XCTAssertNil(
            request.headers.first {
                $0.key.caseInsensitiveCompare("Authorization") == .orderedSame
            }
        )
        let upload = try JSONDecoder().decode(
            AnalyticsUploadRequest.self,
            from: request.body
        )
        XCTAssertEqual(upload.events.count, 1)
        XCTAssertEqual(upload.events.first?.surface, .keyboard)
        XCTAssertEqual(upload.events.first?.eventType, .keyboardActivated)

        let root = try XCTUnwrap(
            JSONSerialization.jsonObject(with: request.body) as? [String: Any]
        )
        XCTAssertEqual(Set(root.keys), ["installationId", "events"])
        let eventObjects = try XCTUnwrap(root["events"] as? [[String: Any]])
        let event = try XCTUnwrap(eventObjects.first)
        XCTAssertFalse(event.keys.contains("installationId"))
        XCTAssertFalse(event.keys.contains("properties"))
        XCTAssertFalse(event.keys.contains("text"))
        XCTAssertFalse(event.keys.contains("prompt"))
        XCTAssertFalse(event.keys.contains("transcript"))
    }

    private func temporaryDatabaseURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("OSGKeyboardExtensionAnalyticsTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory.appendingPathComponent("analytics.sqlite3")
    }
}

private struct ExtensionAnalyticsClock: AnalyticsWallClock {
    func now() -> Date {
        Date(timeIntervalSince1970: 1_700_000_000)
    }
}

private struct ExtensionAnalyticsMonotonicClock: AnalyticsMonotonicClock {
    func nowNanoseconds() -> UInt64 {
        0
    }
}

private final class ExtensionAnalyticsUUIDGenerator:
    AnalyticsUUIDGenerating,
    @unchecked Sendable {
    private let lock = NSLock()
    private var value = 1

    func makeUUID() -> UUID {
        lock.withLock {
            defer { value += 1 }
            return UUID(
                uuidString: String(
                    format: "00000000-0000-0000-0000-%012x",
                    value
                )
            )!
        }
    }
}

private struct ExtensionAnalyticsRandomGenerator: AnalyticsRandomGenerating {
    func next(upperBound: UInt64) -> UInt64 {
        0
    }
}

private actor ExtensionAnalyticsNetwork: AnalyticsNetworking {
    private var captured: [AnalyticsHTTPRequest] = []

    func send(_ request: AnalyticsHTTPRequest) async throws -> AnalyticsHTTPResponse {
        captured.append(request)
        let upload = try JSONDecoder().decode(
            AnalyticsUploadRequest.self,
            from: request.body
        )
        return AnalyticsHTTPResponse(
            statusCode: 200,
            headers: [:],
            body: Data(
                #"{"accepted":\#(upload.events.count),"replayed":0}"#.utf8
            )
        )
    }

    func requests() -> [AnalyticsHTTPRequest] {
        captured
    }
}
