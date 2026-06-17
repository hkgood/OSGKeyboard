// ASRService.swift
// OSGKeyboard · Keyboard Extension
//
// Speech-to-text abstraction over Apple's `SFSpeechRecognizer`.
// Honours a user-selected locale (auto / zh-CN / en-US / ja-JP …) so
// dictation is first-class for non-English languages.

import Foundation
import AVFoundation
import Speech
import os.lock
import OSGKeyboardShared

// MARK: - Sendable conformance

// `AVAudioPCMBuffer` and `SFSpeechRecognitionTask` are not Sendable. We
// only ever access them serially — the PCM buffer is built and consumed
// inside a single Task, and the recogniser task is cancelled but never
// shared concurrently — so an unchecked conformance is sound here.
extension AVAudioPCMBuffer: @unchecked @retroactive Sendable {}
extension SFSpeechRecognitionTask: @unchecked @retroactive Sendable {}

// MARK: - Protocol

public protocol ASRService: Sendable {
    /// Start a transcription session. The returned stream emits `.partial`
    /// updates and exactly one `.final` (or `.error`) before finishing.
    func transcribe(
        stream: AsyncStream<AudioBufferSnapshot>,
        locale: Locale
    ) -> AsyncStream<ASREvent>

    /// Cancel any in-flight recognition and tear down its tasks.
    func cancel()
}

public enum ASREvent: Sendable, Equatable {
    case partial(String)
    case final(String)
    case error(String)
}

// MARK: - Factory

public enum ASRServiceFactory {
    public static func make() -> ASRService {
        AppleSpeechASR()
    }
}

// MARK: - Apple Speech implementation

final class AppleSpeechASR: ASRService, @unchecked Sendable {

    private let lock = OSAllocatedUnfairLock()
    private var recognizerTask: SFSpeechRecognitionTask?
    private var feedTask: Task<Void, Never>?

    func transcribe(
        stream: AsyncStream<AudioBufferSnapshot>,
        locale: Locale
    ) -> AsyncStream<ASREvent> {
        AsyncStream { continuation in
            let recognizer = SFSpeechRecognizer(locale: locale)
                ?? SFSpeechRecognizer(locale: .current)
            guard let recognizer, recognizer.isAvailable else {
                continuation.yield(.error("Speech recognizer unavailable for \(locale.identifier)"))
                continuation.finish()
                return
            }
            recognizer.defaultTaskHint = .dictation

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition

            let task = recognizer.recognitionTask(with: request) { result, error in
                if let error {
                    let nsErr = error as NSError
                    // Codes 203 / 1110 = "no speech detected" — a normal exit.
                    if nsErr.code == 203 || nsErr.code == 1110 {
                        continuation.yield(.final(""))
                    } else {
                        continuation.yield(.error(error.localizedDescription))
                    }
                    continuation.finish()
                    return
                }
                guard let result else { return }
                if result.isFinal {
                    continuation.yield(.final(result.bestTranscription.formattedString))
                    continuation.finish()
                } else {
                    continuation.yield(.partial(result.bestTranscription.formattedString))
                }
            }

            self.lock.withLock { self.recognizerTask = task }

            // Feed audio: for each snapshot, build a 16 kHz mono Float32
            // PCM buffer and immediately `request.append(pcm)`. The PCM
            // buffer never leaves this task, so it doesn't need to be
            // Sendable.
            let feedFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: 16_000,
                channels: 1,
                interleaved: false
            )!
            self.feedTask = Task { [request] in
                for await snap in stream {
                    if Task.isCancelled { break }
                    guard !snap.samples.isEmpty,
                          let pcm = AVAudioPCMBuffer(
                            pcmFormat: feedFormat,
                            frameCapacity: AVAudioFrameCount(snap.samples.count)
                          )
                    else { continue }
                    pcm.frameLength = AVAudioFrameCount(snap.samples.count)
                    if let dst = pcm.floatChannelData?[0] {
                        snap.samples.withUnsafeBufferPointer { src in
                            if let base = src.baseAddress {
                                memcpy(dst, base, snap.samples.count * MemoryLayout<Float>.size)
                            }
                        }
                    }
                    request.append(pcm)
                }
                if !Task.isCancelled {
                    request.endAudio()
                }
            }

            continuation.onTermination = { @Sendable [weak self] _ in
                self?.cancel()
            }
        }
    }

    func cancel() {
        let (recTask, feedT) = lock.withLock { () -> (SFSpeechRecognitionTask?, Task<Void, Never>?) in
            let r = self.recognizerTask
            let f = self.feedTask
            self.recognizerTask = nil
            self.feedTask = nil
            return (r, f)
        }
        recTask?.cancel()
        feedT?.cancel()
    }
}
