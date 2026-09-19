// FlowAdaptiveDownsampler.swift
// OSGKeyboard · HostSupport
//
// Shared route-adaptive resampler for every realtime `installTap` consumer
// (`FlowContinuousCapture`, `LiveDictationController`, and the Mac recorder's
// iOS sibling paths). Extracted so the crash-safe tap pattern lives in exactly
// one place: a second copy of this logic is how the preview surface ended up
// still installing taps with a stale explicit format.

import AVFoundation
import Foundation
import os

/// Why a tap buffer never reached the recogniser.
///
/// Recorded as a plain integer on the realtime audio thread and rendered on the
/// main actor — calling `Logger` inside the tap would allocate and risk
/// priority inversion. Each of these was previously a bare `return`, which is
/// what made "waveform moves but the transcript is empty" invisible: levels and
/// the audio-proof timestamp are taken from the *raw* buffer, before
/// conversion, so they keep looking healthy while ASR receives nothing.
public enum FlowDownsampleFailure: Int, Sendable {
    case none = 0
    case invalidSourceFormat
    case converterCreateFailed
    case scratchOverflow
    case converterError
    case emptyOutput

    public var label: String {
        switch self {
        case .none: return "none"
        case .invalidSourceFormat: return "invalidSourceFormat"
        case .converterCreateFailed: return "converterCreateFailed"
        case .scratchOverflow: return "scratchOverflow"
        case .converterError: return "converterError"
        case .emptyOutput: return "emptyOutput"
        }
    }
}

/// Outcome of one realtime conversion attempt. Carries the reason (and the
/// formats involved) so the drop can be explained after the fact.
enum FlowDownsampleOutcome {
    case converted(AVAudioPCMBuffer)
    case failed(
        failure: FlowDownsampleFailure,
        sourceRate: Double,
        inputFrames: Int,
        wantedFrames: Int
    )
}

/// Route-adaptive downsampling converter, safe to call from the realtime tap.
///
/// `AVAudioEngine.installTap(format:)` traps with an **uncatchable** NSException
/// when the format passed to it does not match the input node's *live* format.
/// After an audio-route change — which the on-device `SpeechAnalyzer` triggers
/// during warmup by reconfiguring the shared `AVAudioSession`, and which any
/// Bluetooth/headset swap triggers at will — the value returned by
/// `inputNode.outputFormat(forBus:)` can lag behind the real hardware rate
/// (e.g. it reports 48 kHz while the node has already switched to 24 kHz).
/// Installing a tap with that stale explicit format crashes the whole app
/// (`Failed to create tap due to format mismatch`).
///
/// Every caller must therefore install the tap with `format: nil` (which always
/// uses the node's live format) and rebuild the sample-rate converter *here*
/// whenever the incoming buffer's format actually changes, so downsampling to
/// the ASR target rate is always valid regardless of route churn.
final class FlowAdaptiveDownsampler: @unchecked Sendable {
    // `AVAudioConverter` / `AVAudioFormat` / `AVAudioPCMBuffer` are not
    // `Sendable`, so the state is guarded manually via the unchecked lock
    // APIs. The scratch output buffer is REUSED across tap callbacks —
    // allocating on the realtime audio thread risks priority inversion, and
    // taps on one bus are serialized, so a single scratch is safe as long as
    // callers copy its contents out before returning (AudioBufferSnapshot
    // does exactly that).
    private struct State {
        var converter: AVAudioConverter
        var source: AVAudioFormat
        var scratch: AVAudioPCMBuffer
    }

    private let lock = OSAllocatedUnfairLock<State?>(uncheckedState: nil)
    let targetFormat: AVAudioFormat

    /// Starting headroom for the reusable output buffer. Taps normally deliver
    /// ≤4096 input frames; output frames = input × (16k / hardwareRate), which
    /// exceeds input only for sub-16 kHz hardware (rare telephony routes), so
    /// 2× the requested tap size covers the common case without allocating.
    private static let initialScratchCapacity: AVAudioFrameCount = 8_192

    /// Ceiling for one-time growth. `bufferSize:` is a hint — macOS in
    /// particular hands pro audio interfaces larger slices than requested — and
    /// silently dropping those frames would be a worse bug than the allocation.
    /// Anything past this is a nonsense ratio, not a real route.
    private static let maxScratchCapacity: AVAudioFrameCount = 32_768

    init(targetFormat: AVAudioFormat) {
        self.targetFormat = targetFormat
    }

    /// Downsamples `buffer` into the reusable scratch buffer and returns it,
    /// rebuilding the converter lazily when the hardware route (and thus the
    /// source format) changes. The returned buffer is only valid until the
    /// next call — copy its samples out synchronously.
    func convertReusingScratch(_ buffer: AVAudioPCMBuffer) -> FlowDownsampleOutcome {
        let sourceFormat = buffer.format
        let sourceRate = sourceFormat.sampleRate
        let inputFrames = Int(buffer.frameLength)
        guard sourceRate > 0 else {
            return .failed(
                failure: .invalidSourceFormat,
                sourceRate: sourceRate,
                inputFrames: inputFrames,
                wantedFrames: 0
            )
        }
        return lock.withLockUnchecked { state -> FlowDownsampleOutcome in
            if state == nil || state!.source != sourceFormat {
                guard let converter = AVAudioConverter(from: sourceFormat, to: targetFormat),
                      let scratch = AVAudioPCMBuffer(
                        pcmFormat: targetFormat,
                        frameCapacity: Self.initialScratchCapacity
                      ) else {
                    state = nil
                    return .failed(
                        failure: .converterCreateFailed,
                        sourceRate: sourceRate,
                        inputFrames: inputFrames,
                        wantedFrames: 0
                    )
                }
                state = State(converter: converter, source: sourceFormat, scratch: scratch)
            }
            guard var current = state else {
                return .failed(
                    failure: .converterCreateFailed,
                    sourceRate: sourceRate,
                    inputFrames: inputFrames,
                    wantedFrames: 0
                )
            }

            // Stay in `Double` until the range is proven: `AVAudioFrameCount(_:)`
            // traps on NaN / infinite / out-of-range input, and a degenerate
            // route (sub-1 Hz `sourceRate`) would otherwise crash the realtime
            // render thread instead of dropping one frame.
            let wantedExact = Double(buffer.frameLength) * targetFormat.sampleRate / sourceRate
            let ceiling = Double(Self.maxScratchCapacity)
            guard wantedExact.isFinite, wantedExact >= 1, wantedExact <= ceiling else {
                return .failed(
                    failure: .scratchOverflow,
                    sourceRate: sourceRate,
                    inputFrames: inputFrames,
                    wantedFrames: wantedExact.isFinite ? Int(min(wantedExact, ceiling)) : 0
                )
            }
            let wanted = AVAudioFrameCount(wantedExact)

            if wanted > current.scratch.frameCapacity {
                // Grow once, with headroom, rather than dropping audio for the
                // rest of the session. This costs an allocation on the realtime
                // thread, which is exactly what the reusable scratch exists to
                // avoid — but it happens at most a couple of times per route,
                // the same as the converter rebuild above, and losing the audio
                // is the worse trade.
                let grownCapacity = min(
                    max(wanted &* 2, Self.initialScratchCapacity),
                    Self.maxScratchCapacity
                )
                guard let grown = AVAudioPCMBuffer(
                    pcmFormat: targetFormat,
                    frameCapacity: grownCapacity
                ) else {
                    return .failed(
                        failure: .scratchOverflow,
                        sourceRate: sourceRate,
                        inputFrames: inputFrames,
                        wantedFrames: Int(wanted)
                    )
                }
                current.scratch = grown
                state = current
            }
            current.scratch.frameLength = 0

            // ONE-SHOT input: the converter keeps pulling until the output
            // buffer's frameCapacity is full, and the scratch is deliberately
            // oversized — feeding the same tap buffer on every pull would
            // duplicate the audio ~6× (stuttering ASR input). After the
            // single feed we report "ran dry", so the expected status is
            // `.inputRanDry` (output not full), not `.haveData`.
            let provided = OSAllocatedUnfairLock(initialState: false)
            var error: NSError?
            let status = current.converter.convert(to: current.scratch, error: &error) { _, outStatus in
                if provided.withLock({ $0 }) {
                    outStatus.pointee = .noDataNow
                    return nil
                }
                provided.withLock { $0 = true }
                outStatus.pointee = .haveData
                return buffer
            }
            guard status != .error, error == nil else {
                return .failed(
                    failure: .converterError,
                    sourceRate: sourceRate,
                    inputFrames: inputFrames,
                    wantedFrames: Int(wanted)
                )
            }
            guard current.scratch.frameLength > 0 else {
                return .failed(
                    failure: .emptyOutput,
                    sourceRate: sourceRate,
                    inputFrames: inputFrames,
                    wantedFrames: Int(wanted)
                )
            }
            return .converted(current.scratch)
        }
    }
}
