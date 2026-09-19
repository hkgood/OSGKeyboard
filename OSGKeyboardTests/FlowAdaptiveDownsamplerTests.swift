// FlowAdaptiveDownsamplerTests.swift
// OSGKeyboard · Tests
//
// `AVAudioEngine.installTap(format:)` raises an UNCATCHABLE NSException when
// the format handed to it no longer matches the input node's live format, and
// that kills the whole app. The fix everywhere is the same: install with
// `format: nil` and let this resampler absorb whatever rate actually arrives.
//
// These tests pin the behaviour that makes `format: nil` safe — converting
// across a mid-stream route change — plus the numeric clamp that keeps a
// degenerate route from trapping on the realtime audio thread.

import AVFoundation
@testable import OSGKeyboardHostSupport
import XCTest

final class FlowAdaptiveDownsamplerTests: XCTestCase {
    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16_000,
        channels: 1,
        interleaved: false
    )

    private func makeBuffer(sampleRate: Double, frames: AVAudioFrameCount) -> AVAudioPCMBuffer? {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        ), let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else {
            return nil
        }
        buffer.frameLength = frames
        // A quiet ramp: silence would also convert, but non-zero samples prove
        // the converter actually ran rather than handing back an empty scratch.
        if let channel = buffer.floatChannelData?[0] {
            for index in 0..<Int(frames) {
                channel[index] = Float(index % 64) / 64.0 * 0.1
            }
        }
        return buffer
    }

    func testConvertsHardwareRateToTargetRate() throws {
        let target = try XCTUnwrap(targetFormat)
        let downsampler = FlowAdaptiveDownsampler(targetFormat: target)
        let buffer = try XCTUnwrap(makeBuffer(sampleRate: 48_000, frames: 4_096))

        guard case .converted(let output) = downsampler.convertReusingScratch(buffer) else {
            return XCTFail("expected a converted buffer for a 48 kHz tap")
        }
        XCTAssertEqual(output.format.sampleRate, 16_000)
        XCTAssertGreaterThan(output.frameLength, 0)
    }

    func testRebuildsConverterWhenTheRouteChangesMidStream() throws {
        let target = try XCTUnwrap(targetFormat)
        let downsampler = FlowAdaptiveDownsampler(targetFormat: target)

        // Built-in mic …
        let wideband = try XCTUnwrap(makeBuffer(sampleRate: 48_000, frames: 4_096))
        guard case .converted = downsampler.convertReusingScratch(wideband) else {
            return XCTFail("expected the first buffer to convert")
        }

        // … then the user connects a headset and the node switches rate. This
        // is the exact transition that crashed a tap installed with an
        // explicit format.
        let narrowband = try XCTUnwrap(makeBuffer(sampleRate: 24_000, frames: 4_096))
        guard case .converted(let output) = downsampler.convertReusingScratch(narrowband) else {
            return XCTFail("expected the post-route-change buffer to convert")
        }
        XCTAssertEqual(output.format.sampleRate, 16_000)
        XCTAssertGreaterThan(output.frameLength, 0)
    }

    func testUpsamplesSubTargetTelephonyRates() throws {
        let target = try XCTUnwrap(targetFormat)
        let downsampler = FlowAdaptiveDownsampler(targetFormat: target)
        let buffer = try XCTUnwrap(makeBuffer(sampleRate: 8_000, frames: 4_096))

        // 4096 × (16k / 8k) = 8192 frames — exactly the scratch capacity, so
        // this is the boundary the headroom constant was sized for.
        guard case .converted(let output) = downsampler.convertReusingScratch(buffer) else {
            return XCTFail("expected an 8 kHz telephony route to convert")
        }
        XCTAssertGreaterThan(output.frameLength, 0)
    }

    func testGrowsTheScratchForAnOversizedTapSliceInsteadOfDroppingAudio() throws {
        let target = try XCTUnwrap(targetFormat)
        let downsampler = FlowAdaptiveDownsampler(targetFormat: target)
        // 4096 × (16k / 4k) = 16,384 output frames against the 8,192-frame
        // starting scratch. `bufferSize:` is only a hint — macOS hands pro
        // interfaces larger slices — so this must grow, not drop the audio.
        let buffer = try XCTUnwrap(makeBuffer(sampleRate: 4_000, frames: 4_096))

        guard case .converted(let output) = downsampler.convertReusingScratch(buffer) else {
            return XCTFail("expected an oversized slice to grow the scratch and convert")
        }
        XCTAssertGreaterThan(output.frameLength, 8_192)

        // The grown scratch is reused: a following ordinary buffer must still
        // convert, and must not report the previous buffer's frame count.
        let followUp = try XCTUnwrap(makeBuffer(sampleRate: 48_000, frames: 4_096))
        guard case .converted(let second) = downsampler.convertReusingScratch(followUp) else {
            return XCTFail("expected the next buffer to convert against the grown scratch")
        }
        XCTAssertLessThan(second.frameLength, output.frameLength)
    }

    func testRefusesAConversionPastTheGrowthCeiling() throws {
        let target = try XCTUnwrap(targetFormat)
        let downsampler = FlowAdaptiveDownsampler(targetFormat: target)
        // 32,768 × (16k / 8k) = 65,536 output frames — past the 32,768 ceiling.
        // Growth has a limit so a nonsense ratio cannot allocate without bound
        // on the realtime thread; past it, dropping the frame is correct.
        let buffer = try XCTUnwrap(makeBuffer(sampleRate: 8_000, frames: 32_768))

        guard case .failed(let failure, _, let inputFrames, let wantedFrames) =
                downsampler.convertReusingScratch(buffer) else {
            return XCTFail("expected a conversion past the ceiling to be reported")
        }
        XCTAssertEqual(failure, .scratchOverflow)
        XCTAssertEqual(inputFrames, 32_768)
        // The report still carries a finite, usable number for diagnostics.
        XCTAssertGreaterThan(wantedFrames, 0)
    }

    func testUnsupportedRateFailsCleanlyRatherThanTrapping() throws {
        let target = try XCTUnwrap(targetFormat)
        let downsampler = FlowAdaptiveDownsampler(targetFormat: target)
        // A 1 Hz "route" is not something `AVAudioConverter` will build for.
        // The contract that matters is the same either way: report the drop,
        // never trap.
        let buffer = try XCTUnwrap(makeBuffer(sampleRate: 1, frames: 4_096))

        guard case .failed(let failure, _, _, _) =
                downsampler.convertReusingScratch(buffer) else {
            return XCTFail("expected a degenerate rate to be reported, not converted")
        }
        XCTAssertTrue(
            failure == .converterCreateFailed || failure == .scratchOverflow,
            "unexpected failure \(failure.label)"
        )
    }

    func testRecoversAfterADroppedFrame() throws {
        let target = try XCTUnwrap(targetFormat)
        let downsampler = FlowAdaptiveDownsampler(targetFormat: target)
        let degenerate = try XCTUnwrap(makeBuffer(sampleRate: 1, frames: 4_096))
        _ = downsampler.convertReusingScratch(degenerate)

        // One bad frame must not wedge the resampler for the rest of the
        // session — the route can recover.
        let healthy = try XCTUnwrap(makeBuffer(sampleRate: 48_000, frames: 4_096))
        guard case .converted(let output) = downsampler.convertReusingScratch(healthy) else {
            return XCTFail("expected the resampler to recover after a dropped frame")
        }
        XCTAssertGreaterThan(output.frameLength, 0)
    }
}
