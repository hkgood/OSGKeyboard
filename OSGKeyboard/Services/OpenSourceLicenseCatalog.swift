// OpenSourceLicenseCatalog.swift
// OSGKeyboard · Main App
//
// Single source of truth for third-party open-source components shipped
// with OSGKeyboard. Consumed by Settings → About → Third-Party Licenses.
//
// Keep this list aligned with bundled resources and runtime downloads.
//
// iOS targets remain zero-SPM. macOS local ASR links mlx-audio-swift (vendored
// under ThirdParty/) for Qwen3 MLX streaming; model weights download via catalog.

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
            id: "mlx-audio-swift",
            name: "mlx-audio-swift",
            licenseName: "MIT",
            purpose: "macOS local Qwen3 MLX streaming ASR (MLXAudioSTT), linked only in the Mac app target.",
            url: URL(string: "https://github.com/Blaizzy/mlx-audio-swift"),
            licenseText: mitText
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

    Permission is hereby granted, free of charge, to any person obtaining a copy
    of this software and associated documentation files (the "Software"), to deal
    in the Software without restriction, including without limitation the rights
    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
    copies of the Software, and to permit persons to whom the Software is
    furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all
    copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
    SOFTWARE.
    """
}
