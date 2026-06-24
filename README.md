> ⚠️ **2026-06-24**: Default branch renamed from `main` to `0.2`. Old `main` is now `0.1`; `refactor/drop-qwen3-coreml` is now `0.2`. See CHANGELOG for details.

# OSGKeyboard

> Hold a key, speak, release — AI-polished text appears at your cursor in any app.
> A source-available, custom-keyboard-based voice input tool for iOS 26+, inspired by [Typeless](https://typeless.com) and [OpenLess](https://github.com/Open-Less/openless).

![Platform](https://img.shields.io/badge/platform-iOS%2026%2B-0078D4?logo=apple)
![Swift](https://img.shields.io/badge/Swift-6.0-FA7343?logo=swift)
![License](https://img.shields.io/badge/license-Source%20Available-blue)
![CI](https://github.com/hkgood/OSGKeyboard/actions/workflows/ci.yml/badge.svg)

[中文 README](./README.zh.md)

---

## What is it?

OSGKeyboard is a free, source-available alternative to commercial voice-input tools. It runs as a **Custom Keyboard Extension** on iOS, so you can use it in **any app** — Messages, Notes, Mail, ChatGPT, Claude, Cursor, you name it.

1. Press and hold the mic key
2. Speak naturally
3. Release — the AI polishes your words into clean text and inserts it at the cursor

The audio stays on-device (transcribed by Apple's on-device `SpeechAnalyzer` + `DictationTranscriber` on iOS 26+). Only the **polished transcript** is sent to your chosen cloud LLM. **No audio ever leaves your phone.**

---

## Features

- 🎙 **Push-to-talk** with a Typeless-style circular mic button
- 🧠 **On-device ASR** (`SpeechAnalyzer` + `DictationTranscriber`, iOS 26+)
- ✍️ **AI polishing** — adds structure, punctuation, fixes grammar, optionally produces lists
- 🧩 **Local + cloud polish toggle** — local engine is ASR-only by default; opt into a post-ASR cloud polish step (DeepSeek by default) when the iOS speech recognition isn't strong enough for your environment (noisy far-field audio, strong accents, etc.)
- 🔌 **Bring-your-own API** — works with any OpenAI-compatible endpoint (OpenAI, DeepSeek, Qwen DashScope, your own self-hosted server, …)
- 🔒 **Privacy first** — audio never leaves your device; transcripts only sent to the LLM you choose
- 🎨 **Native SwiftUI** — dark theme, frosted glass, ~2000 lines of Swift
- 🪶 **Zero dependencies** — no SwiftPM packages, no CocoaPods, no Carthage

---

## Quick start

### Requirements

- macOS with **Xcode 16+** (Xcode 26 recommended)
- iPhone running **iOS 26.0+**
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`
- An OpenAI-compatible API key (e.g. from [OpenAI](https://platform.openai.com/api-keys), [DeepSeek](https://platform.deepseek.com/api_keys), or [Qwen DashScope](https://dashscope.console.aliyun.com/apiKey))

### Build & run

```bash
git clone https://github.com/hkgood/OSGKeyboard.git
cd OSGKeyboard
xcodegen generate          # produces OSGKeyboard.xcodeproj
open OSGKeyboard.xcodeproj # or build via CLI:
xcodebuild -project OSGKeyboard.xcodeproj -scheme OSGKeyboard \
  -destination 'generic/platform=iOS Simulator' build
```

### Enable the keyboard in iOS

1. Run the app on your device or simulator.
2. Follow the 3-step onboarding: **enable the keyboard** in iOS Settings, then **allow Full Access** (required for the mic and LLM calls), then **paste your API key**.
3. In any text field, tap 🌐 to switch to **OSGKeyboard**.
4. Press and hold the mic, speak, release. ✨

> **"Allow Full Access" is required.** Without it, iOS blocks the keyboard from using the microphone and from making network requests. We never log, store, or transmit your keystrokes — see [`PrivacyInfo.xcprivacy`](./OSGKeyboard/PrivacyInfo.xcprivacy).

---

## Architecture

```
OSGKeyboard/
├── OSGKeyboard/                 # Main iOS app (settings, onboarding)
│   ├── Views/                   # SwiftUI screens
│   ├── OSGKeyboardApp.swift     # @main entry
│   ├── PrivacyInfo.xcprivacy    # Required privacy manifest
│   └── OSGKeyboard.entitlements # App Group declaration
├── OSGKeyboardExt/              # Custom Keyboard Extension
│   ├── KeyboardViewController.swift   # Principal class
│   ├── Services/
│   │   ├── AudioCaptureService.swift  # AVAudioEngine → 16 kHz PCM
│   │   ├── ASRService.swift           # iOS 26 SpeechAnalyzer ASR
│   │   └── PolishingService.swift     # LLM call with timeout
│   └── Views/                   # RecordButton, Waveform, KeyboardRootView
├── OSGKeyboardShared/           # Framework shared by app + extension
│   ├── Models/                  # ProviderConfig, LLMRequest, LLMProvider
│   ├── Services/                # LLMClient (OpenAI-compatible)
│   └── Constants/               # AppGroup identifier
├── OSGKeyboardTests/            # XCTest unit tests
├── project.yml                  # XcodeGen project definition
└── .github/workflows/ci.yml     # Lint + build CI
```

### Data flow

```
[Long-press mic] → AudioCaptureService → AudioBufferSnapshot (16 kHz mono)
                                          ↓
                                  ASRService.transcribe()
                                          ↓
                                ASREvent.final(rawTranscript)
                                          ↓
                              PolishingService.polish()
                                          ↓
                            LLMClient (OpenAI-compatible)
                                          ↓
                          textDocumentProxy.insertText(polished)
```

**Engine modes:**

- `cloud` (default): ASR runs on-device via `SpeechAnalyzer`, the transcript is
  sent to your configured LLM for polish.
- `local`: ASR runs on-device via `SpeechAnalyzer`. The transcript is inserted
  as-is — no cloud round-trip.
- `local` + "Cloud polish after ASR" toggle (Settings → On-device models):
  same as `cloud` in spirit, but routed via the local-engine pipeline so the
  keyboard extension can still use the on-device ASR; the transcript is sent
  to the configured LLM before insertion. Requires a DeepSeek (or other
  OpenAI-compatible) API key in the Keychain.

---

## Adding a new LLM provider

Open `OSGKeyboardShared/Models/LLMProvider.swift` and append a new `LLMProvider` to the `presets` array. The default `OpenAICompatibleClient` handles any endpoint that speaks the `POST /chat/completions` protocol.

```swift
LLMProvider(
    id: "groq",
    name: "Groq",
    defaultBaseURL: "https://api.groq.com/openai/v1",
    defaultModel: "llama-3.1-70b-versatile",
    apiKeyURL: URL(string: "https://console.groq.com/keys")
)
```

That's it. No other code changes required.

---

## Limitations

- iOS sandboxes keyboard extensions: ~60 MB memory cap, Full Access required.
- The keyboard does **not** work in password fields or some `WKWebView` textareas (iOS limitation).
- iOS 26+ only. Earlier iOS versions are not supported.

---

## License

[OSGKeyboard Source Available License](./LICENSE) — personal learning and non-commercial local use only. No commercial use, redistribution, or public forks without permission. Commercial licensing: [rocky.hk@gmail.com](mailto:rocky.hk@gmail.com).

---

## Acknowledgements

- Inspired by [Typeless](https://typeless.com) and the desktop open-source [OpenLess](https://github.com/Open-Less/openless)
- Built with [XcodeGen](https://github.com/yonaskolb/XcodeGen)
- Powered by Apple's [SpeechAnalyzer](https://developer.apple.com/documentation/speech/speechanalyzer) and [SFSpeechRecognizer](https://developer.apple.com/documentation/speech/sfspeechrecognizer)

---

**Note:** the project is published at [`hkgood/OSGKeyboard`](https://github.com/hkgood/OSGKeyboard); badges and git clone URLs already point there.
