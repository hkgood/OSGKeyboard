// AIShortcutShareLink.swift
// OSGKeyboard · Shared
//
// Validates iCloud Shortcut share URLs and reads the published name from
// Apple's undocumented records endpoint. Running a Shortcut still requires
// that name (`shortcuts://run-shortcut?name=`); the share link is install-only.

import Foundation

public enum AIShortcutShareLink {
    /// `https://www.icloud.com/shortcuts/{token}` or `https://icloud.com/shortcuts/{token}`.
    public static func isValid(_ url: URL) -> Bool {
        guard let token = AIAgentShortcutRun.iCloudShareToken(from: url) else { return false }
        let allowed = CharacterSet.alphanumerics
        return (16...64).contains(token.count)
            && token.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    public static func parse(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let withScheme: String
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            withScheme = trimmed
        } else {
            withScheme = "https://\(trimmed)"
        }
        guard let url = URL(string: withScheme), isValid(url) else { return nil }
        return url
    }
}

public enum AIShortcutShareMetadataError: Error, Equatable, Sendable {
    case invalidLink
    case network
    case missingName
}

public enum AIShortcutShareMetadata {
    public static func recordsURL(for shareURL: URL) -> URL? {
        guard let token = AIAgentShortcutRun.iCloudShareToken(from: shareURL) else { return nil }
        return URL(string: "https://www.icloud.com/shortcuts/api/records/\(token)")
    }

    /// Parses `fields.name.value`, or the older `records[0].fields.name.value`.
    public static func name(fromRecordsJSON data: Data) throws -> String {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let root = object as? [String: Any] else {
            throw AIShortcutShareMetadataError.missingName
        }
        if let name = stringName(in: root) {
            return name
        }
        if let records = root["records"] as? [[String: Any]],
           let first = records.first,
           let name = stringName(in: first) {
            return name
        }
        throw AIShortcutShareMetadataError.missingName
    }

    public static func fetchName(
        from shareURL: URL,
        session: URLSession = .shared
    ) async throws -> String {
        guard let url = recordsURL(for: shareURL) else {
            throw AIShortcutShareMetadataError.invalidLink
        }
        let data: Data
        do {
            let (bytes, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else {
                throw AIShortcutShareMetadataError.network
            }
            data = bytes
        } catch let error as AIShortcutShareMetadataError {
            throw error
        } catch {
            throw AIShortcutShareMetadataError.network
        }
        return try name(fromRecordsJSON: data)
    }

    private static func stringName(in record: [String: Any]) -> String? {
        guard let fields = record["fields"] as? [String: Any],
              let nameField = fields["name"] as? [String: Any],
              let value = nameField["value"] as? String else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
