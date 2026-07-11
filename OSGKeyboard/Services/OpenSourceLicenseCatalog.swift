// OpenSourceLicenseCatalog.swift
// OSGKeyboard · Main App
//
// Single source of truth for third-party open-source components shipped
// with OSGKeyboard. Consumed by Settings → About → Third-Party Licenses.
//
// Keep this list aligned with bundled resources and runtime downloads.
//
// iOS targets remain zero-SPM. macOS local ASR downloads the sherpa-onnx
// runtime binary on demand; model weights are cached under Application Support.

import Foundation

enum OpenSourceLicenseCatalog {

    struct Entry: Identifiable, Hashable {
        let id: String
        let name: String
        let licenseName: String
        /// One-line explanation shown in the popup and above the full text.
        let purpose: String
        let url: URL?
        /// Verbatim license body for the long-scroll disclosure page.
        let licenseText: String
    }

    /// Bundled libraries and runtime components referenced by the app.
    static let entries: [Entry] = [
        .init(
            id: "material-icons",
            name: "Google Material Icons",
            licenseName: "Apache-2.0",
            purpose: "MaterialIcons-Regular.ttf bundled with the iOS app for Settings and navigation iconography.",
            url: URL(string: "https://github.com/google/material-design-icons"),
            licenseText: apache2Text
        ),
        .init(
            id: "sherpa-onnx",
            name: "sherpa-onnx",
            licenseName: "Apache-2.0",
            purpose: "macOS local ASR runtime (`sherpa-onnx-offline`) downloaded at install time and cached on device.",
            url: URL(string: "https://github.com/k2-fsa/sherpa-onnx"),
            licenseText: apache2Text
        ),
    ]

    // MARK: - License bodies

    static let apache2Text = """
    Apache License
    Version 2.0, January 2004
    http://www.apache.org/licenses/

    Licensed under the Apache License, Version 2.0 (the "License");
    you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

        http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software
    distributed under the License is distributed on an "AS IS" BASIS,
    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
    implied. See the License for the specific language governing
    permissions and limitations under the License.
    """
}
