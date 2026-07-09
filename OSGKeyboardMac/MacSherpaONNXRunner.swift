// MacSherpaONNXRunner.swift
// OSGKeyboard · Mac
//
// Invokes the downloaded `sherpa-onnx-offline` binary for Sherpa-backed POC models.

import Foundation

enum MacSherpaONNXRunner {

    static func transcribeQwen3(
        samples: [Float],
        sampleRate: Int,
        locale: Locale,
        modelRoot: URL,
        layout: LocalASRModelLayout,
        runtimeBinary: URL,
        bias: LocalASRBiasPayload?
    ) async throws -> String {
        guard sampleRate == 16_000 else {
            throw MacLocalASRError.qwen3InferenceFailed("Sherpa expects 16 kHz audio")
        }
        guard let conv = layout.convFrontend,
              let encoder = layout.encoder,
              let decoder = layout.decoder,
              let tokenizer = layout.tokenizer else {
            throw MacLocalASRError.qwen3InferenceFailed("Incomplete Sherpa Qwen3 layout")
        }

        let wavURL = try writeTemporaryWAV(samples: samples, sampleRate: sampleRate)
        defer { try? FileManager.default.removeItem(at: wavURL) }

        var arguments = [
            "--qwen3-asr-conv-frontend=\(modelRoot.appendingPathComponent(conv).path)",
            "--qwen3-asr-encoder=\(modelRoot.appendingPathComponent(encoder).path)",
            "--qwen3-asr-decoder=\(modelRoot.appendingPathComponent(decoder).path)",
            "--qwen3-asr-tokenizer=\(modelRoot.appendingPathComponent(tokenizer).path)",
            "--qwen3-asr-max-new-tokens=512",
            "--num-threads=2",
        ]

        if let language = MacQwen3LanguageHint.from(locale: locale) {
            arguments.append("--qwen3-asr-language=\(language)")
        }

        if let hotwords = bias?.hardHotwords, !hotwords.isEmpty {
            arguments.append("--qwen3-asr-hotwords=\(hotwords.joined(separator: ","))")
        }

        arguments.append(wavURL.path)
        return try await run(binary: runtimeBinary, arguments: arguments)
    }

    static func transcribeSenseVoice(
        samples: [Float],
        sampleRate: Int,
        modelRoot: URL,
        layout: LocalASRModelLayout,
        runtimeBinary: URL
    ) async throws -> String {
        guard sampleRate == 16_000 else {
            throw MacLocalASRError.qwen3InferenceFailed("Sherpa expects 16 kHz audio")
        }
        guard let model = layout.senseVoiceModel,
              let tokens = layout.tokens else {
            throw MacLocalASRError.qwen3InferenceFailed("Incomplete SenseVoice layout")
        }

        let wavURL = try writeTemporaryWAV(samples: samples, sampleRate: sampleRate)
        defer { try? FileManager.default.removeItem(at: wavURL) }

        let arguments = [
            "--tokens=\(modelRoot.appendingPathComponent(tokens).path)",
            "--sense-voice-model=\(modelRoot.appendingPathComponent(model).path)",
            "--num-threads=2",
            wavURL.path,
        ]
        return try await run(binary: runtimeBinary, arguments: arguments)
    }

    static func transcribeParaformer(
        samples: [Float],
        sampleRate: Int,
        modelRoot: URL,
        layout: LocalASRModelLayout,
        runtimeBinary: URL
    ) async throws -> String {
        guard sampleRate == 16_000 else {
            throw MacLocalASRError.qwen3InferenceFailed("Sherpa expects 16 kHz audio")
        }
        guard let paraformer = layout.paraformerModel,
              let tokens = layout.tokens else {
            throw MacLocalASRError.qwen3InferenceFailed("Incomplete Paraformer layout")
        }

        let wavURL = try writeTemporaryWAV(samples: samples, sampleRate: sampleRate)
        defer { try? FileManager.default.removeItem(at: wavURL) }

        let arguments = [
            "--tokens=\(modelRoot.appendingPathComponent(tokens).path)",
            "--paraformer=\(modelRoot.appendingPathComponent(paraformer).path)",
            "--num-threads=2",
            wavURL.path,
        ]
        return try await run(binary: runtimeBinary, arguments: arguments)
    }

    // MARK: - Private

    private static func writeTemporaryWAV(samples: [Float], sampleRate: Int) throws -> URL {
        let data = PCMSampleWavEncoder.encode(samples: samples, sampleRate: sampleRate)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("osg-sherpa-\(UUID().uuidString).wav")
        try data.write(to: url, options: .atomic)
        return url
    }

    private static func run(binary: URL, arguments: [String]) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = binary
            process.arguments = arguments
            process.currentDirectoryURL = binary.deletingLastPathComponent()

            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            process.terminationHandler = { proc in
                let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let stdout = String(data: outputData, encoding: .utf8) ?? ""
                let stderr = String(data: errorData, encoding: .utf8) ?? ""

                guard proc.terminationStatus == 0 else {
                    let detail = stderr.isEmpty ? stdout : stderr
                    continuation.resume(
                        throwing: MacLocalASRError.qwen3InferenceFailed(
                            detail.trimmingCharacters(in: .whitespacesAndNewlines)
                        )
                    )
                    return
                }

                let text = parseTranscript(stdout: stdout)
                if text.isEmpty {
                    continuation.resume(throwing: MacLocalASRError.emptyTranscript)
                } else {
                    continuation.resume(returning: text)
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: MacLocalASRError.qwen3InferenceFailed(error.localizedDescription))
            }
        }
    }

    private static func parseTranscript(stdout: String) -> String {
        let lines = stdout
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        for line in lines.reversed() {
            if line.hasPrefix("{"), let data = line.data(using: .utf8),
               let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let text = object["text"] as? String {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
            if !line.hasPrefix("/"), !line.hasPrefix("--"), line.count > 1 {
                return line
            }
        }
        return ""
    }
}
