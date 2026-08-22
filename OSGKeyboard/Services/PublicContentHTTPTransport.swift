// PublicContentHTTPTransport.swift
// OSGKeyboard · Main App
//
// Anonymous public-content transport. It is intentionally independent from
// account/auth clients and is never linked into keyboard-extension behavior.

import Foundation

protocol PublicContentHTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

final class URLSessionPublicContentHTTPTransport:
    PublicContentHTTPTransport,
    @unchecked Sendable {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw PublicContentHTTPError.invalidResponse
        }
        return (data, response)
    }
}

enum PublicContentHTTPError: Error, Equatable {
    case invalidResponse
    case unexpectedStatus(Int)
    case notModifiedWithoutCache
    case staleRevision(current: Int64, received: Int64)
}
