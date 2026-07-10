// MacSpeechLocalASR.swift
// OSGKeyboard · Mac
//
// Apple Speech framework fallback for local engine mode. Writes PCM to a
// temp WAV and runs `SFSpeechURLRecognitionRequest`.

import AVFoundation
import Foundation
import Speech

enum MacSpeechLocalASR {
    /// Shared resume-once state for one recognition run. The recognizer
    /// callback (delivered on an arbitrary Speech queue) and the timeout task
    /// race to finish, and a `CheckedContinuation` must resume exactly once,
    /// so both go through this lock-guarded gate. It also retains the
    /// `SFSpeechRecognitionTask` so the losing/failing path can cancel it.
    private final class RecognitionSession: @unchecked Sendable {
        private let lock = NSLock()
        private var isResumed = false
        private var task: SFSpeechRecognitionTask?
        private var timeoutTask: Task<Void, Never>?

        func retain(_ task: SFSpeechRecognitionTask) {
            lock.lock()
            self.task = task
            let alreadyResumed = isResumed
            lock.unlock()
            // Timeout won the race before the task handle was stored.
            if alreadyResumed { task.cancel() }
        }

        func retainTimeout(_ task: Task<Void, Never>) {
            lock.lock()
            timeoutTask = task
            let alreadyResumed = isResumed
            lock.unlock()
            // Recognition finished before the handle landed — stop the timer.
            if alreadyResumed { task.cancel() }
        }

        /// Returns `true` exactly once across all callers; the winner may
        /// resume the continuation. Pass `cancellingTask: true` on failure
        /// paths so the in-flight recognition stops doing work. The winner
        /// also cancels the timeout task so it doesn't keep the session (and
        /// continuation captures) alive for the rest of its sleep.
        func claimResume(cancellingTask: Bool) -> Bool {
            lock.lock()
            guard !isResumed else {
                lock.unlock()
                return false
            }
            isResumed = true
            let task = self.task
            let timeout = timeoutTask
            lock.unlock()
            if cancellingTask { task?.cancel() }
            timeout?.cancel()
            return true
        }
    }

    static func transcribe(samples: [Float], locale: Locale, bias: LocalASRBiasPayload? = nil) async throws -> String {
        let auth = await requestAuthorization()
        guard auth == .authorized else { throw MacLocalASRError.speechDenied }

        if Self.isChineseLocale(locale) {
            CustomLanguageModelManager.shared.prepareInBackgroundIfNeeded()
            _ = try? await CustomLanguageModelManager.shared.prepareIfNeeded()
        }

        let wavURL = try writeTemporaryWAV(samples: samples, sampleRate: 16_000)
        defer { try? FileManager.default.removeItem(at: wavURL) }

        let recognizer = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer()
        guard let recognizer, recognizer.isAvailable else {
            throw MacLocalASRError.speechFailed("Speech recognizer unavailable")
        }
        // The request below sets `requiresOnDeviceRecognition = true`, which
        // fails (or worse, never produces a final result) when the on-device
        // model for the locale is missing — fail fast with a clear error.
        guard recognizer.supportsOnDeviceRecognition else {
            throw MacLocalASRError.speechFailed(
                "On-device speech recognition is not available for \(recognizer.locale.identifier). Download the language in System Settings → Keyboard → Dictation."
            )
        }

        // Overall deadline: recognition of a file is normally much faster than
        // realtime, so 2× audio length with a 30 s floor is generous. Without
        // it, empty audio / cancellation / a missing model can leave the
        // callback silent forever and the continuation never resumes.
        let audioSeconds = Double(samples.count) / 16_000
        let timeoutSeconds = max(30.0, audioSeconds * 2)
        let session = RecognitionSession()

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            let request = SFSpeechURLRecognitionRequest(url: wavURL)
            request.shouldReportPartialResults = false
            CustomLanguageModelManager.applyCustomLanguageModel(
                to: request,
                locale: locale,
                bias: bias
            )

            let task = recognizer.recognitionTask(with: request) { result, error in
                if let error {
                    if session.claimResume(cancellingTask: true) {
                        continuation.resume(throwing: MacLocalASRError.speechFailed(error.localizedDescription))
                    }
                    return
                }
                // Non-final callbacks carry no usable transcript yet; if a
                // final result never arrives, the timeout below resumes us.
                guard let result, result.isFinal else { return }
                guard session.claimResume(cancellingTask: false) else { return }
                let text = result.bestTranscription.formattedString
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if text.isEmpty {
                    continuation.resume(throwing: MacLocalASRError.emptyTranscript)
                } else {
                    continuation.resume(returning: text)
                }
            }
            session.retain(task)

            let timeout = Task {
                try? await Task.sleep(for: .seconds(timeoutSeconds))
                guard !Task.isCancelled else { return }
                if session.claimResume(cancellingTask: true) {
                    continuation.resume(throwing: MacLocalASRError.speechFailed("Speech recognition timed out"))
                }
            }
            session.retainTimeout(timeout)
        }
    }

    private static func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    private static func writeTemporaryWAV(samples: [Float], sampleRate: Int) throws -> URL {
        let wav = PCMSampleWavEncoder.encode(samples: samples, sampleRate: sampleRate)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("osg-mac-asr-\(UUID().uuidString).wav")
        try wav.write(to: url)
        return url
    }

    private static func isChineseLocale(_ locale: Locale) -> Bool {
        locale.identifier(.bcp47).lowercased().hasPrefix("zh")
    }
}
