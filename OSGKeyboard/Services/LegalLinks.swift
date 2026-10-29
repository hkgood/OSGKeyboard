// LegalLinks.swift
// OSGKeyboard · Main App

import Foundation

enum LegalLinks {
    static let repositoryURL = URL(string: "https://github.com/hkgood/OSGKeyboard")!

    /// Public privacy policy. Served from the mainland-hosted website so the
    /// China storefront (ICP filing) can reach a备案 domain; also bundled
    /// in-app as PrivacyPolicy.html.
    static var privacyPolicyURL: URL? {
        URL(string: "https://osg.osglab.com/privacy/")
    }

    /// Support / feedback (GitHub Issues).
    static var supportURL: URL? {
        URL(string: "https://github.com/hkgood/OSGKeyboard/issues")
    }

    /// In-app release notes (hosted on download.osglab.com). Prefer
    /// `ReleaseNotesStore.pageURL(language:colorScheme:)` so v/lang/theme are set.
    static var releaseNotesURL: URL? {
        URL(string: ReleaseNotesStore.pageURLString)
    }
}
