import XCTest
@testable import OSGKeyboardShared

final class MicrophonePriorityTests: XCTestCase {
    private let builtIn = MicrophonePriorityDevice(
        id: "built-in",
        name: "iPhone Microphone",
        kind: .builtIn
    )
    private let bluetooth = MicrophonePriorityDevice(
        id: "airpods",
        name: "AirPods",
        kind: .bluetooth
    )
    private let usb = MicrophonePriorityDevice(
        id: "usb",
        name: "USB Microphone",
        kind: .usb
    )

    func testMergeAppendsNewDevicesWithoutChangingExistingPriority() {
        let existing = MicrophonePriorityConfiguration(prioritized: [usb, builtIn])

        let merged = existing.merging(available: [bluetooth, builtIn, usb])

        XCTAssertEqual(merged.prioritized.map(\.id), ["usb", "built-in", "airpods"])
    }

    func testExcludedDeviceDoesNotReappearWhenItReconnects() {
        var configuration = MicrophonePriorityConfiguration(
            prioritized: [builtIn, bluetooth]
        )
        configuration.exclude(id: bluetooth.id)

        configuration.merge(available: [bluetooth, builtIn])

        XCTAssertEqual(configuration.prioritized.map(\.id), ["built-in"])
        XCTAssertEqual(configuration.excluded.map(\.id), ["airpods"])
    }

    func testResolverUsesFirstAvailablePriority() {
        let configuration = MicrophonePriorityConfiguration(
            prioritized: [usb, builtIn, bluetooth]
        )

        XCTAssertEqual(
            configuration.preferredDevice(available: [bluetooth, builtIn])?.id,
            builtIn.id
        )
    }

    func testMoveUpdatesPriorityOrder() {
        var configuration = MicrophonePriorityConfiguration(
            prioritized: [bluetooth, builtIn, usb]
        )

        configuration.move(fromOffsets: IndexSet(integer: 2), toOffset: 0)

        XCTAssertEqual(configuration.prioritized.map(\.id), ["usb", "airpods", "built-in"])
    }

    func testRestoreAppendsDeviceAtLowestPriority() {
        var configuration = MicrophonePriorityConfiguration(
            prioritized: [builtIn],
            excluded: [usb]
        )

        configuration.restore(id: usb.id)

        XCTAssertEqual(configuration.prioritized.map(\.id), ["built-in", "usb"])
        XCTAssertTrue(configuration.excluded.isEmpty)
    }

    func testResolverDoesNotFallBackToExcludedDevice() {
        let configuration = MicrophonePriorityConfiguration(
            prioritized: [builtIn],
            excluded: [bluetooth]
        )

        XCTAssertNil(configuration.preferredDevice(available: [bluetooth]))
    }

    func testStoreRoundTripsConfiguration() throws {
        let suite = "MicrophonePriorityTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = MicrophonePriorityStore(defaults: defaults)
        let expected = MicrophonePriorityConfiguration(
            prioritized: [usb, builtIn],
            excluded: [bluetooth]
        )

        store.save(expected)

        XCTAssertTrue(store.hasStoredConfiguration)
        XCTAssertEqual(store.load(), expected)
    }
}
