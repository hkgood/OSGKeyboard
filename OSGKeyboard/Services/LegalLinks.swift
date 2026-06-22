// LegalLinks.swift
// OSGKeyboard · Main App

import Foundation

enum LegalLinks {
    static let repositoryURL = URL(string: "https://github.com/hkgood/OSGKeyboard")!

    /// Public privacy policy (GitHub Pages). Also bundled in-app as PrivacyPolicy.html.
    static var privacyPolicyURL: URL? {
        URL(string: "https://hkgood.github.io/OSGKeyboard/privacy/")
    }

    /// Support / feedback (GitHub Issues).
    static var supportURL: URL? {
        URL(string: "https://github.com/hkgood/OSGKeyboard/issues")
    }
}
