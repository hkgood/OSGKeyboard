// FlowUtterancePCMStoreTests.swift
// OSGKeyboardTests

@testable import OSGKeyboardShared
import XCTest

final class FlowUtterancePCMStoreTests: XCTestCase {

    func testAppendAndConsume() {
        let store = FlowUtterancePCMStore(maxSampleCount: 100)
        store.append([1, 2, 3])
        store.append([4, 5])
        XCTAssertEqual(store.sampleCount, 5)
        XCTAssertEqual(store.consume(), [1, 2, 3, 4, 5])
        XCTAssertEqual(store.sampleCount, 0)
    }

    func testTrimsOldestWhenOverCap() {
        let store = FlowUtterancePCMStore(maxSampleCount: 4)
        store.append([1, 2, 3, 4, 5])
        XCTAssertEqual(store.consume(), [2, 3, 4, 5])
    }

    func testSnapshotDoesNotClear() {
        let store = FlowUtterancePCMStore(maxSampleCount: 100)
        store.append([0.1, -0.2])
        XCTAssertEqual(store.snapshot(), [0.1, -0.2])
        XCTAssertEqual(store.sampleCount, 2)
        XCTAssertEqual(store.consume(), [0.1, -0.2])
    }
}
