// FlowAudioSessionCoordinator.swift
// OSGKeyboard · Host Support
//
// Single owner for the shared iOS AVAudioSession used by Flow capture and
// Picture in Picture keep-alive. Keeping category transitions here prevents
// two independent state machines from racing the same process-wide session.

import AVFoundation
import Foundation
import OSGKeyboardShared

public enum FlowAudioRouteRecoveryPolicy {
    public static func shouldRebuild(
        reasonRaw: UInt,
        formatIsStable: Bool,
        engineIsRunning: Bool
    ) -> Bool {
        switch AVAudioSession.RouteChangeReason(rawValue: reasonRaw) {
        case .newDeviceAvailable, .oldDeviceUnavailable:
            return true
        case .categoryChange, .routeConfigurationChange:
            return !formatIsStable || !engineIsRunning
        default:
            return false
        }
    }
}

public struct FlowAudioSessionSnapshot: Sendable, Equatable {
    public let sampleRate: Double
    public let inputChannels: Int
    public let inputPortType: String
    public let inputPortUID: String
}

public final class FlowAudioEngineHandle: @unchecked Sendable {
    public let engine: AVAudioEngine

    public init(_ engine: AVAudioEngine) {
        self.engine = engine
    }
}

public final class FlowAudioSessionCoordinator: @unchecked Sendable {
    private struct CaptureActivation: Sendable {
        let snapshot: FlowAudioSessionSnapshot
        let preferredInputUID: String?
    }

    public enum Mode: Sendable, Equatable {
        case inactive
        case playback
        case capture
    }

    public static let shared = FlowAudioSessionCoordinator()

    private let session = AVAudioSession.sharedInstance()
    private let queue = DispatchQueue(
        label: "com.osgkeyboard.flow.audio-session",
        qos: .userInitiated
    )
    private var mode: Mode = .inactive
    private var active = false

    private init() {}

    public func activateCapture() async throws -> FlowAudioSessionSnapshot {
        let activation: CaptureActivation = try await perform {
            if self.mode != .capture {
                // `.voiceChat` turns on system speech DSP (noise suppression /
                // AGC). `.measurement` feeds near-raw PCM and is weak against
                // a competing talker in the same room.
                try self.session.setCategory(
                    .playAndRecord,
                    mode: FlowCaptureVoiceProcessing.captureMode,
                    options: FlowCaptureVoiceProcessing.captureOptions
                )
            }
            if !self.active {
                try self.session.setActive(true, options: .notifyOthersOnDeactivation)
                self.active = true
            }
            // When an HFP device is already connected, iOS can initially
            // report the built-in mic and switch to HFP after recording has
            // begun. Select the route before building AVAudioEngine so short
            // utterances do not land entirely inside that negotiation window.
            let hfp = self.session.availableInputs?.first(where: {
                $0.portType == .bluetoothHFP
            })
            if self.session.currentRoute.inputs.first?.portType != .bluetoothHFP,
               let hfp {
                do {
                    try self.session.setPreferredInput(hfp)
                } catch {
                    OSGDiag.log(
                        "preferred HFP input failed: \(error.localizedDescription)",
                        category: "flow"
                    )
                }
            } else {
                // Built-in near-talk preference (cardioid when available).
                FlowCaptureVoiceProcessing.preferNearTalkBuiltInMic(on: self.session)
            }
            self.mode = .capture
            return CaptureActivation(
                snapshot: self.makeSnapshot(),
                preferredInputUID: hfp?.uid
            )
        }
        return await waitForStableRoute(
            initial: activation.snapshot,
            preferredInputUID: activation.preferredInputUID
        )
    }

    public func activatePlayback() async -> Bool {
        do {
            _ = try await perform {
                // Once capture has established a stable playAndRecord route,
                // keep that active session between utterances. The engine and
                // tap are stopped separately, so the microphone is released,
                // while avoiding a category flip that eventually yields !pri
                // after repeated PiP/capture cycles.
                if self.active, self.mode == .capture {
                    return self.makeSnapshot()
                }
                if self.mode != .playback {
                    try self.session.setCategory(
                        .playback,
                        mode: .moviePlayback,
                        options: [.mixWithOthers]
                    )
                }
                if !self.active {
                    try self.session.setActive(true)
                    self.active = true
                }
                self.mode = .playback
                return self.makeSnapshot()
            }
            return true
        } catch {
            OSGDiag.log(
                "PiP audio session failed: \(error.localizedDescription)",
                category: "flow"
            )
            return false
        }
    }

    public func deactivate() {
        queue.async { [self] in
            guard active else { return }
            do {
                try session.setActive(false, options: .notifyOthersOnDeactivation)
                active = false
                mode = .inactive
            } catch {
                OSGDiag.log(
                    "audio session deactivate failed: \(error.localizedDescription)",
                    category: "flow"
                )
            }
        }
    }

    public func startEngine(_ handle: FlowAudioEngineHandle) async throws {
        try await perform {
            handle.engine.prepare()
            try handle.engine.start()
            return true
        }
    }

    public func stopEngine(_ handle: FlowAudioEngineHandle) async {
        _ = try? await perform {
            if handle.engine.isRunning {
                handle.engine.stop()
            }
            handle.engine.reset()
            return true
        }
    }

    public func enqueueStopEngine(_ handle: FlowAudioEngineHandle) {
        queue.async {
            if handle.engine.isRunning {
                handle.engine.stop()
            }
            handle.engine.reset()
        }
    }

    private func waitForStableRoute(
        initial: FlowAudioSessionSnapshot,
        preferredInputUID: String?,
        timeout: TimeInterval = 1.5
    ) async -> FlowAudioSessionSnapshot {
        let deadline = Date().addingTimeInterval(timeout)
        var previous = initial
        var stableReadCount = 0
        while Date() < deadline {
            try? await Task.sleep(nanoseconds: 50_000_000)
            let current = await snapshot()
            let preferredRouteReached = preferredInputUID == nil
                || current.inputPortUID == preferredInputUID
            if current == previous, current.sampleRate > 0,
               current.inputChannels > 0, preferredRouteReached {
                stableReadCount += 1
            } else {
                stableReadCount = 0
            }
            if stableReadCount >= 4 {
                return current
            }
            previous = current
        }
        return previous
    }

    private func snapshot() async -> FlowAudioSessionSnapshot {
        (try? await perform { self.makeSnapshot() })
            ?? FlowAudioSessionSnapshot(
                sampleRate: 0,
                inputChannels: 0,
                inputPortType: "none",
                inputPortUID: ""
            )
    }

    private func makeSnapshot() -> FlowAudioSessionSnapshot {
        let input = session.currentRoute.inputs.first
        return FlowAudioSessionSnapshot(
            sampleRate: session.sampleRate,
            inputChannels: session.inputNumberOfChannels,
            inputPortType: input?.portType.rawValue ?? "none",
            inputPortUID: input?.uid ?? ""
        )
    }

    private func perform<T: Sendable>(
        _ operation: @escaping @Sendable () throws -> T
    ) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                continuation.resume(with: Result { try operation() })
            }
        }
    }
}
