// CredentialSource.swift
// OSGKeyboard · Shared
//
// Credential ownership is independent from the ASR engine. This keeps local
// ASR + managed polish, direct BYOK cloud, and fully managed flows composable.

import Foundation

public enum CredentialSource: String, CaseIterable, Codable, Sendable {
    case byok
    case managed

    public static func fromStored(_ value: String?) -> CredentialSource {
        CredentialSource(rawValue: value ?? "") ?? .byok
    }
}
