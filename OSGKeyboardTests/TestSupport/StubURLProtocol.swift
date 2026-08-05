// StubURLProtocol.swift
// OSGKeyboardTests · TestSupport
//
// Shared URLProtocol stub for hermetic HTTP client tests (LLM + Cloud ASR).

import Foundation

/// Per-test stub config holder. Tests set these via `StubURLProtocolStorage.config =`
/// before invoking the code under test, then reset to nil in cleanup.
enum StubURLProtocolStorage {
    nonisolated(unsafe) static var config: (statusCode: Int, body: Data)?
    nonisolated(unsafe) static var delaySeconds: Double = 0
    nonisolated(unsafe) static var lastRequest: URLRequest?
}

final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let cfg = StubURLProtocolStorage.config ?? (statusCode: 200, body: Data())
        let delay = StubURLProtocolStorage.delaySeconds
        // Materialize body here (once). Doing it in `canonicalRequest` consumes
        // the stream before `startLoading` can capture it for assertions.
        StubURLProtocolStorage.lastRequest = Self.materializingBody(of: request)

        // Simulate a slow transport. We honour URLProtocol.stopLoading() so
        // cancellation doesn't leave the test hanging, and we yield to the
        // run loop so `URLSession.data(for:)` actually observes the delay
        // (a busy-wait would never let the cooperative scheduler time out).
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            guard self.client != nil else { return }
            let response = HTTPURLResponse(
                url: self.request.url!,
                statusCode: cfg.statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            self.client?.urlProtocol(self, didLoad: cfg.body)
            self.client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}

    private static func materializingBody(of request: URLRequest) -> URLRequest {
        var req = request
        if req.httpBody == nil, let stream = req.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var data = Data()
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 4_096)
            defer { buffer.deallocate() }
            while stream.hasBytesAvailable {
                let read = stream.read(buffer, maxLength: 4_096)
                if read <= 0 { break }
                data.append(buffer, count: read)
            }
            if !data.isEmpty {
                req.httpBody = data
            }
        }
        return req
    }
}

extension StubURLProtocol {
    static func makeEphemeralSession() -> URLSession {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: cfg)
    }

    static func reset() {
        StubURLProtocolStorage.config = nil
        StubURLProtocolStorage.delaySeconds = 0
        StubURLProtocolStorage.lastRequest = nil
    }
}
