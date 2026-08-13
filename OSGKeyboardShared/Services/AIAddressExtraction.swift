// AIAddressExtraction.swift
// OSGKeyboard · Shared
//
// Parses the LLM's navigate-skill reply into one origin|destination line.
// Fail closed: empty / NONE / no destination never become a run. Only the
// first valid line is kept — opening several map apps is not useful.

import Foundation

public struct AIMapRoute: Equatable, Sendable {
    /// Nil means "current location" in the map app.
    public let origin: String?
    public let destination: String

    public init(origin: String?, destination: String) {
        self.origin = origin
        self.destination = destination
    }
}

public enum AIAddressExtraction: Sendable {
    /// Canonical line: origin|destination. Empty origin keeps the pipe.
    public static let fieldSeparator: Character = "|"

    private static let emptyTokens: Set<String> = [
        "none", "no", "n/a", "na", "nil", "null",
        "无", "没有", "没有地址", "没有地点", "无地址", "无地点",
        "没有可导航的地点", "没有可导航的地址",
        "no address", "no addresses", "no location", "no locations",
        "no place", "no places", "no destination",
    ]

    /// Lines to send to the host. Empty → do not run the companion Shortcut.
    public static func lines(
        from raw: String,
        sourceClipboard: String? = nil
    ) -> [String] {
        guard let route = route(from: raw, sourceClipboard: sourceClipboard) else {
            return []
        }
        return [encode(route)]
    }

    public static func route(
        from raw: String,
        sourceClipboard: String? = nil
    ) -> AIMapRoute? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if isEmptyToken(trimmed) { return nil }

        for line in trimmed.components(separatedBy: .newlines) {
            guard let route = parseLine(line) else { continue }
            if isWholeClipboardEcho(route, source: sourceClipboard) {
                return nil
            }
            return route
        }
        return nil
    }

    public static func encode(_ route: AIMapRoute) -> String {
        "\(route.origin ?? "")|\(route.destination)"
    }

    // MARK: - Line

    private static func parseLine(_ line: String) -> AIMapRoute? {
        let stripped = stripBullet(line)
        guard !stripped.isEmpty, !isEmptyToken(stripped) else { return nil }

        let parts = stripped
            .split(separator: fieldSeparator, omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        let originRaw: String
        let destinationRaw: String
        if parts.count == 1 {
            originRaw = ""
            destinationRaw = parts[0]
        } else {
            originRaw = parts[0]
            var destParts = Array(parts[1...])
            while destParts.last?.isEmpty == true {
                destParts.removeLast()
            }
            destinationRaw = destParts
                .joined(separator: String(fieldSeparator))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard let destination = sanitizedPlace(destinationRaw) else { return nil }
        let origin = sanitizedPlace(originRaw)
        if let origin, origin.caseInsensitiveCompare(destination) == .orderedSame {
            return AIMapRoute(origin: nil, destination: destination)
        }
        return AIMapRoute(origin: origin, destination: destination)
    }

    /// Drop URLs and empty / NONE tokens. Place names stay as-is.
    private static func sanitizedPlace(_ raw: String) -> String? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isEmptyToken(text) else { return nil }
        if text.contains("://") { return nil }
        return text
    }

    private static func isEmptyToken(_ text: String) -> Bool {
        let folded = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "。.!！"))
            .lowercased()
        return emptyTokens.contains(folded)
    }

    private static func stripBullet(_ line: String) -> String {
        var text = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefixes = ["- ", "* ", "• ", "、"]
        for prefix in prefixes where text.hasPrefix(prefix) {
            text = String(text.dropFirst(prefix.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let dotted = text.range(of: #"^\d+[\.\)、]\s*"#, options: .regularExpression) {
            text = String(text[dotted.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text
    }

    /// One long destination that is essentially the clipboard body is not a place.
    private static func isWholeClipboardEcho(_ route: AIMapRoute, source: String?) -> Bool {
        guard let source, source.count > 80, route.destination.count > 80 else {
            return false
        }
        let a = collapse(route.destination)
        let b = collapse(source)
        guard !a.isEmpty, !b.isEmpty else { return false }
        if a == b { return true }
        return a.contains(b) || b.contains(a)
    }

    private static func collapse(_ text: String) -> String {
        text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .lowercased()
    }
}
