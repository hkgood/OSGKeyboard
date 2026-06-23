// LegalWebView.swift
// OSGKeyboard · Main App
//
// In-app HTML viewer for bundled legal documents (privacy policy).

import SwiftUI
import WebKit

struct LegalWebView: UIViewRepresentable {
    let resourceName: String
    var scrollToAnchor: String?

    func makeCoordinator() -> Coordinator {
        Coordinator(scrollToAnchor: scrollToAnchor)
    }

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView

        guard let url = Bundle.main.url(forResource: resourceName, withExtension: "html") else {
            return webView
        }
        webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
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
