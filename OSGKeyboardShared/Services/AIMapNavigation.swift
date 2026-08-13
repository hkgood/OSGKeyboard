// AIMapNavigation.swift
// OSGKeyboard · Shared
//
// Builds one turn-by-turn URL. Provider order is Amap (高德) → Baidu →
// Apple Maps. Shortcuts cannot call `canOpenURL`, so the host injects that
// check and passes the resulting URL to the companion Shortcut.

import Foundation

public enum AIMapProvider: String, Equatable, Sendable {
    case amap
    case baidu
    case apple
}

public enum AIMapNavigation: Sendable {
    public static let sourceApplication = "OSGKeyboard"
    public static let baiduSource = "ios.osgkeyboard"
    /// Amap's usual current-location label when we have no coordinates.
    public static let amapCurrentLocationName = "我的位置"

    public static func provider(canOpen: (URL) -> Bool) -> AIMapProvider {
        if canOpen(probe("iosamap")) || canOpen(probe("amapuri")) {
            return .amap
        }
        if canOpen(probe("baidumap")) {
            return .baidu
        }
        return .apple
    }

    public static func url(for route: AIMapRoute, canOpen: (URL) -> Bool) -> URL {
        switch provider(canOpen: canOpen) {
        case .amap:
            if canOpen(probe("iosamap")) {
                return amapURL(route, useLegacyScheme: true)
            }
            return amapURL(route, useLegacyScheme: false)
        case .baidu:
            return baiduURL(route)
        case .apple:
            return appleURL(route)
        }
    }

    /// Keyboard payload is `origin|destination`. Host turns it into one URL.
    public static func shortcutInput(
        from encoded: String,
        canOpen: (URL) -> Bool
    ) -> String? {
        guard let route = AIAddressExtraction.route(from: encoded) else { return nil }
        return url(for: route, canOpen: canOpen).absoluteString
    }

    // MARK: - Providers

    private static func amapURL(_ route: AIMapRoute, useLegacyScheme: Bool) -> URL {
        let originName = route.origin ?? amapCurrentLocationName
        let items = [
            URLQueryItem(name: "sourceApplication", value: sourceApplication),
            URLQueryItem(name: "sname", value: originName),
            URLQueryItem(name: "dname", value: route.destination),
            URLQueryItem(name: "dev", value: "0"),
            URLQueryItem(name: "t", value: "0"),
        ]
        if useLegacyScheme {
            return makeURL(scheme: "iosamap", host: "path", path: nil, items: items)
        }
        let url = makeURL(scheme: "amapuri", host: "route", path: "/plan/", items: items)
        // URLComponents drops the trailing slash; Amap's documented path is `/plan/`.
        let withSlash = url.absoluteString.replacingOccurrences(
            of: "://route/plan?",
            with: "://route/plan/?"
        )
        return URL(string: withSlash) ?? url
    }

    private static func baiduURL(_ route: AIMapRoute) -> URL {
        var items = [
            URLQueryItem(name: "destination", value: "name:\(route.destination)"),
            URLQueryItem(name: "mode", value: "driving"),
            URLQueryItem(name: "src", value: baiduSource),
        ]
        if let origin = route.origin {
            items.insert(
                URLQueryItem(name: "origin", value: "name:\(origin)"),
                at: 0
            )
        }
        return makeURL(scheme: "baidumap", host: "map", path: "/direction", items: items)
    }

    private static func appleURL(_ route: AIMapRoute) -> URL {
        var items = [
            URLQueryItem(name: "daddr", value: route.destination),
            URLQueryItem(name: "dirflg", value: "d"),
        ]
        if let origin = route.origin {
            items.insert(URLQueryItem(name: "saddr", value: origin), at: 0)
        }
        // `URLComponents(string: "maps://")` keeps the `://` that opening needs.
        var components = URLComponents(string: "maps://")!
        components.queryItems = items
        return components.url ?? URL(string: "maps://")!
    }

    private static func probe(_ scheme: String) -> URL {
        URL(string: "\(scheme)://")!
    }

    private static func makeURL(
        scheme: String,
        host: String?,
        path: String?,
        items: [URLQueryItem]
    ) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        if let path {
            components.path = path
        }
        components.queryItems = items
        return components.url ?? URL(string: "\(scheme)://")!
    }
}
