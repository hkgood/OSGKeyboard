// MacSpeechLocalASR.swift
// OSGKeyboard · Mac
//
// Apple Speech framework fallback for local engine mode. Writes PCM to a
// temp WAV and runs `SFSpeechURLRecognitionRequest`.

import AVFoundation
import Foundation
import Speech

enum MacSpeechLocalASR {
    static func transcribe(samples: [Float], locale: Locale) async throws -> String {
        let auth = await requestAuthorization()
        guard auth == .authorized else { throw MacLocalASRError.speechDenied }

        let wavURL = try writeTemporaryWAV(samples: samples, sampleRate: 16_000)
        defer { try? FileManager.default.removeItem(at: wavURL) }

        let recognizer = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer()
        guard let recognizer, recognizer.isAvailable else {
            throw MacLocalASRError.speechFailed("Speech recognizer unavailable")
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = SFSpeechURLRecognitionRequest(url: wavURL)
            request.shouldReportPartialResults = false
            request.requiresOnDeviceRecognition = true

            recognizer.recognitionTask(with: request) { result, error in
                if let error {
                    continuation.resume(throwing: MacLocalASRError.speechFailed(error.localizedDescription))
                    return
                }
                guard let result, result.isFinal else { return }
                let text = result.bestTranscription.formattedString
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if text.isEmpty {
                    continuation.resume(throwing: MacLocalASRError.emptyTranscript)
                } else {
                    continuation.resume(returning: text)
                }
            }
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
}
