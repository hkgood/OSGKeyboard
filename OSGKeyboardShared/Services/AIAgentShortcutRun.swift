// AIAgentShortcutRun.swift
// OSGKeyboard · Shared
//
// Ephemeral App Group payload for one keyboard → host → Shortcuts hop.
// The keyboard writes titles here, then opens `osgkeyboard://skill/run`.
// The host consumes the payload (once) and opens the Shortcuts URL.

import Foundation

public struct AIAgentShortcutRunPayload: Codable, Equatable, Sendable {
    public let skillID: String
    public let titles: [String]
    public let createdAt: Date

    public init(skillID: String, titles: [String], createdAt: Date = Date()) {
        self.skillID = skillID
        self.titles = titles
        self.createdAt = createdAt
    }

    public var joinedTitles: String {
        titles.joined(separator: "\n")
    }
}

public enum AIAgentShortcutRun {
    public static let pendingKey = "config.aiAgentSkills.pendingRun.v1"
    /// Drop payloads older than this; a leftover write must not fire later.
    public static let payloadTTL: TimeInterval = 60

    public static func shortcutsRunURL(
        name: String,
        text: String,
        xSuccess: String? = nil,
        xError: String? = nil,
        xCancel: String? = nil
    ) -> URL? {
        var components = URLComponents()
        components.scheme = "shortcuts"
        let usesCallback = xSuccess != nil || xError != nil || xCancel != nil
        if usesCallback {
            components.host = "x-callback-url"
            components.path = "/run-shortcut"
        } else {
            components.host = "run-shortcut"
        }
        var items = [
            URLQueryItem(name: "name", value: name),
            URLQueryItem(name: "input", value: "text"),
            URLQueryItem(name: "text", value: text),
        ]
        if let xSuccess {
            items.append(URLQueryItem(name: "x-success", value: xSuccess))
        }
        if let xError {
            items.append(URLQueryItem(name: "x-error", value: xError))
        }
        if let xCancel {
            items.append(URLQueryItem(name: "x-cancel", value: xCancel))
        }
        components.queryItems = items
        return components.url
    }

    /// Xcode / Console search: `OSGDiag/skills`. DEBUG builds include bodies.
    public static func trace(_ message: String) {
        OSGDiag.log(message, category: "skills")
    }

    /// Single-line preview so Console keeps the format (`\\n` for newlines).
    public static func preview(_ text: String, limit: Int = 1200) -> String {
        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\r\n", with: "\\n")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\n")
            .replacingOccurrences(of: "\t", with: "\\t")
        if escaped.count <= limit { return escaped }
        return String(escaped.prefix(limit)) + "…(chars=\(text.count))"
    }

    public static func traceBody(_ label: String, _ text: String) {
        #if DEBUG
        trace("\(label) chars=\(text.count) body=\(preview(text))")
        #else
        trace("\(label) chars=\(text.count)")
        #endif
    }

    /// Opens the Shortcuts Add sheet for an iCloud share token.
    /// Do not `open` the HTTPS share page from the app — Universal Links
    /// often land on Gallery and drop the token.
    public static func shortcutsInstallURL(from shareURL: URL) -> URL? {
        guard let token = iCloudShareToken(from: shareURL) else { return nil }
        return URL(string: "shortcuts://shortcuts/\(token)")
    }

    public static func iCloudShareToken(from shareURL: URL) -> String? {
        guard let host = shareURL.host, host.contains("icloud.com") else { return nil }
        let parts = shareURL.path.split(separator: "/").map(String.init)
        guard let index = parts.firstIndex(of: "shortcuts"),
              parts.count > index + 1 else { return nil }
        let token = parts[index + 1]
        guard token != "api", !token.isEmpty else { return nil }
        return token
    }

    public static func openShortcutURL(name: String) -> URL? {
        var components = URLComponents()
        components.scheme = "shortcuts"
        components.host = "open-shortcut"
        components.queryItems = [URLQueryItem(name: "name", value: name)]
        return components.url
    }

    public static func encode(_ payload: AIAgentShortcutRunPayload) -> Data? {
        try? JSONEncoder().encode(payload)
    }

    public static func decode(_ data: Data, now: Date = Date()) -> AIAgentShortcutRunPayload? {
        guard let payload = try? JSONDecoder().decode(AIAgentShortcutRunPayload.self, from: data) else {
            return nil
        }
        guard now.timeIntervalSince(payload.createdAt) <= payloadTTL else { return nil }
        guard !payload.titles.isEmpty else { return nil }
        return payload
    }
}
