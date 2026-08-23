// WebPageContentService.swift
// OSGKeyboard · Main App
//
// Fetches a bounded public HTTPS page in the host process, then turns static
// HTML into untrusted source text for the existing clipboard AI pipeline.

import Foundation

struct WebPageContent: Equatable, Sendable {
    let finalURL: URL
    let title: String?
    let body: String

    var summaryMaterial: String {
        var sections = ["Source URL: \(finalURL.absoluteString)"]
        if let title, !title.isEmpty {
            sections.append("Title: \(title)")
        }
        sections.append("Webpage body:\n\(body)")
        return sections.joined(separator: "\n")
    }
}

enum WebPageContentError: Error, Equatable, Sendable {
    case invalidURL
    case tooManyRedirects
    case invalidResponse
    case httpStatus(Int)
    case responseTooLarge
    case unsupportedContentType
    case undecodableText
    case emptyContent
    case transport
}

enum WebPageURLPolicy {
    static func validatedSummaryURL(_ url: URL) -> URL? {
        guard var components = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        ) else {
            return nil
        }
        guard components.scheme?.lowercased() == "https",
              let host = components.host?.lowercased(),
              !host.isEmpty,
              components.user == nil,
              components.password == nil,
              !isPrivateHost(host) else {
            return nil
        }
        components.scheme = "https"
        return components.url
    }

    private static func isPrivateHost(_ rawHost: String) -> Bool {
        let host = rawHost.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        if host == "localhost"
            || host.hasSuffix(".localhost")
            || host.hasSuffix(".local")
            || host.hasSuffix(".internal")
            || host.hasSuffix(".lan") {
            return true
        }
        if host.contains(":") {
            // IPv6 literals are uncommon webpage targets and include several
            // private/link-local encodings that are easy to disguise.
            return true
        }
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        let numericHost = host.allSatisfy { $0.isNumber || $0 == "." }
        guard numericHost else { return false }
        guard parts.count == 4,
              parts.allSatisfy({ part in
                  guard let value = Int(part) else { return false }
                  return (0...255).contains(value)
              }) else {
            return true
        }
        let octets = parts.compactMap { Int($0) }
        guard octets.count == 4 else { return true }
        let first = octets[0]
        let second = octets[1]
        return first == 0
            || first == 10
            || first == 127
            || (first == 100 && (64...127).contains(second))
            || (first == 169 && second == 254)
            || (first == 172 && (16...31).contains(second))
            || (first == 192 && second == 168)
            || first >= 224
    }
}

final class WebPageContentService: @unchecked Sendable {
    static let shared = WebPageContentService()

    private static let maximumResponseBytes = 2 * 1_024 * 1_024
    private static let maximumBodyCharacters = 40_000
    private let configurationTemplate: URLSessionConfiguration

    init(configuration: URLSessionConfiguration = .ephemeral) {
        let copy = configuration.copy() as? URLSessionConfiguration ?? .ephemeral
        copy.timeoutIntervalForRequest = 12
        copy.timeoutIntervalForResource = 18
        copy.requestCachePolicy = .reloadIgnoringLocalCacheData
        copy.urlCache = nil
        copy.httpCookieStorage = nil
        copy.httpShouldSetCookies = false
        copy.httpAdditionalHeaders = [
            "Accept": "text/html, application/xhtml+xml, text/plain;q=0.8",
            "User-Agent": "OSGKeyboard/2 WebpageSummary"
        ]
        configurationTemplate = copy
    }

    func fetchSummarySource(from sourceURL: URL) async throws -> WebPageContent {
        guard let url = WebPageURLPolicy.validatedSummaryURL(sourceURL) else {
            throw WebPageContentError.invalidURL
        }
        let configuration = configurationTemplate.copy() as? URLSessionConfiguration
            ?? .ephemeral
        let response = try await BoundedWebPageLoader(
            configuration: configuration,
            maximumBytes: Self.maximumResponseBytes
        ).load(url)
        guard let finalURL = WebPageURLPolicy.validatedSummaryURL(response.finalURL) else {
            throw WebPageContentError.invalidURL
        }
        let html = String(data: response.data, encoding: .utf8)
            ?? String(data: response.data, encoding: .isoLatin1)
        guard let html else {
            throw WebPageContentError.undecodableText
        }
        return try WebPageHTMLExtractor.extract(
            html: html,
            finalURL: finalURL,
            maximumBodyCharacters: Self.maximumBodyCharacters
        )
    }
}

private struct WebPageHTTPResponse: Sendable {
    let data: Data
    let finalURL: URL
}

private final class BoundedWebPageLoader:
    NSObject,
    URLSessionDataDelegate,
    URLSessionTaskDelegate,
    @unchecked Sendable {
    private let maximumBytes: Int
    private let queue: OperationQueue
    private let lock = NSLock()
    private var session: URLSession!
    private var continuation: CheckedContinuation<WebPageHTTPResponse, Error>?
    private var receivedData = Data()
    private var response: HTTPURLResponse?
    private var redirectCount = 0
    private var terminalError: WebPageContentError?
    private var finished = false

    init(configuration: URLSessionConfiguration, maximumBytes: Int) {
        self.maximumBytes = maximumBytes
        queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .userInitiated
        super.init()
        session = URLSession(
            configuration: configuration,
            delegate: self,
            delegateQueue: queue
        )
    }

    func load(_ url: URL) async throws -> WebPageHTTPResponse {
        try Task.checkCancellation()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                guard !finished else {
                    lock.unlock()
                    continuation.resume(throwing: CancellationError())
                    return
                }
                self.continuation = continuation
                lock.unlock()
                var request = URLRequest(url: url)
                request.httpMethod = "GET"
                session.dataTask(with: request).resume()
            }
        } onCancel: {
            self.finish(.failure(CancellationError()))
        }
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard let http = response as? HTTPURLResponse else {
            completionHandler(.cancel)
            finish(.failure(WebPageContentError.invalidResponse))
            return
        }
        guard (200..<300).contains(http.statusCode) else {
            completionHandler(.cancel)
            finish(.failure(WebPageContentError.httpStatus(http.statusCode)))
            return
        }
        if let mimeType = http.mimeType?.lowercased(),
           !Self.allowedMIMETypes.contains(mimeType) {
            completionHandler(.cancel)
            finish(.failure(WebPageContentError.unsupportedContentType))
            return
        }
        if http.expectedContentLength > Int64(maximumBytes) {
            completionHandler(.cancel)
            finish(.failure(WebPageContentError.responseTooLarge))
            return
        }
        lock.lock()
        self.response = http
        lock.unlock()
        completionHandler(.allow)
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive data: Data
    ) {
        lock.lock()
        guard !finished else {
            lock.unlock()
            return
        }
        guard receivedData.count + data.count <= maximumBytes else {
            terminalError = .responseTooLarge
            lock.unlock()
            dataTask.cancel()
            return
        }
        receivedData.append(data)
        lock.unlock()
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        lock.lock()
        redirectCount += 1
        let count = redirectCount
        lock.unlock()
        guard count <= 5 else {
            completionHandler(nil)
            finish(.failure(WebPageContentError.tooManyRedirects))
            return
        }
        guard let redirectedURL = request.url,
              let safeURL = WebPageURLPolicy.validatedSummaryURL(redirectedURL) else {
            completionHandler(nil)
            finish(.failure(WebPageContentError.invalidURL))
            return
        }
        var redirectedRequest = request
        redirectedRequest.url = safeURL
        redirectedRequest.httpMethod = "GET"
        completionHandler(redirectedRequest)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        lock.lock()
        let storedError = terminalError
        let storedResponse = response
        let data = receivedData
        lock.unlock()
        if let storedError {
            finish(.failure(storedError))
        } else if error != nil {
            finish(.failure(WebPageContentError.transport))
        } else if let finalURL = storedResponse?.url {
            finish(.success(WebPageHTTPResponse(data: data, finalURL: finalURL)))
        } else {
            finish(.failure(WebPageContentError.invalidResponse))
        }
    }

    private func finish(_ result: Result<WebPageHTTPResponse, Error>) {
        lock.lock()
        guard !finished else {
            lock.unlock()
            return
        }
        finished = true
        let continuation = continuation
        self.continuation = nil
        lock.unlock()
        session.invalidateAndCancel()
        continuation?.resume(with: result)
    }

    private static let allowedMIMETypes: Set<String> = [
        "text/html",
        "application/xhtml+xml",
        "text/plain"
    ]
}

enum WebPageHTMLExtractor {
    static func extract(
        html: String,
        finalURL: URL,
        maximumBodyCharacters: Int
    ) throws -> WebPageContent {
        let title = firstCapture(
            pattern: #"(?is)<title\b[^>]*>(.*?)</title>"#,
            in: html
        ).map(cleanInlineText)
        let selected = firstCapture(
            pattern: #"(?is)<article\b[^>]*>(.*?)</article>"#,
            in: html
        ) ?? firstCapture(
            pattern: #"(?is)<main\b[^>]*>(.*?)</main>"#,
            in: html
        ) ?? firstCapture(
            pattern: #"(?is)<body\b[^>]*>(.*?)</body>"#,
            in: html
        ) ?? html

        var text = replacing(
            pattern: #"(?is)<!--.*?-->"#,
            in: selected,
            with: " "
        )
        text = replacing(
            pattern: #"(?is)<(script|style|noscript|template|svg|canvas|nav|footer|aside|form|dialog)\b[^>]*>.*?</\1\s*>"#,
            in: text,
            with: " "
        )
        text = replacing(
            pattern: #"(?is)<br\s*/?>|</?(p|div|section|article|main|h[1-6]|li|ul|ol|tr|blockquote|pre)\b[^>]*>"#,
            in: text,
            with: "\n"
        )
        text = replacing(pattern: #"(?is)<[^>]+>"#, in: text, with: " ")
        text = decodeHTMLEntities(text)
        text = normalizedBody(text)
        guard text.count >= 40 else {
            throw WebPageContentError.emptyContent
        }
        if text.count > maximumBodyCharacters {
            text = String(text.prefix(maximumBodyCharacters))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let resolvedTitle = title.flatMap { $0.isEmpty ? nil : $0 }
        return WebPageContent(
            finalURL: finalURL,
            title: resolvedTitle,
            body: text
        )
    }

    private static func firstCapture(pattern: String, in text: String) -> String? {
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(
                  in: text,
                  range: NSRange(text.startIndex..., in: text)
              ),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[range])
    }

    private static func replacing(
        pattern: String,
        in text: String,
        with replacement: String
    ) -> String {
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return text
        }
        return expression.stringByReplacingMatches(
            in: text,
            range: NSRange(text.startIndex..., in: text),
            withTemplate: replacement
        )
    }

    private static func cleanInlineText(_ text: String) -> String {
        normalizedBody(
            decodeHTMLEntities(
                replacing(pattern: #"(?is)<[^>]+>"#, in: text, with: " ")
            )
        )
        .replacingOccurrences(of: "\n", with: " ")
    }

    private static func normalizedBody(_ text: String) -> String {
        let normalizedNewlines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        return normalizedNewlines
            .split(separator: "\n")
            .map {
                replacing(
                    pattern: #"[^\S\n]+"#,
                    in: String($0),
                    with: " "
                ).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private static func decodeHTMLEntities(_ source: String) -> String {
        var text = source
        let namedEntities = [
            "&nbsp;": " ",
            "&amp;": "&",
            "&lt;": "<",
            "&gt;": ">",
            "&quot;": "\"",
            "&#39;": "'",
            "&apos;": "'",
            "&ndash;": "–",
            "&mdash;": "—",
            "&hellip;": "…",
            "&lsquo;": "‘",
            "&rsquo;": "’",
            "&ldquo;": "“",
            "&rdquo;": "”"
        ]
        for (entity, value) in namedEntities {
            text = text.replacingOccurrences(of: entity, with: value)
        }
        guard let expression = try? NSRegularExpression(
            pattern: #"&#(?:([0-9]+)|x([0-9A-Fa-f]+));"#
        ) else {
            return text
        }
        let matches = expression.matches(
            in: text,
            range: NSRange(text.startIndex..., in: text)
        )
        for match in matches.reversed() {
            guard let fullRange = Range(match.range, in: text) else { continue }
            let decimal = Range(match.range(at: 1), in: text).flatMap {
                UInt32(text[$0], radix: 10)
            }
            let hexadecimal = Range(match.range(at: 2), in: text).flatMap {
                UInt32(text[$0], radix: 16)
            }
            guard let scalarValue = decimal ?? hexadecimal,
                  let scalar = UnicodeScalar(scalarValue) else {
                continue
            }
            text.replaceSubrange(fullRange, with: String(scalar))
        }
        return text
    }
}
