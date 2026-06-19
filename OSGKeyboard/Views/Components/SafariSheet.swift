// SafariSheet.swift
// OSGKeyboard · Main App

import SafariServices
import SwiftUI
import OSGKeyboardShared

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

struct SafariSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: url)
        controller.preferredControlTintColor = UIColor(Palette.accent)
        return controller
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
