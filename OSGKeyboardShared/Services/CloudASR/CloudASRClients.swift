// CloudASRClients.swift
// OSGKeyboard · Shared
//
// Provider-specific cloud ASR backends with personal-dictionary bias.

import Foundation

public protocol CloudASRTranscribing: Sendable {
    func prepare(dictionary: PersonalDictionary) async throws
    func transcribe(
        samples: [Float],
        sampleRate: Int,
        locale: Locale,
        dictionary: PersonalDictionary
    ) async throws -> String
}

public enum CloudASRClientFactory {
    public static func make(store: any ConfigurationStore, session: URLSession = .shared) -> CloudASRTranscribing {
        let strategy = CloudASRModelCatalog.strategy(for: store.providerId)
        switch strategy {
        case .zhipuHotwords:
            return ZhipuCloudASRClient(
                apiKey: store.apiKey,
                model: CloudASRModelCatalog.defaultModel(for: store.providerId),
                session: session
            )
        case .alibabaVocabulary:
            return AlibabaFunASRClient(
                apiKey: store.apiKey,
                model: CloudASRModelCatalog.defaultModel(for: store.providerId),
                persistence: store.cloudASRPersistence,
                session: session
            )
        case .prompt:
            return PromptCloudASRClient(
                providerId: store.providerId,
                baseURL: store.baseURL,
                apiKey: store.apiKey,
                model: CloudASRModelCatalog.defaultModel(for: store.providerId),
                session: session
            )
        case .localFallback:
            return UnsupportedCloudASRClient(providerId: store.providerId)
        }
    }
}

// MARK: - Zhipu (hotwords + prompt)

struct ZhipuCloudASRClient: CloudASRTranscribing {
    let apiKey: String
    let model: String
    let session: URLSession

    private static let maxDurationSeconds: TimeInterval = 30

    func prepare(dictionary: PersonalDictionary) async throws {}

    func transcribe(
        samples: [Float],
        sampleRate: Int,
        locale: Locale,
        dictionary: PersonalDictionary
    ) async throws -> String {
        guard !apiKey.isEmpty else { throw CloudASRError.noAPIKey }
        let duration = Double(samples.count) / Double(sampleRate)
        guard duration <= Self.maxDurationSeconds else { throw CloudASRError.audioTooLong }

        let wav = PCMSampleWavEncoder.encode(samples: samples, sampleRate: sampleRate)
        let urlString = "https://open.bigmodel.cn/api/paas/v4\(CloudASRModelCatalog.zhipuTranscriptionPath)"
        guard let url = URL(string: urlString) else { throw CloudASRError.invalidURL }

        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()
        func appendField(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }

        appendField("model", model)
        appendField("stream", "false")

        let hotwords = dictionary.asrHotwords()
        if !hotwords.isEmpty,
           let hotwordsJSON = try? JSONSerialization.data(withJSONObject: hotwords),
           let hotwordsString = String(data: hotwordsJSON, encoding: .utf8) {
            appendField("hotwords", hotwordsString)
        }

        let prompt = dictionary.asrPromptBias()
        if !prompt.isEmpty {
            appendField("prompt", prompt)
        }

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"chunk.wav\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(wav)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        request.timeoutInterval = 60

        let (data, response) = try await session.data(for: request)
        try Self.validateHTTP(response: response, data: data)
        guard let text = Self.parseZhipuText(from: data)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            throw CloudASRError.emptyTranscript
        }
        return text
    }

    private static func parseZhipuText(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json["text"] as? String
    }

    fileprivate static func validateHTTP(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw CloudASRError.transport("non-HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = parseErrorMessage(from: data)
            throw CloudASRError.http(status: http.statusCode, message: message)
        }
    }

    fileprivate static func parseErrorMessage(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let message = json["message"] as? String { return message }
        if let error = json["error"] as? [String: Any],
           let message = error["message"] as? String {
            return message
        }
        return nil
    }
}

// MARK: - Alibaba Fun-ASR Flash (vocabulary_id + context)

/// `UserDefaults` is not `Sendable`; we only touch `persistence` on the
/// actor-isolated cloud ASR path, same as the previous `AppGroupStore` holder.
struct AlibabaFunASRClient: CloudASRTranscribing, @unchecked Sendable {
    let apiKey: String
    let model: String
    let persistence: UserDefaults
    let session: URLSession

    func prepare(dictionary: PersonalDictionary) async throws {
        _ = try await AlibabaVocabularySync.ensureVocabularyID(
            dictionary: dictionary,
            apiKey: apiKey,
            targetModel: CloudASRModelCatalog.alibabaVocabularyTargetModel,
            defaults: persistence,
            session: session
        )
    }

    func transcribe(
        samples: [Float],
        sampleRate: Int,
        locale: Locale,
        dictionary: PersonalDictionary
    ) async throws -> String {
        guard !apiKey.isEmpty else { throw CloudASRError.noAPIKey }

        let vocabularyID = try await AlibabaVocabularySync.ensureVocabularyID(
            dictionary: dictionary,
            apiKey: apiKey,
            targetModel: CloudASRModelCatalog.alibabaVocabularyTargetModel,
            defaults: persistence,
            session: session
        )

        let dataURI = PCMSampleWavEncoder.dataURI(samples: samples, sampleRate: sampleRate)
        let urlString = CloudASRModelCatalog.alibabaAPIBase + CloudASRModelCatalog.alibabaMultimodalPath
        guard let url = URL(string: urlString) else { throw CloudASRError.invalidURL }

        var messages: [[String: Any]] = []
        let context = dictionary.alibabaContextText()
        if !context.isEmpty {
            messages.append([
                "role": "user",
                "content": [
                    ["type": "input_text", "text": context],
                ],
            ])
        }
        messages.append([
            "role": "user",
            "content": [
                [
                    "type": "input_audio",
                    "input_audio": ["data": dataURI],
                ],
            ],
        ])

        var parameters: [String: Any] = [
            "format": "wav",
            "sample_rate": "\(sampleRate)",
        ]
        if let vocabularyID, !vocabularyID.isEmpty {
            parameters["vocabulary_id"] = vocabularyID
        }

        let body: [String: Any] = [
            "model": model,
            "input": ["messages": messages],
            "parameters": parameters,
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("disable", forHTTPHeaderField: "X-DashScope-SSE")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 90

        let (data, response) = try await session.data(for: request)
        try ZhipuCloudASRClient.validateHTTP(response: response, data: data)
        guard let text = Self.parseText(from: data)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            throw CloudASRError.emptyTranscript
        }
        return text
    }

    private static func parseText(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let output = json["output"] as? [String: Any] else {
            return nil
        }
        if let text = output["text"] as? String { return text }
        if let sentence = output["sentence"] as? [String: Any],
           let text = sentence["text"] as? String {
            return text
        }
        return nil
    }
}

// MARK: - Prompt-biased transcription (OpenAI / MiMo / custom)

struct PromptCloudASRClient: CloudASRTranscribing {
    let providerId: String
    let baseURL: String
    let apiKey: String
    let model: String
    let session: URLSession

    func prepare(dictionary: PersonalDictionary) async throws {}

    func transcribe(
        samples: [Float],
        sampleRate: Int,
        locale: Locale,
        dictionary: PersonalDictionary
    ) async throws -> String {
        guard !apiKey.isEmpty else { throw CloudASRError.noAPIKey }
        if providerId == "mimo" {
            return try await transcribeMiMo(
                samples: samples,
                sampleRate: sampleRate,
                dictionary: dictionary
            )
        }
        return try await transcribeOpenAIStyle(
            samples: samples,
            sampleRate: sampleRate,
            dictionary: dictionary
        )
    }

    private func transcribeOpenAIStyle(
        samples: [Float],
        sampleRate: Int,
        dictionary: PersonalDictionary
    ) async throws -> String {
        let wav = PCMSampleWavEncoder.encode(samples: samples, sampleRate: sampleRate)
        let trimmedBase = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        let urlString = "\(trimmedBase)/audio/transcriptions"
        guard let url = URL(string: urlString) else { throw CloudASRError.invalidURL }

        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()
        func appendField(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }

        appendField("model", model)
        let prompt = dictionary.asrPromptBias(maxCharacters: 600)
        if !prompt.isEmpty {
            appendField("prompt", prompt)
        }

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"chunk.wav\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(wav)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        request.timeoutInterval = 90

        let (data, response) = try await session.data(for: request)
        try ZhipuCloudASRClient.validateHTTP(response: response, data: data)
        guard let text = Self.parseOpenAIText(from: data)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            throw CloudASRError.emptyTranscript
        }
        return text
    }

    private func transcribeMiMo(
        samples: [Float],
        sampleRate: Int,
        dictionary: PersonalDictionary
    ) async throws -> String {
        let dataURI = PCMSampleWavEncoder.dataURI(samples: samples, sampleRate: sampleRate)
        let trimmedBase = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        let urlString = "\(trimmedBase)/chat/completions"
        guard let url = URL(string: urlString) else { throw CloudASRError.invalidURL }

        var userContent: [[String: Any]] = []
        let prompt = dictionary.asrPromptBias()
        if !prompt.isEmpty {
            userContent.append(["type": "text", "text": prompt])
        }
        userContent.append([
            "type": "input_audio",
            "input_audio": ["data": dataURI],
        ])

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "user", "content": userContent],
            ],
            "asr_options": ["language": "auto"],
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "api-key")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 90

        let (data, response) = try await session.data(for: request)
        try ZhipuCloudASRClient.validateHTTP(response: response, data: data)
        guard let text = Self.parseChatCompletionText(from: data)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            throw CloudASRError.emptyTranscript
        }
        return text
    }

    private static func parseOpenAIText(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json["text"] as? String
    }

    private static func parseChatCompletionText(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any] else {
            return nil
        }
        return message["content"] as? String
    }
}

// MARK: - Unsupported hosted ASR (Moonshot)

struct UnsupportedCloudASRClient: CloudASRTranscribing {
    let providerId: String

    func prepare(dictionary: PersonalDictionary) async throws {}

    func transcribe(
        samples: [Float],
        sampleRate: Int,
        locale: Locale,
        dictionary: PersonalDictionary
    ) async throws -> String {
        throw CloudASRError.providerUnsupported
    }
}
