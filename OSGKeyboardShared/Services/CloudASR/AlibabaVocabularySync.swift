// AlibabaVocabularySync.swift
// OSGKeyboard · Shared
//
// Syncs PersonalDictionary → DashScope custom vocabulary (Fun-ASR Flash).

import Foundation

public enum AlibabaVocabularySync {
    public enum Keys {
        public static let vocabularyId = "config.alibabaASRVocabularyId"
        public static let fingerprint = "config.alibabaASRVocabularyFingerprint"
    }

    private static let vocabularyPrefix = "osgkb"

    /// Returns a ready `vocabulary_id`, creating or updating the remote list as needed.
    public static func ensureVocabularyID(
        dictionary: PersonalDictionary,
        apiKey: String,
        targetModel: String = CloudASRModelCatalog.alibabaVocabularyTargetModel,
        defaults: UserDefaults,
        session: URLSession = .shared
    ) async throws -> String? {
        let entries = dictionary.alibabaHotwordEntries()
        guard !entries.isEmpty else {
            clearCache(defaults: defaults)
            return nil
        }

        let fingerprint = dictionary.vocabularySyncFingerprint()
        if let cachedID = defaults.string(forKey: Keys.vocabularyId),
           defaults.string(forKey: Keys.fingerprint) == fingerprint,
           !cachedID.isEmpty {
            return cachedID
        }

        let url = try customizationURL()
        if let existingID = defaults.string(forKey: Keys.vocabularyId), !existingID.isEmpty {
            try await updateVocabulary(
                id: existingID,
                entries: entries,
                apiKey: apiKey,
                url: url,
                session: session
            )
            cache(id: existingID, fingerprint: fingerprint, defaults: defaults)
            return existingID
        }

        let createdID = try await createVocabulary(
            entries: entries,
            targetModel: targetModel,
            apiKey: apiKey,
            url: url,
            session: session
        )
        cache(id: createdID, fingerprint: fingerprint, defaults: defaults)
        return createdID
    }

    public static func clearCache(defaults: UserDefaults) {
        defaults.removeObject(forKey: Keys.vocabularyId)
        defaults.removeObject(forKey: Keys.fingerprint)
    }

    private static func cache(id: String, fingerprint: String, defaults: UserDefaults) {
        defaults.set(id, forKey: Keys.vocabularyId)
        defaults.set(fingerprint, forKey: Keys.fingerprint)
    }

    private static func customizationURL() throws -> URL {
        let raw = CloudASRModelCatalog.alibabaAPIBase + CloudASRModelCatalog.alibabaCustomizationPath
        guard let url = URL(string: raw) else { throw CloudASRError.invalidURL }
        return url
    }

    private static func createVocabulary(
        entries: [AlibabaHotwordEntry],
        targetModel: String,
        apiKey: String,
        url: URL,
        session: URLSession
    ) async throws -> String {
        let vocabulary = entries.map { entry -> [String: Any] in
            var item: [String: Any] = ["text": entry.text, "weight": entry.weight]
            if let lang = entry.lang { item["lang"] = lang }
            return item
        }
        let body: [String: Any] = [
            "model": "speech-biasing",
            "input": [
                "action": "create_vocabulary",
                "target_model": targetModel,
                "prefix": vocabularyPrefix,
                "vocabulary": vocabulary,
            ] as [String: Any],
        ]
        let data = try await postJSON(body, to: url, apiKey: apiKey, session: session)
        guard let id = parseVocabularyID(from: data) else {
            throw CloudASRError.decoding("missing vocabulary_id")
        }
        return id
    }

    private static func updateVocabulary(
        id: String,
        entries: [AlibabaHotwordEntry],
        apiKey: String,
        url: URL,
        session: URLSession
    ) async throws {
        let vocabulary = entries.map { entry -> [String: Any] in
            var item: [String: Any] = ["text": entry.text, "weight": entry.weight]
            if let lang = entry.lang { item["lang"] = lang }
            return item
        }
        let body: [String: Any] = [
            "model": "speech-biasing",
            "input": [
                "action": "update_vocabulary",
                "vocabulary_id": id,
                "vocabulary": vocabulary,
            ] as [String: Any],
        ]
        _ = try await postJSON(body, to: url, apiKey: apiKey, session: session)
    }

    private static func postJSON(
        _ body: [String: Any],
        to url: URL,
        apiKey: String,
        session: URLSession
    ) async throws -> [String: Any] {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CloudASRError.transport("non-HTTP response")
        }
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard (200..<300).contains(http.statusCode) else {
            let message = parseAPIErrorMessage(from: json)
            throw CloudASRError.http(status: http.statusCode, message: message)
        }
        return json ?? [:]
    }

    private static func parseVocabularyID(from json: [String: Any]) -> String? {
        if let output = json["output"] as? [String: Any],
           let id = output["vocabulary_id"] as? String {
            return id
        }
        return nil
    }

    private static func parseAPIErrorMessage(from json: [String: Any]?) -> String? {
        guard let json else { return nil }
        if let message = json["message"] as? String { return message }
        if let error = json["error"] as? [String: Any],
           let message = error["message"] as? String {
            return message
        }
        return nil
    }
}
