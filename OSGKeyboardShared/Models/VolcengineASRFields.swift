// VolcengineASRFields.swift
// OSGKeyboard · Shared
//
// Parse / encode Volcengine SAUC credentials stored in the ASR API key field.
// Supports legacy AppID+AccessToken (old console) and single API Key (new console).

import Foundation

/// Volcengine speech console auth style for SAUC streaming ASR.
public enum VolcengineASRAuthMode: String, Sendable, Equatable {
    /// Old console: `X-Api-App-Key` + `X-Api-Access-Key`.
    case appToken = "app_token"
    /// New console: single `X-Api-Key`.
    case apiKey = "api_key"
}

public struct VolcengineASRFields: Sendable, Equatable {
    public var authMode: VolcengineASRAuthMode
    public var appID: String
    public var accessToken: String
    /// New-console API Key (`X-Api-Key`). Kept alongside app-token fields so the
    /// settings toggle can switch modes without wiping the other credential set.
    public var apiKeyCredential: String

    /// Locked product: Doubao streaming ASR 2.0 · duration billing.
    public static let fixedResourceID = CloudASRModelCatalog.volcengineDefaultResourceID

    public init(
        authMode: VolcengineASRAuthMode = .apiKey,
        appID: String = "",
        accessToken: String = "",
        apiKeyCredential: String = ""
    ) {
        self.authMode = authMode
        self.appID = appID
        self.accessToken = accessToken
        self.apiKeyCredential = apiKeyCredential
    }

    /// Always `volc.seedasr.sauc.duration` — not user-editable.
    public var resourceID: String { Self.fixedResourceID }

    public var usesAPIKeyAuth: Bool { authMode == .apiKey }

    public var hasUsableCredentials: Bool {
        switch authMode {
        case .appToken:
            return !appID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .apiKey:
            return !apiKeyCredential.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    public var encodedAPIKey: String {
        var object: [String: String] = [
            "auth_mode": authMode.rawValue,
            "resource_id": Self.fixedResourceID,
        ]
        // Persist both credential sets so toggling auth mode is non-destructive.
        if !appID.isEmpty { object["app_id"] = appID }
        if !accessToken.isEmpty { object["access_token"] = accessToken }
        if !apiKeyCredential.isEmpty { object["api_key"] = apiKeyCredential }

        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let string = String(data: data, encoding: .utf8) else {
            switch authMode {
            case .appToken:
                return [appID, accessToken, Self.fixedResourceID].joined(separator: ":")
            case .apiKey:
                return apiKeyCredential
            }
        }
        return string
    }

    /// Apply SAUC WebSocket handshake headers for the active auth mode.
    public func applyWebSocketAuthHeaders(to request: inout URLRequest, connectID: String) {
        request.setValue(Self.fixedResourceID, forHTTPHeaderField: "X-Api-Resource-Id")
        request.setValue(connectID, forHTTPHeaderField: "X-Api-Connect-Id")
        switch authMode {
        case .apiKey:
            request.setValue(
                apiKeyCredential.trimmingCharacters(in: .whitespacesAndNewlines),
                forHTTPHeaderField: "X-Api-Key"
            )
        case .appToken:
            request.setValue(
                appID.trimmingCharacters(in: .whitespacesAndNewlines),
                forHTTPHeaderField: "X-Api-App-Key"
            )
            request.setValue(
                accessToken.trimmingCharacters(in: .whitespacesAndNewlines),
                forHTTPHeaderField: "X-Api-Access-Key"
            )
        }
    }

    /// - Parameter resourceFallback: Ignored; resource is always `fixedResourceID`.
    ///   Kept so call sites stay source-compatible.
    public static func parse(apiKey: String, resourceFallback: String = "") -> VolcengineASRFields {
        _ = resourceFallback
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        var fields = VolcengineASRFields()

        guard !trimmed.isEmpty else { return fields }

        if let data = trimmed.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            fields.appID = string(json, keys: ["app_id", "appId", "appid"]) ?? ""
            fields.accessToken = string(json, keys: ["access_token", "accessToken", "token"]) ?? ""
            fields.apiKeyCredential = string(json, keys: ["api_key", "apiKey"]) ?? ""
            fields.authMode = resolveAuthMode(
                raw: string(json, keys: ["auth_mode", "authMode"]),
                hasAPIKey: !fields.apiKeyCredential.isEmpty,
                hasAppToken: !fields.appID.isEmpty && !fields.accessToken.isEmpty
            )
            return fields
        }

        // Legacy colon form is always old-console app-token auth.
        let parts = trimmed
            .components(separatedBy: CharacterSet(charactersIn: ":\n,"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if parts.indices.contains(0) { fields.appID = parts[0] }
        if parts.indices.contains(1) { fields.accessToken = parts[1] }
        fields.authMode = .appToken
        return fields
    }

    private static func resolveAuthMode(
        raw: String?,
        hasAPIKey: Bool,
        hasAppToken: Bool
    ) -> VolcengineASRAuthMode {
        if let raw {
            let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if normalized == VolcengineASRAuthMode.apiKey.rawValue || normalized == "apikey" {
                return .apiKey
            }
            if normalized == VolcengineASRAuthMode.appToken.rawValue
                || normalized == "apptoken"
                || normalized == "app_id_token" {
                return .appToken
            }
        }
        // Legacy JSON without auth_mode: prefer app-token when present.
        if hasAppToken { return .appToken }
        if hasAPIKey { return .apiKey }
        return .apiKey
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
