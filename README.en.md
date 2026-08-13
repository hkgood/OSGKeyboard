# OSGKeyboard

**Speak it. It's typed.**

Voice input for iPhone, iPad, and Mac. Speak in any app — polished text lands at your cursor.

![Platform](https://img.shields.io/badge/iOS%20%2F%20iPadOS-26%2B-0078D4?logo=apple)
![Platform](https://img.shields.io/badge/macOS-15%2B-555?logo=apple)
![Swift](https://img.shields.io/badge/Swift-6.0-FA7343?logo=swift)
![Version](https://img.shields.io/badge/version-1.7.5-3aa05a)
![License](https://img.shields.io/badge/license-Source%20Available-blue)

[Website](https://hkgood.github.io/OSGKeyboard/) · [中文 README](./README.md) · [Privacy Policy](https://hkgood.github.io/OSGKeyboard/privacy/)

<p align="center">
  <a href="https://apps.apple.com/app/osgkeyboard/id6781553267">
    <img src="docs/assets/badges/ios-en.svg" alt="Download now from the App Store" height="40">
  </a>
  &nbsp;
  <a href="https://github.com/hkgood/OSGKeyboard/releases/download/v1.1-mac/OSGKeyboard-1.1.dmg">
    <img src="docs/assets/badges/macos-en.svg" alt="Download historical macOS version 1.1" height="40">
  </a>
</p>

---

## Why OSGKeyboard

- **Works everywhere** — Messages, Notes, Notion, Cursor, Mail, WeChat — wherever you type
- **Speak, don't edit** — tap (iOS) or hold Option (Mac); AI adds punctuation and structure for you
- **Type in Chinese and English** — iOS keyboard ships full/double pinyin candidates, plus English autocomplete, autocorrect, and next-word prediction
- **On-device by default** — local recognition on iOS; optional local models on Mac. Cloud upload only when you opt in
- **Bring your own LLM** — local ASR needs no API key; polish and AI mode use your configured DeepSeek, OpenAI, Anthropic, OpenRouter, or compatible service
- **Mac global dictation** — menu-bar app, bottom overlay with live feedback, inserts into the frontmost app

---

## Three steps

1. **Install & authorize** — add the iOS keyboard with Full Access; grant mic + Accessibility on Mac
2. **Pick an engine** — local ASR works without a key; add your own API key for polish or AI mode
3. **Start talking** — switch to OSGKeyboard, or hold Option on Mac

---

## Platforms

| | iOS / iPadOS | macOS |
|---|:---:|:---:|
| Keyboard / global hotkey | ✅ | ✅ hold Option |
| Chinese typing (full / Microsoft / Sogou double pinyin) | ✅ optional fuzzy pairs | — |
| English typing (autocomplete / autocorrect / next-word) | ✅ offline lexicon + personal-dictionary boosts | — |
| Local speech recognition | ✅ SpeechAnalyzer | ✅ Qwen3 MLX streaming (0.6B 4-bit default) + Apple Speech fallback |
| AI polish | ✅ | ✅ |
| Voice AI questions (explicit Insert / Send) | ✅ | — |
| Voice-edit last input | ✅ | — |
| Post-polish translation | ✅ | ✅ |
| Personal dictionary | ✅ iCloud sync; protects polish and boosts English suggestions | ✅ |
| Dictation history | ✅ | ✅ |
| Live UI | — (silent background keep-alive) | ✅ floating pill |

---

## Privacy

Speech is transcribed on-device by default. Polish sends **text only** — the transcript and a small amount of nearby cursor text for continuity, never raw audio. Chinese candidate learning and English suggestion/autocorrect learning stay in the on-device App Group and are not uploaded. Secure fields disable English suggestions and autocorrect. Cursor context is not logged or saved to voice history. See the [Privacy Policy](https://hkgood.github.io/OSGKeyboard/privacy/).

---

## Get the app

**iPhone / iPad (App Store)**

<a href="https://apps.apple.com/app/osgkeyboard/id6781553267">
  <img src="docs/assets/badges/ios-en.svg" alt="Download now from the App Store" height="40">
</a>

**Mac (historical version 1.1, Developer ID signed and notarized)**

<a href="https://github.com/hkgood/OSGKeyboard/releases/download/v1.1-mac/OSGKeyboard-1.1.dmg">
  <img src="docs/assets/badges/macos-en.svg" alt="Download historical macOS version 1.1" height="40">
</a>

## Build from source

Requires macOS with **Xcode 26** and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
git clone https://github.com/hkgood/OSGKeyboard.git
cd OSGKeyboard
./Scripts/generate-xcodeproj.sh
open OSGKeyboard.xcodeproj
```

Run tests:

```bash
xcodebuild test -project OSGKeyboard.xcodeproj -scheme OSGKeyboard \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

---

## Architecture (brief)

```
OSGKeyboard/          Main iOS app (Flow session host)
OSGKeyboardExt/       Custom keyboard extension
OSGKeyboardMac/       macOS menu-bar app
OSGKeyboardShared/    App/extension shared models, typing, sync, and UI
OSGKeyboardHostSupport/ Host-only ASR, cloud, CLM, charts, and StoreKit
```

**Flow session model (iOS):** the host app keeps a long-lived audio session; the keyboard sends start/stop signals via App Group; polished text is delivered back for insertion.

**Engine modes:**

- `local` — on-device ASR; raw text without a key, optional polish with your configured LLM key
- `cloud` — uploads audio to your configured ASR provider, then polishes via LLM

See [CHANGELOG.md](./CHANGELOG.md) for release history and [CONTRIBUTING.md](./CONTRIBUTING.md) for PR guidelines.

---

## Adding an LLM provider

Append a preset in `OSGKeyboardShared/Models/LLMProvider.swift` — any OpenAI-compatible `/chat/completions` endpoint works out of the box.

---

## Acknowledgements

OSGKeyboard's voice and keyboard features build on these projects and platforms:

- [Typeless](https://typeless.com) — product inspiration for voice-first input
- [Apple SpeechAnalyzer](https://developer.apple.com/documentation/speech) — on-device iOS speech recognition
- [librime](https://github.com/rime/librime) and [librime-xcframework](https://github.com/ghostflyby/librime-xcframework) — Chinese input engine and static iOS packaging
- [NanoMouse](https://github.com/xjwhnxjwhn/nanomouse) and [Hamster](https://github.com/imfuxiao/Hamster) — references for iOS Rime lifecycle and architecture
- [rime-pinyin-simp](https://github.com/rime/rime-pinyin-simp), [Jieba](https://github.com/fxsjy/jieba), [phrase-pinyin-data](https://github.com/mozillazg/phrase-pinyin-data), and [pinyin-data](https://github.com/mozillazg/pinyin-data) — pinyin, phrase, and frequency data
- [mlx-audio-swift](https://github.com/Blaizzy/mlx-audio-swift) — local Qwen3 MLX streaming ASR on macOS
- [Google Material Icons](https://github.com/google/material-design-icons) — icon font used by the iOS app

See [Third-Party Notices](./NOTICE-TYPING.md) for exact versions and licenses (Chinese Rime stack plus the OSG-owned English lexicon notice), or open Settings → About → Third-Party Licenses in the app.

---

## License

[Source Available License](./LICENSE) — this is not an open-source license. Personal, non-commercial local use is permitted; redistribution and public derivatives require permission. Commercial licensing: [rocky.hk@gmail.com](mailto:rocky.hk@gmail.com).
