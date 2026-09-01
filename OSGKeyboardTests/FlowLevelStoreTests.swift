// FlowLevelStoreTests.swift
// OSGKeyboardTests
//
// Regression cover for the waveform bar arithmetic. `calculateLevels` runs on
// the AVAudioEngine realtime thread, where a reversed `start..<end` range is an
// uncatchable Swift trap that takes the whole host app down mid-dictation — so
// the short-buffer cases below are the ones that matter, not the happy path.

import AVFoundation
@testable import OSGKeyboardHostSupport
import XCTest

final class FlowLevelStoreTests: XCTestCase {
    /// Mirrors `FlowContinuousCapture.levelBarCount`, which cannot be read here
    /// directly: it lives on a `@MainActor` type and this suite is nonisolated.
    /// `testBarCountMatchesShippedConstant` keeps the two from drifting.
    private let barCount = 24

    @MainActor
    func testBarCountMatchesShippedConstant() {
        XCTAssertEqual(
            barCount,
            FlowContinuousCapture.levelBarCount,
            "Bar count drifted — the short-buffer cases below are sized to it"
        )
    }

    private func makeBuffer(frameLength: Int, amplitude: Float = 0.5) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48_000,
            channels: 1,
            interleaved: false
        )!
        // frameCapacity must be > 0 even when we want a zero-length buffer.
        let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(max(frameLength, 1))
        )!
        buffer.frameLength = AVAudioFrameCount(frameLength)
        if let channel = buffer.floatChannelData?[0] {
            for index in 0..<frameLength {
                channel[index] = amplitude
            }
        }
        return buffer
    }

    /// The shipped bar count is 24. Any tap buffer shorter than that used to
    /// drive the tail bars past `frameLength` and build a reversed range.
    func testShortBuffersDoNotTrap() {
        for frameLength in [0, 1, 2, 5, 10, 22, 23, 24, 25] {
            let levels = FlowLevelStore.calculateLevels(
                from: makeBuffer(frameLength: frameLength),
                barCount: barCount
            )
            XCTAssertEqual(
                levels.count,
                barCount,
                "frameLength=\(frameLength) must still produce a full bar array"
            )
            for level in levels {
                XCTAssertFalse(level.isNaN, "frameLength=\(frameLength) produced NaN")
                XCTAssertTrue(
                    (0...1).contains(level),
                    "frameLength=\(frameLength) produced out-of-range level \(level)"
                )
            }
        }
    }

    /// Bars past the available samples read as silence rather than crashing.
    func testBarsBeyondAvailableSamplesReadAsZero() {
        let levels = FlowLevelStore.calculateLevels(
            from: makeBuffer(frameLength: 10),
            barCount: barCount
        )
        XCTAssertEqual(levels.count, barCount)
        // 10 samples spread one-per-bar: the first 10 carry signal, the rest are empty.
        XCTAssertTrue(levels[0] > 0, "leading bars should carry the signal")
        for index in 10..<barCount {
            XCTAssertEqual(levels[index], 0, "bar \(index) has no samples and must read 0")
        }
    }

    /// Normal-sized tap buffers keep producing a full, non-silent waveform.
    func testTypicalBufferSizesProduceSignal() {
        for frameLength in [64, 441, 1_024, 4_096] {
            let levels = FlowLevelStore.calculateLevels(
                from: makeBuffer(frameLength: frameLength),
                barCount: barCount
            )
            XCTAssertEqual(levels.count, barCount)
            XCTAssertTrue(
                levels.allSatisfy { $0 > 0 },
                "frameLength=\(frameLength) should light every bar"
            )
        }
    }

    /// The instance path the audio tap actually calls.
    func testUpdateFromShortBufferKeepsSnapshotUsable() {
        let store = FlowLevelStore(barCount: barCount)
        store.update(from: makeBuffer(frameLength: 3), barCount: barCount)
        XCTAssertEqual(store.snapshot().count, barCount)
    }
}
