// AnalyticsModelTests.swift
// OSGKeyboardTests
//
// Wire-contract and privacy invariants for the allowlisted analytics schema.

import Foundation
@testable import OSGKeyboardShared
import XCTest

final class AnalyticsModelTests: XCTestCase {
    func testEventEncodingContainsOnlyAllowlistedKeysAndNoFreeTextContainer() throws {
        let event = try AnalyticsEvent(
            clientEventId: analyticsTestUUID(2),
            eventType: .aiFeatureFailed,
            occurredAt: Date(timeIntervalSince1970: 1_700_000_000.125),
            surface: .keyboard,
            appVersion: "2.0.0",
            osVersion: "26.0",
            feature: .polish,
            executionMode: .managed,
            failureCategory: .network,
            durationBucket: .oneToThreeSeconds
        )

        let data = try JSONEncoder().encode(event)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        XCTAssertEqual(
            Set(object.keys),
            [
                "clientEventId",
                "eventType",
                "occurredAt",
                "surface",
                "appVersion",
                "osVersion",
                "feature",
                "executionMode",
                "failureCategory",
                "durationBucket"
            ]
        )
        XCTAssertFalse(object.keys.contains("properties"))
        XCTAssertFalse(object.keys.contains("text"))
        XCTAssertEqual(
            Set(Mirror(reflecting: event).children.compactMap(\.label)),
            Set(object.keys).union(["acquisitionChannel"])
        )
    }

    func testUnknownFieldsAreRejectedAtEveryWireEnvelope() throws {
        let event = try AnalyticsEvent(
            clientEventId: analyticsTestUUID(2),
            eventType: .sessionStarted,
            occurredAt: Date(timeIntervalSince1970: 1_700_000_000),
            surface: .app,
            appVersion: "2.0.0",
            osVersion: "26.0"
        )
        var eventObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(event))
                as? [String: Any]
        )
        eventObject["userText"] = "must be rejected"
        assertUnknownField(
            try JSONSerialization.data(withJSONObject: eventObject),
            as: AnalyticsEvent.self,
            expected: "userText"
        )

        let request = Data(#"{"events":[],"properties":{"secret":"value"}}"#.utf8)
        assertUnknownField(
            request,
            as: AnalyticsUploadRequest.self,
            expected: "properties"
        )

        let response = Data(#"{"accepted":1,"replayed":0,"debug":"secret"}"#.utf8)
        assertUnknownField(
            response,
            as: AnalyticsUploadResponse.self,
            expected: "debug"
        )
    }

    func testUploadRequestMatchesStrictKtorOpenAPIFixture() throws {
        let fixture = Data(
            """
            {
              "installationId": "00000000-0000-0000-0000-000000000001",
              "events": [
                {
                  "clientEventId": "00000000-0000-0000-0000-000000000002",
                  "eventType": "FIRST_OPEN",
                  "occurredAt": "2023-11-14T22:13:20.000Z",
                  "surface": "APP",
                  "appVersion": "2.0.0",
                  "osVersion": "26.0"
                }
              ]
            }
            """.utf8
        )

        let request = try JSONDecoder().decode(AnalyticsUploadRequest.self, from: fixture)
        XCTAssertEqual(request.installationId, analyticsTestUUID(1))
        XCTAssertEqual(request.events.single?.clientEventId, analyticsTestUUID(2))

        let encoded = try AnalyticsCanonicalJSON.encode(request)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        XCTAssertEqual(Set(object.keys), ["installationId", "events"])
        let event = try XCTUnwrap((object["events"] as? [[String: Any]])?.single)
        XCTAssertEqual(
            Set(event.keys),
            [
                "clientEventId",
                "eventType",
                "occurredAt",
                "surface",
                "appVersion",
                "osVersion"
            ]
        )
        XCTAssertNil(event["installationId"])
    }

    func testEnvironmentFiltersAndTruncatesVersionsToSafeBound() {
        let environment = AnalyticsEnvironment(
            appVersion: String(repeating: "a", count: 40) + "/private",
            osVersion: "26.0 (Build 23A)/用户"
        )

        XCTAssertEqual(environment.appVersion, String(repeating: "a", count: 32))
        XCTAssertEqual(environment.appVersion.utf8.count, 32)
        XCTAssertEqual(environment.osVersion, "26.0Build23A")

        let empty = AnalyticsEnvironment(appVersion: "用户 /", osVersion: "")
        XCTAssertEqual(empty.appVersion, "unknown")
        XCTAssertEqual(empty.osVersion, "unknown")
    }

    func testPurchaseCancelledRequiresCancelledFailureCategory() throws {
        XCTAssertNoThrow(
            try AnalyticsEvent(
                clientEventId: analyticsTestUUID(2),
                eventType: .purchaseCancelled,
                occurredAt: Date(timeIntervalSince1970: 1_700_000_000),
                surface: .app,
                appVersion: "2.0.0",
                osVersion: "26.0",
                failureCategory: .cancelled
            )
        )

        XCTAssertThrowsError(
            try AnalyticsEvent(
                clientEventId: analyticsTestUUID(3),
                eventType: .purchaseCancelled,
                occurredAt: Date(timeIntervalSince1970: 1_700_000_000),
                surface: .app,
                appVersion: "2.0.0",
                osVersion: "26.0",
                failureCategory: .network
            )
        ) { error in
            guard case AnalyticsModelError.invalidDimensions(.purchaseCancelled) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testDurationBucketBoundariesAreStable() {
        XCTAssertEqual(AnalyticsDurationBucket(elapsedNanoseconds: 999_999_999), .lessThanOneSecond)
        XCTAssertEqual(AnalyticsDurationBucket(elapsedNanoseconds: 1_000_000_000), .oneToThreeSeconds)
        XCTAssertEqual(AnalyticsDurationBucket(elapsedNanoseconds: 2_999_999_999), .oneToThreeSeconds)
        XCTAssertEqual(AnalyticsDurationBucket(elapsedNanoseconds: 3_000_000_000), .threeToTenSeconds)
        XCTAssertEqual(AnalyticsDurationBucket(elapsedNanoseconds: 10_000_000_000), .tenToThirtySeconds)
        XCTAssertEqual(AnalyticsDurationBucket(elapsedNanoseconds: 30_000_000_000), .thirtySecondsOrMore)
    }

    private func assertUnknownField<T: Decodable>(
        _ data: Data,
        as type: T.Type,
        expected: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(
            try JSONDecoder().decode(type, from: data),
            file: file,
            line: line
        ) { error in
            guard case AnalyticsModelError.unknownField(let field) = error else {
                return XCTFail("Unexpected error: \(error)", file: file, line: line)
            }
            XCTAssertEqual(field, expected, file: file, line: line)
        }
    }
}

private extension Array {
    var single: Element? {
        count == 1 ? first : nil
    }
}
