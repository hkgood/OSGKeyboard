// SafariSheet.swift
// OSGKeyboard · Main App

import SafariServices
import SwiftUI

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

struct SafariSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
