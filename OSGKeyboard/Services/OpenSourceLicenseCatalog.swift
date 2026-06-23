// OpenSourceLicenseCatalog.swift
// OSGKeyboard · Main App
//
// Single source of truth for third-party open-source components shipped
// with OSGKeyboard. Consumed by Settings → About → Third-Party Licenses.
//
// Keep this list aligned with `project.yml` package dependencies.
//
// v0.2.0: dropped the `Qwen3Speech` SPM fork (Qwen3 CoreML ASR is gone)
// and the `aufklarer/Qwen3-ASR-CoreML` runtime artefact. The local
// engine now ships with iOS 26 `SpeechAnalyzer` + `DictationTranscriber`
// and has no on-device ML dependencies of our own.

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

    /// Bundled libraries referenced by the app. v0.2.0 no longer pulls in
    /// `soniqo/speech-swift` (we use iOS 26 `SpeechAnalyzer` instead) and
    /// no longer downloads `Qwen3-ASR-CoreML` weights — both entries are
    /// intentionally absent.
    static let entries: [Entry] = [
        .init(
            id: "material-icons",
            name: "Google Material Icons",
            licenseName: "Apache-2.0",
            purpose: "MaterialIcons-Regular.ttf bundled for Settings and navigation iconography.",
            url: URL(string: "https://github.com/google/material-design-icons"),
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

    static let mitText = """
    MIT License

    Copyright (c) 2023 Apple Inc.

    Permission is hereby granted, free of charge, to any person
    obtaining a copy of this software and associated documentation
    files (the "Software"), to deal in the Software without
    restriction, including without limitation the rights to use, copy,
    modify, merge, publish, distribute, sublicense, and/or sell copies
    of the Software, and to permit persons to whom the Software is
    furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be
    included in all copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
    EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
    MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
    NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
    HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
    WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
    DEALINGS IN THE SOFTWARE.
    """
}