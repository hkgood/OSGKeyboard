// ModelDownloadSourcePicker.swift
// OSGKeyboard · Main App
//
// Picks ModelScope vs Hugging Face by probing both mirrors on the
// user's current network. Result is cached briefly so consecutive
// downloads in one session don't re-probe.

import Foundation
import os

enum ModelDownloadSourcePicker {

    private struct CacheState {
        var source: ModelDownloadSource?
        var expiresAt: Date?
    }

    private static let lock = OSAllocatedUnfairLock(initialState: CacheState())
    private static let cacheTTL: TimeInterval = 300

    /// Resolves the fastest reachable mirror for the current network.
    static func resolve() async -> ModelDownloadSource {
        if let cached = cachedValue() { return cached }

        let winner = await probeFastest() ?? defaultHeuristic()
        storeCache(winner)
        return winner
    }

    /// Alternate mirror — used when the first download attempt fails.
    static func alternate(to source: ModelDownloadSource) -> ModelDownloadSource {
        switch source {
        case .modelScope:  return .huggingface
        case .huggingface: return .modelScope
        }
    }

    // MARK: - Probe

    private static func probeFastest() async -> ModelDownloadSource? {
        await withTaskGroup(of: (ModelDownloadSource, TimeInterval)?.self) { group in
            for source in ModelDownloadSource.allCases {
                group.addTask {
                    guard let latency = await probeLatency(for: source) else { return nil }
                    return (source, latency)
                }
            }

            var best: (ModelDownloadSource, TimeInterval)?
            for await candidate in group {
                guard let candidate else { continue }
                if best == nil || candidate.1 < best!.1 {
                    best = candidate
                }
            }
            return best?.0
        }
    }

    private static func probeLatency(for source: ModelDownloadSource) async -> TimeInterval? {
        guard let url = probeURL(for: source) else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 4
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let started = CFAbsoluteTimeGetCurrent()
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return nil }
            guard (200...399).contains(http.statusCode) else { return nil }
            return CFAbsoluteTimeGetCurrent() - started
        } catch {
            // Some hosts reject HEAD — retry with a tiny GET.
            var get = URLRequest(url: url)
            get.httpMethod = "GET"
            get.timeoutInterval = 4
            get.cachePolicy = .reloadIgnoringLocalCacheData
            do {
                let (_, response) = try await URLSession.shared.data(for: get)
                guard let http = response as? HTTPURLResponse else { return nil }
                guard (200...399).contains(http.statusCode) else { return nil }
                return CFAbsoluteTimeGetCurrent() - started
            } catch {
                return nil
            }
        }
    }

    private static func probeURL(for source: ModelDownloadSource) -> URL? {
        switch source {
        case .modelScope:
            return URL(string: "https://modelscope.cn")
        case .huggingface:
            return URL(string: "https://huggingface.co")
        }
    }

    /// When both probes fail (offline, captive portal, etc.).
    private static func defaultHeuristic() -> ModelDownloadSource {
        if Locale.current.region?.identifier == "CN" { return .modelScope }
        if TimeZone.current.identifier.hasPrefix("Asia/Shanghai") { return .modelScope }
        return .huggingface
    }

    // MARK: - Cache

    private static func cachedValue() -> ModelDownloadSource? {
        lock.withLock { state in
            guard let source = state.source,
                  let expiresAt = state.expiresAt,
                  expiresAt > Date() else {
                return nil
            }
            return source
        }
    }

    private static func storeCache(_ source: ModelDownloadSource) {
        lock.withLock { state in
            state.source = source
            state.expiresAt = Date().addingTimeInterval(cacheTTL)
        }
    }
}
