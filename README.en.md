# OSGKeyboard

**Speak it. It's typed.**

Voice input for iPhone, iPad, and Mac. Speak in any app — polished text lands at your cursor.

![Platform](https://img.shields.io/badge/iOS%20%2F%20iPadOS-26%2B-0078D4?logo=apple)
![Platform](https://img.shields.io/badge/macOS-14%2B-555?logo=apple)
![Swift](https://img.shields.io/badge/Swift-6.0-FA7343?logo=swift)
![Version](https://img.shields.io/badge/version-0.5.3-3aa05a)
![License](https://img.shields.io/badge/license-Source%20Available-blue)

[Website](https://hkgood.github.io/OSGKeyboard/) · [中文 README](./README.md) · [Privacy Policy](https://hkgood.github.io/OSGKeyboard/privacy/)

<p align="center">
  <a href="https://apps.apple.com/app/osgkeyboard/id6781553267">
    <img src="docs/assets/badges/ios-en.svg" alt="Download now from the App Store" height="40">
  </a>
  &nbsp;
  <a href="https://github.com/hkgood/OSGKeyboard/releases/download/v1.1-mac/OSGKeyboard-1.1.dmg">
    <img src="docs/assets/badges/macos-en.svg" alt="Download now — macOS version" height="40">
  </a>
</p>

---

## Why OSGKeyboard

- **Works everywhere** — Messages, Notes, Notion, Cursor, Mail, WeChat — wherever you type
- **Speak, don't edit** — tap (iOS) or hold Option (Mac); AI adds punctuation and structure for you
- **On-device by default** — local recognition on iOS; optional local models on Mac. Cloud upload only when you opt in
- **Bring your own LLM** — built-in polish out of the box, or plug in DeepSeek, OpenAI, Anthropic, OpenRouter, and more
- **Mac global dictation** — menu-bar app, bottom overlay with live feedback, inserts into the frontmost app

---

## Three steps

1. **Install & authorize** — add the iOS keyboard with Full Access; grant mic + Accessibility on Mac
2. **Pick an engine** — local ASR + built-in polish (zero config), or your own API keys
3. **Start talking** — switch to OSGKeyboard, or hold Option on Mac

---

## Platforms

| | iOS / iPadOS | macOS |
|---|:---:|:---:|
| Keyboard / global hotkey | ✅ | ✅ hold Option |
| Full / Microsoft / Sogou double pinyin | ✅ optional fuzzy pairs | — |
| Local speech recognition | ✅ SpeechAnalyzer | ✅ SenseVoice / Qwen3 |
| AI polish | ✅ | ✅ |
| Post-polish translation | ✅ | ✅ |
| Personal dictionary | ✅ iCloud sync | ✅ |
| Dictation history | ✅ | ✅ |
| Live UI | ✅ Dynamic Island | ✅ floating pill |

---

## Privacy

Speech is transcribed on-device by default. Polish sends **text only** — the transcript and a small amount of nearby cursor text for continuity, never raw audio. Chinese candidate learning stays in the on-device App Group and is not uploaded. Cursor context is not logged or saved to voice history, and secure fields are never captured. See the [Privacy Policy](https://hkgood.github.io/OSGKeyboard/privacy/).

---

## Get the app

**iPhone / iPad (App Store)**

<a href="https://apps.apple.com/app/osgkeyboard/id6781553267">
  <img src="docs/assets/badges/ios-en.svg" alt="Download now from the App Store" height="40">
</a>

**Mac (Developer ID signed and notarized)**

<a href="https://github.com/hkgood/OSGKeyboard/releases/download/v1.1-mac/OSGKeyboard-1.1.dmg">
  <img src="docs/assets/badges/macos-en.svg" alt="Download now — macOS version" height="40">
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
OSGKeyboardShared/    Shared framework (ASR, LLM, sync, design system)
```

**Flow session model (iOS):** the host app keeps a long-lived audio session; the keyboard sends start/stop signals via App Group; polished text is delivered back for insertion.

**Engine modes:**

- `local` — on-device ASR; built-in polish (or your own LLM key)
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

See [Third-Party Notices](./NOTICE-TYPING.md) for exact versions and licenses, or open Settings → About → Third-Party Licenses in the app.

---

## License

[Source Available License](./LICENSE) — personal, non-commercial use only. Commercial licensing: [rocky.hk@gmail.com](mailto:rocky.hk@gmail.com).
