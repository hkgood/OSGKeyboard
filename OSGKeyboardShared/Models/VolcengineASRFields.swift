// VolcengineASRFields.swift
// OSGKeyboard · Shared
//
// Parse / encode Volcengine SAUC credentials stored in the ASR API key field.

import Foundation

public struct VolcengineASRFields: Sendable, Equatable {
    public var appID: String
    public var accessToken: String
    public var resourceID: String

    public init(
        appID: String = "",
        accessToken: String = "",
        resourceID: String = CloudASRModelCatalog.defaultModel(for: "volcengine")
    ) {
        self.appID = appID
        self.accessToken = accessToken
        self.resourceID = resourceID
    }

    public var encodedAPIKey: String {
        let object = [
            "app_id": appID,
            "access_token": accessToken,
            "resource_id": resourceID,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let string = String(data: data, encoding: .utf8) else {
            return [appID, accessToken, resourceID].joined(separator: ":")
        }
        return string
    }

    public static func parse(apiKey: String, resourceFallback: String) -> VolcengineASRFields {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        var fields = VolcengineASRFields(
            appID: "",
            accessToken: "",
            resourceID: resourceFallback.isEmpty
                ? CloudASRModelCatalog.defaultModel(for: "volcengine")
                : resourceFallback
        )

        if let data = trimmed.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            fields.appID = string(json, keys: ["app_id", "appId", "appid"]) ?? ""
            fields.accessToken = string(json, keys: ["access_token", "accessToken", "token"]) ?? ""
            fields.resourceID = string(json, keys: ["resource_id", "resourceId", "resource"]) ?? fields.resourceID
            return fields
        }

        let parts = trimmed
            .components(separatedBy: CharacterSet(charactersIn: ":\n,"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if parts.indices.contains(0) { fields.appID = parts[0] }
        if parts.indices.contains(1) { fields.accessToken = parts[1] }
        if parts.indices.contains(2) { fields.resourceID = parts[2] }
        return fields
    }

    private static func string(_ json: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = json[key] as? String {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        return nil
    }
}
