// MacLegalWebView.swift
// OSGKeyboard · Mac
//
// In-app HTML viewer for bundled legal documents (privacy policy).

import SwiftUI
import WebKit

struct MacLegalWebView: NSViewRepresentable {
    let resourceName: String
    var scrollToAnchor: String?

    func makeCoordinator() -> Coordinator {
        Coordinator(scrollToAnchor: scrollToAnchor)
    }

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero)
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView

        guard let url = Bundle.main.url(forResource: resourceName, withExtension: "html") else {
            return webView
        }
        webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        context.coordinator.scrollToAnchor = scrollToAnchor
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var scrollToAnchor: String?
        weak var webView: WKWebView?

        init(scrollToAnchor: String?) {
            self.scrollToAnchor = scrollToAnchor
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard let anchor = scrollToAnchor, !anchor.isEmpty else { return }
            let escaped = anchor.replacingOccurrences(of: "'", with: "\\'")
            webView.evaluateJavaScript("location.hash = '#\(escaped)';") { _, _ in }
        }
    }
}
