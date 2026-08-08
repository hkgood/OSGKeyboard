// RemoteWebView.swift
// OSGKeyboard · Main App
//
// In-app WKWebView for remote HTTPS pages (e.g. GitHub Issues, release notes).

import SwiftUI
import WebKit

struct RemoteWebView: UIViewRepresentable {
    let url: URL
    @Binding var isLoading: Bool
    /// When true, strip page `env(safe-area-inset-*)` bottom padding after load
    /// (sheets already lay out above the home indicator).
    var neutralizeSafeAreaPadding: Bool = false

    func makeCoordinator() -> Coordinator {
        Coordinator(isLoading: $isLoading, neutralizeSafeAreaPadding: neutralizeSafeAreaPadding)
    }

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        Self.applyScrollInsets(webView)
        webView.navigationDelegate = context.coordinator
        context.coordinator.loadedURL = url
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        context.coordinator.neutralizeSafeAreaPadding = neutralizeSafeAreaPadding
        Self.applyScrollInsets(uiView)
        guard context.coordinator.loadedURL != url else { return }
        context.coordinator.loadedURL = url
        uiView.load(URLRequest(url: url))
    }

    /// Kill automatic safe-area insets that leave a dead band under the page.
    static func applyScrollInsets(_ webView: WKWebView) {
        let scroll = webView.scrollView
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.contentInset = .zero
        scroll.scrollIndicatorInsets = .zero
        scroll.automaticallyAdjustsScrollIndicatorInsets = false
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        @Binding var isLoading: Bool
        var loadedURL: URL?
        var neutralizeSafeAreaPadding: Bool

        init(isLoading: Binding<Bool>, neutralizeSafeAreaPadding: Bool) {
            _isLoading = isLoading
            self.neutralizeSafeAreaPadding = neutralizeSafeAreaPadding
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            isLoading = true
            RemoteWebView.applyScrollInsets(webView)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isLoading = false
            RemoteWebView.applyScrollInsets(webView)
            guard neutralizeSafeAreaPadding else { return }
            // Remote HTML may still use env(safe-area-inset-bottom); neutralize in-app.
            webView.evaluateJavaScript(
                """
                (function () {
                  var s = document.getElementById('osg-webview-safe-area-fix');
                  if (!s) {
                    s = document.createElement('style');
                    s.id = 'osg-webview-safe-area-fix';
                    document.head.appendChild(s);
                  }
                  s.textContent = 'html{height:100%;} body{min-height:100%;padding-bottom:24px!important;}';
                })();
                """,
                completionHandler: nil
            )
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            isLoading = false
            RemoteWebView.applyScrollInsets(webView)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            isLoading = false
            RemoteWebView.applyScrollInsets(webView)
        }
    }
}
