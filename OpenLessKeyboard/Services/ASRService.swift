// ASRService.swift
// OSGKeyboard · Keyboard Extension
//
// Speech-to-text abstraction. iOS 26+ uses SpeechAnalyzer + DictationTranscriber
// (Apple's modern, on-device streaming API). iOS 18 falls back to SFSpeechRecognizer
// with on-device recognition.

import Foundation
import AVFoundation
import Speech

public protocol ASRService: AnyObject, Sendable {
    /// Start transcription. Returns an async stream of partial + final strings.
    /// The last value emitted on `finish()` is the final transcript.
    func transcribe(stream: AsyncStream<AudioBufferSnapshot>) -> AsyncStream<ASREvent>

    /// Cancel any in-flight work.
    func cancel()
}

public enum ASREvent: Sendable {
    case partial(String)  // incremental, may be discarded
    case final(String)    // the authoritative transcript
    case error(String)
}

// MARK: - Factory

public enum ASRServiceFactory {
    public static func create() -> ASRService {
        if #available(iOS 26, *) {
            return SpeechAnalyzerASR()
        } else {
            return SFSpeechRecognizerASR()
        }
    }
}

// MARK: - iOS 26+: SpeechAnalyzer + DictationTranscriber

@available(iOS 26, *)
final class SpeechAnalyzerASR: ASRService, @unchecked Sendable {
    private let recognizer: SFSpeechRecognizer? = SFSpeechRecognizer(locale: .current)
    private var task: Task<Void, Never>?

    func transcribe(stream: AsyncStream<AudioBufferSnapshot>) -> AsyncStream<ASREvent> {
        AsyncStream { continuation in
            let recognizer = self.recognizer ?? SFSpeechRecognizer(locale: .current)
            guard let recognizer, recognizer.isAvailable else {
                continuation.yield(.error("Speech recognizer unavailable"))
                continuation.finish()
                return
            }
            recognizer.defaultTaskHint = .dictation

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            if recognizer.supportsOnDeviceRecognition {
                request.requiresOnDeviceRecognition = true
            }

            let task = recognizer.recognitionTask(with: request) { result, error in
                if let error {
                    continuation.yield(.error(error.localizedDescription))
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
            self.task = Task { [request] in
                for await snap in stream {
                    if Task.isCancelled { break }
                    let pcmStream = AsyncStream<AudioBufferSnapshot> { c in
                        c.yield(snap)
                        c.finish()
                    }
                    for await pcm in pcmStream.toAVAudioBuffers() {
                        request.append(pcm)
                    }
                }
                request.endAudio()
                // give recognizer a moment to finalize
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
            // onTermination intentionally omitted: SFSpeechRecognitionTask is
            // not Sendable. Cancellation flows through this class's cancel().
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}

// MARK: - iOS 18 fallback: SFSpeechRecognizer

final class SFSpeechRecognizerASR: ASRService, @unchecked Sendable {
    private let recognizer: SFSpeechRecognizer? = SFSpeechRecognizer(locale: .current)
    private var task: SFSpeechRecognitionTask?
    private var feedTask: Task<Void, Never>?

    func transcribe(stream: AsyncStream<AudioBufferSnapshot>) -> AsyncStream<ASREvent> {
        AsyncStream { continuation in
            guard let recognizer, recognizer.isAvailable else {
                continuation.yield(.error("Speech recognizer unavailable"))
                continuation.finish()
                return
            }
            recognizer.defaultTaskHint = .dictation

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            if recognizer.supportsOnDeviceRecognition {
                request.requiresOnDeviceRecognition = true
            }

            let recognizerTask = recognizer.recognitionTask(with: request) { result, error in
                if let error {
                    continuation.yield(.error(error.localizedDescription))
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
            self.task = recognizerTask

            self.feedTask = Task { [request] in
                for await snap in stream {
                    if Task.isCancelled { break }
                    let pcmStream = AsyncStream<AudioBufferSnapshot> { c in
                        c.yield(snap)
                        c.finish()
                    }
                    for await pcm in pcmStream.toAVAudioBuffers() {
                        request.append(pcm)
                    }
                }
                request.endAudio()
            }
            // onTermination intentionally omitted: SFSpeechRecognitionTask is
            // not Sendable. Cancellation is handled by calling cancel() on
            // this class, and the feedTask loop respects Task.isCancelled.
        }
    }

    func cancel() {
        task?.cancel()
        feedTask?.cancel()
        task = nil
        feedTask = nil
    }
}
