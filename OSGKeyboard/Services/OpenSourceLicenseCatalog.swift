// OpenSourceLicenseCatalog.swift
// OSGKeyboard · Main App
//
// Single source of truth for third-party components distributed by each
// OSGKeyboard platform. Consumed by Settings → About → Third-Party Licenses.
//
// Keep this list aligned with bundled resources and runtime downloads.

import Foundation

enum OpenSourceLicenseCatalog {

    enum Platform: Hashable {
        case iOS
        case macOS
    }

    struct Entry: Identifiable, Hashable {
        let id: String
        let name: String
        let licenseName: String
        /// One-line explanation shown in the popup and above the full text.
        let purpose: String
        let url: URL?
        /// Verbatim license body for the long-scroll disclosure page.
        let licenseText: String
        let platforms: Set<Platform>
    }

    /// Bundled libraries and runtime components referenced by the app.
    private static let allEntries: [Entry] = [
        .init(
            id: "material-icons",
            name: "Google Material Icons",
            licenseName: "Apache-2.0",
            purpose: "MaterialIcons-Regular.ttf bundled with the iOS app for Settings and navigation iconography.",
            url: URL(string: "https://github.com/google/material-design-icons"),
            licenseText: resourceText(
                named: "LICENSE-PINYIN-SIMP-APACHE",
                fallback: apache2Text
            ),
            platforms: [.iOS]
        ),
        .init(
            id: "librime-static",
            name: "librime 1.17.0 + static dependencies",
            licenseName: "BSD-3-Clause and others",
            purpose: "Chinese input runtime packaged by librime-xcframework 1.17.0-pack.1. Includes complete notices for Boost, OpenCC, LevelDB, yaml-cpp, glog, marisa-trie, RapidJSON, Darts and other statically linked components.",
            url: URL(string: "https://github.com/ghostflyby/librime-xcframework"),
            licenseText: resourceText(
                named: "LIBRIME-COMBINED-NOTICES",
                fallback: bsd3Text
            ),
            platforms: [.iOS]
        ),
        .init(
            id: "rime-pinyin-simp",
            name: "rime-pinyin-simp",
            licenseName: "Apache-2.0",
            purpose: "Permissive Simplified-Chinese baseline dictionary used to generate OSGKeyboard's Rime lexicon.",
            url: URL(string: "https://github.com/rime/rime-pinyin-simp"),
            licenseText: resourceText(
                named: "LICENSE-PINYIN-SIMP-APACHE",
                fallback: apache2Text
            ),
            platforms: [.iOS]
        ),
        .init(
            id: "jieba",
            name: "Jieba",
            licenseName: "MIT",
            purpose: "Modern Simplified-Chinese words and frequency weights used by the generated typing dictionary.",
            url: URL(string: "https://github.com/fxsjy/jieba"),
            licenseText: resourceText(
                named: "LICENSE-JIEBA-MIT",
                fallback: mitText
            ),
            platforms: [.iOS]
        ),
        .init(
            id: "phrase-pinyin-data",
            name: "phrase-pinyin-data",
            licenseName: "MIT",
            purpose: "Phrase pronunciation data used to resolve polyphonic Chinese words.",
            url: URL(string: "https://github.com/mozillazg/phrase-pinyin-data"),
            licenseText: resourceText(
                named: "LICENSE-PHRASE-PINYIN-DATA-MIT",
                fallback: mitText
            ),
            platforms: [.iOS]
        ),
        .init(
            id: "pinyin-data",
            name: "pinyin-data",
            licenseName: "MIT",
            purpose: "Per-character Mandarin pronunciation fallback for generated dictionary entries.",
            url: URL(string: "https://github.com/mozillazg/pinyin-data"),
            licenseText: resourceText(
                named: "LICENSE-PINYIN-DATA-MIT",
                fallback: mitText
            ),
            platforms: [.iOS]
        ),
        .init(
            id: "mlx-audio-swift",
            name: "mlx-audio-swift",
            licenseName: "MIT",
            purpose: "macOS local Qwen3 MLX streaming ASR (MLXAudioSTT), linked only in the Mac app target.",
            url: URL(string: "https://github.com/Blaizzy/mlx-audio-swift"),
            licenseText: mlxAudioMITText,
            platforms: [.macOS]
        ),
    ]

    static func entries(for platform: Platform) -> [Entry] {
        allEntries.filter { $0.platforms.contains(platform) }
    }

    private static func resourceText(named name: String, fallback: String) -> String {
        let bundles = Bundle.allFrameworks + Bundle.allBundles + [Bundle.main]
        for bundle in bundles {
            guard let url = bundle.url(forResource: name, withExtension: "txt"),
                  let text = try? String(contentsOf: url, encoding: .utf8),
                  !text.isEmpty else {
                continue
            }
            return text
        }
        return fallback
    }

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

    static let mlxAudioMITText = """
    MIT License

    Copyright (c) 2025 Prince Canuma

    \(mitText.components(separatedBy: "\n").dropFirst(2).joined(separator: "\n"))
    """

    static let bsd3Text = """
    BSD 3-Clause License

    Copyright (c) 2014, RIME Developers
    All rights reserved.

    Redistribution and use in source and binary forms, with or without
    modification, are permitted provided that the following conditions are met:

    1. Redistributions of source code must retain the above copyright notice,
       this list of conditions and the following disclaimer.
    2. Redistributions in binary form must reproduce the above copyright notice,
       this list of conditions and the following disclaimer in the documentation
       and/or other materials provided with the distribution.
    3. Neither the name of the copyright holder nor the names of its contributors
       may be used to endorse or promote products derived from this software
       without specific prior written permission.

    THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
    AND ANY EXPRESS OR IMPLIED WARRANTIES ARE DISCLAIMED. IN NO EVENT SHALL THE
    COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DAMAGES ARISING IN ANY WAY
    OUT OF THE USE OF THIS SOFTWARE.
    """
}
