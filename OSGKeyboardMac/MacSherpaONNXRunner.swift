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
            if line.hasPrefix("{") {
                // Sherpa's JSON result line (`{"text": ..., "lang": ..., ...}`).
                // Trust only its `text` field — including when it's empty
                // (silence/no-speech) — and never fall through to the raw
                // JSON below, or the JSON blob itself gets inserted as text.
                if let data = line.data(using: .utf8),
                   let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let text = object["text"] as? String {
                    return sanitizeTranscript(text)
                }
                continue
            }
            if isMetadataNoiseLine(line) { continue }
            if !line.hasPrefix("/"), !line.hasPrefix("--"), line.count > 1 {
                let cleaned = sanitizeTranscript(line)
                if !cleaned.isEmpty { return cleaned }
            }
        }
        return ""
    }

    /// Qwen3-ASR (via sherpa-onnx) often prefixes the transcript with a
    /// scaffold such as `language Chinese<asr_text>…`. Older runtimes leave
    /// that intact in `result.text`; incomplete generations can even stop at
    /// the bare word `language`. Strip the scaffold so only spoken text remains.
    private static func sanitizeTranscript(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return "" }

        // Prefer the payload after the last `<asr_text>` marker.
        if let marker = text.range(of: "<asr_text>", options: .backwards) {
            text = String(text[marker.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } else if let match = text.range(
            of: #"^language\s+\S+\s*"#,
            options: [.regularExpression, .caseInsensitive]
        ) {
            // Fallback when the marker token was lost but the language prefix remains.
            text = String(text[match.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Drop leftover control tokens / bare scaffold words.
        if isMetadataNoiseLine(text) { return "" }
        return text
    }

    /// Lines that are sherpa/Qwen metadata rather than spoken content.
    private static func isMetadataNoiseLine(_ line: String) -> Bool {
        let lowered = line.lowercased()
        switch lowered {
        case "language", "emotion", "event", "text",
             "<asr_text>", "</asr_text>", "<|im_end|>":
            return true
        default:
            // Exact scaffold with no spoken payload, e.g. "language Chinese".
            if lowered.range(
                of: #"^language(\s+\S+)?$"#,
                options: .regularExpression
            ) != nil {
                return true
            }
            return false
        }
    }
}

enum MacQwen3LanguageHint {
    /// Map persisted BCP-47 locale ids to Qwen3 prompt language names.
    /// Returns `nil` for auto-detect.
    static func from(locale: Locale) -> String? {
        let raw = locale.identifier.lowercased()
        if raw.isEmpty || raw == "auto" { return nil }
        if raw.hasPrefix("zh") { return "Chinese" }
        if raw.hasPrefix("en") { return "English" }
        if raw.hasPrefix("ja") { return "Japanese" }
        if raw.hasPrefix("ko") { return "Korean" }
        if raw.hasPrefix("fr") { return "French" }
        if raw.hasPrefix("de") { return "German" }
        if raw.hasPrefix("es") { return "Spanish" }
        if raw.hasPrefix("pt") { return "Portuguese" }
        if raw.hasPrefix("ru") { return "Russian" }
        if raw.hasPrefix("ar") { return "Arabic" }
        return nil
    }
}
