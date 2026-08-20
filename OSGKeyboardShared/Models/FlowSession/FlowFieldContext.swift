// FlowFieldContext.swift
// OSGKeyboard · Shared

import Foundation

public struct FlowFieldContext: Codable, Equatable, Sendable {
    public let precedingText: String?
    public let followingText: String?
    public let keyboardType: String?
    public let returnKeyType: String?
    public let isSecureEntry: Bool
    /// Distinguishes a known-empty field from unavailable document context.
    public let isEmptyField: Bool
    public let isContextAvailable: Bool

    public init(
        precedingText: String? = nil,
        followingText: String? = nil,
        keyboardType: String? = nil,
        returnKeyType: String? = nil,
        isSecureEntry: Bool = false,
        isEmptyField: Bool = false,
        isContextAvailable: Bool = false
    ) {
        self.precedingText = isSecureEntry ? nil : precedingText
        self.followingText = isSecureEntry ? nil : followingText
        self.keyboardType = keyboardType
        self.returnKeyType = returnKeyType
        self.isSecureEntry = isSecureEntry
        self.isEmptyField = isSecureEntry ? false : isEmptyField
        self.isContextAvailable = isSecureEntry ? false : isContextAvailable
    }

    public var deliveryFingerprint: String? {
        guard !isSecureEntry else { return nil }
        return [
            keyboardType ?? "",
            returnKeyType ?? "",
            precedingText.map { String($0.suffix(80)) } ?? "",
            followingText.map { String($0.prefix(40)) } ?? ""
        ].joined(separator: "|")
    }
}
