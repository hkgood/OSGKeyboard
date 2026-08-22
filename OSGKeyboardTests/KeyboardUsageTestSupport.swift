// KeyboardUsageTestSupport.swift
// OSGKeyboardTests
//
// Deterministic fixtures for aggregate keyboard usage storage and uploads.

import Foundation
@testable import OSGKeyboardShared

func keyboardUsageTemporaryDatabaseURL() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(
            "OSGKeyboardUsageTests",
            isDirectory: true
        )
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: true
    )
    return directory.appendingPathComponent("keyboard-usage.sqlite3")
}

func keyboardUsageDate(
    _ year: Int,
    _ month: Int,
    _ day: Int,
    hour: Int = 12
) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar.date(
        from: DateComponents(
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour
        )
    )!
}

let keyboardUsageEnvironment = AnalyticsEnvironment(
    appVersion: "2.0.0",
    osVersion: "26.0"
)

func keyboardUsageRecord(
    _ counts: KeyboardUsageCharacterCounts,
    sessionID: UUID,
    occurredAt: Date,
    repository: KeyboardUsageRepository,
    installationID: UUID = analyticsTestUUID(900)
) async {
    await repository.record(
        counts: counts,
        sessionID: sessionID,
        installationID: installationID,
        occurredAt: occurredAt,
        environment: keyboardUsageEnvironment
    )
}

func keyboardUsageSuccessResponse(
    accepted: Int,
    replayed: Int = 0
) -> AnalyticsHTTPResponse {
    AnalyticsHTTPResponse(
        statusCode: 200,
        headers: [:],
        body: Data(
            #"{"accepted":\#(accepted),"replayed":\#(replayed)}"#.utf8
        )
    )
}
