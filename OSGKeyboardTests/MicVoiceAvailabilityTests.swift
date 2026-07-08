// MicVoiceAvailabilityTests.swift
// OSGKeyboardTests

import XCTest
@testable import OSGKeyboardShared

final class MicVoiceAvailabilityTests: XCTestCase {

    func testReadyWhenHostReadyAndIdle() {
        let availability = MicVoiceAvailabilityResolver.resolve(
            phase: .idle,
            micDisabled: false,
            hasFullAccess: true,
            appGroupAvailable: true,
            hostReady: true,
            isPreparingSession: false
        )
        XCTAssertEqual(availability, .ready)
    }

    func testUnavailableWhenMissingAPIKey() {
        let availability = MicVoiceAvailabilityResolver.resolve(
            phase: .idle,
            micDisabled: true,
            hasFullAccess: true,
            appGroupAvailable: true,
            hostReady: true,
            isPreparingSession: false
        )
        XCTAssertEqual(availability, .unavailable(.missingAPIKey))
    }

    func testUnavailableWhenHostNotReady() {
        let availability = MicVoiceAvailabilityResolver.resolve(
            phase: .idle,
            micDisabled: false,
            hasFullAccess: true,
            appGroupAvailable: true,
            hostReady: false,
            isPreparingSession: false
        )
        XCTAssertEqual(availability, .unavailable(.hostNotReady))
    }

    func testUnavailableWhenPreparingSession() {
        let availability = MicVoiceAvailabilityResolver.resolve(
            phase: .idle,
            micDisabled: false,
            hasFullAccess: true,
            appGroupAvailable: true,
            hostReady: false,
            isPreparingSession: true
        )
        XCTAssertEqual(availability, .unavailable(.preparingSession))
    }

    func testRecordingOverridesReady() {
        let availability = MicVoiceAvailabilityResolver.resolve(
            phase: .recording,
            micDisabled: false,
            hasFullAccess: true,
            appGroupAvailable: true,
            hostReady: true,
            isPreparingSession: false
        )
        XCTAssertEqual(availability, .recording)
    }

    func testProcessingOverridesUnavailable() {
        let availability = MicVoiceAvailabilityResolver.resolve(
            phase: .processing,
            micDisabled: false,
            hasFullAccess: true,
            appGroupAvailable: true,
            hostReady: false,
            isPreparingSession: false
        )
        XCTAssertEqual(availability, .processing)
    }
}
