# OSGKeyboard

> Tap to talk, tap to stop — AI-polished text appears at your cursor in any app.
> A source-available, custom-keyboard-based voice input tool for iOS 26+, inspired by [Typeless](https://typeless.com) and [OpenLess](https://github.com/Open-Less/openless).

![Platform](https://img.shields.io/badge/platform-iOS%2026%2B-0078D4?logo=apple)
![Swift](https://img.shields.io/badge/Swift-6.0-FA7343?logo=swift)
![License](https://img.shields.io/badge/license-Source%20Available-blue)
![CI](https://github.com/hkgood/OSGKeyboard/actions/workflows/ci.yml/badge.svg)
![Version](https://img.shields.io/badge/version-0.2.1-3aa05a)

[中文 README](./README.zh.md) · [Privacy Policy](https://hkgood.github.io/OSGKeyboard/privacy/)

---

## What is it?

OSGKeyboard is a free, source-available alternative to commercial voice-input tools. It runs as a **Custom Keyboard Extension** on iOS, so you can use it in **any app** — Messages, Notes, Mail, WeChat, ChatGPT, Claude, Cursor, you name it.

1. Tap the mic to start recording
2. Speak naturally (up to 3.5 minutes / 210 seconds per take)
3. Tap again to stop — the AI polishes your words into clean text and inserts at the cursor

By default, audio is transcribed **on-device** by Apple's `SpeechAnalyzer` + `DictationTranscriber` (iOS 26+) — **no audio leaves your phone** unless you say so. If polish is enabled, only the transcript text goes to your chosen LLM. Optionally, you can switch to a **cloud ASR engine** (explicit opt-in with a confirmation): in that mode your recordings are uploaded to the ASR provider you configure.

Under the hood, OSGKeyboard uses a **Flow session model**: a long-lived audio session runs in the host app, the keyboard extension writes tiny "start / stop" signals to the App Group, and the polished text is delivered back to the keyboard for insertion. You do not need to jump back to the host app between recordings.

---

## Features

- 🎙 **Tap-to-toggle recording** with a Typeless-style circular mic button, 3.5-minute (210s) per-take cap with live countdown
- 🧠 **On-device ASR** (`SpeechAnalyzer` + `DictationTranscriber`, iOS 26+)
- ✍️ **AI polishing** — adds structure, punctuation, fixes grammar, optionally produces lists
- 🧩 **Local + cloud polish toggle** — local engine is ASR-only by default; opt into a post-ASR cloud polish step (DeepSeek by default) when the iOS speech recognition isn't strong enough for your environment (noisy far-field audio, strong accents, etc.)
- 🔌 **Bring-your-own API** — works with any OpenAI-compatible endpoint (OpenAI, DeepSeek, Qwen DashScope, Moonshot, Zhipu, your own self-hosted server, …)
- 🔒 **Privacy first** — on-device ASR by default, so audio never leaves your device unless you explicitly opt into the cloud engine; polish sends only the transcript to the LLM you choose
- 🎨 **Native SwiftUI** — dark theme, frosted glass, pure Swift 6, ~3,600 lines of code
- 🪶 **Zero dependencies** — no SwiftPM packages, no CocoaPods, no Carthage
- 🔁 **Flow session** — keep recording across multiple takes without bouncing back to the host app

---

## Quick start

### Requirements

- macOS with **Xcode 26** (matches `project.yml` deployment target iOS 26)
- iPhone or iPad running **iOS 26.0+** (iPad fully supported: Split View / Stage Manager, adaptive layout)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`
- An OpenAI-compatible API key (e.g. from [OpenAI](https://platform.openai.com/api-keys), [DeepSeek](https://platform.deepseek.com/api_keys), or [Qwen DashScope](https://dashscope.console.aliyun.com/apiKey)). Not needed if you stay on the "local ASR only" engine.

### Build & run

```bash
git clone https://github.com/hkgood/OSGKeyboard.git
cd OSGKeyboard
./Scripts/generate-xcodeproj.sh   # generates OSGKeyboard.xcodeproj via XcodeGen
open OSGKeyboard.xcodeproj        # or build via CLI:
xcodebuild -project OSGKeyboard.xcodeproj -scheme OSGKeyboard \
  -destination 'generic/platform=iOS Simulator' build
```

> The `OSGKeyboard.xcodeproj` is **not** committed — it is regenerated from
> `project.yml` by `Scripts/generate-xcodeproj.sh`. Always re-run the script
> after `git pull` if `project.yml` has changed.

### macOS distribution (decision)

The macOS menu-bar app ships via **Developer ID direct distribution** (notarized,
non-sandboxed), NOT the Mac App Store. This is deliberate: its core features —
global hold-to-talk hotkey, Accessibility-based text insertion into other apps,
and synthesized ⌘V — are incompatible with the Mac App Store sandbox, and a
sandboxed Accessibility grant also tends to reset after every app update.
`OSGKeyboardMac.entitlements` therefore keeps `com.apple.security.app-sandbox`
set to `false`; do not flip it back on without redesigning the insertion path.
(The iOS app targets the iOS App Store as usual — see `AUDIT_APPSTORE.md`.)

### Enable the keyboard in iOS

The host app walks you through a **5-step onboarding**:

1. **Welcome** — intro to OSGKeyboard
2. **Microphone** — request mic access
3. **Speech recognition** — request on-device speech recognition access
4. **Enable keyboard + Full Access** — open iOS Settings to add OSGKeyboard and allow Full Access
5. **Engine + API** — pick the local or cloud engine, then paste your API key (cloud / cloud-polish only)

After onboarding, in any text field, tap 🌐 to switch to **OSGKeyboard**, then tap the circular mic to start, speak, and tap again to stop.

> **"Allow Full Access" is required.** Without it, iOS blocks the keyboard from using the microphone and from making network requests. We never log, store, or transmit your keystrokes — see [`PrivacyInfo.xcprivacy`](./OSGKeyboard/PrivacyInfo.xcprivacy) and our [Privacy Policy](https://hkgood.github.io/OSGKeyboard/privacy/).

---

## Architecture

```
OSGKeyboard/
├── OSGKeyboard/                 # Main iOS app (host of the Flow session)
│   ├── Services/                # FlowSessionManager, AppPermissions, SpeechHistoryStore, …
│   ├── Views/                   # SwiftUI: OnboardingView, HomeView, SettingsView, HistoryView, …
│   ├── OSGKeyboardApp.swift     # @main entry, owns the FlowSessionManager
│   ├── PrivacyInfo.xcprivacy    # Required privacy manifest
│   └── OSGKeyboard.entitlements # App Group + Keychain Group
├── OSGKeyboardExt/              # Custom Keyboard Extension
│   ├── KeyboardViewController.swift   # Principal class (drives SwiftUI)
│   ├── Services/                # AppGroupPersistor, HostAppLauncher, AudioCaptureService (legacy, unused)
│   ├── Views/                   # KeyboardRootView, RecordButton, WaveformView
│   └── PrivacyInfo.xcprivacy
├── OSGKeyboardShared/           # Framework shared by app + extension (APPLICATION_EXTENSION_API_ONLY=YES)
│   ├── Services/                # FlowSessionBridge, FlowSessionDarwin, LLMClient, PolishingService, ASRService, Keychain, AppGroupStore, …
│   ├── Models/                  # LLMProvider, ProviderConfig, TranscriptionDelivery, AudioBufferSnapshot, …
│   ├── DesignSystem/            # Theme, ThemedRoot
│   └── Constants/               # AppGroup identifier
├── OSGKeyboardTests/            # XCTest unit tests (LLM, Keychain, ASR, Flow bridge, …)
├── OSGKeyboardExtTests/         # Keyboard-extension-side unit tests
├── Scripts/                     # generate-xcodeproj.sh, patch-icon-composer.sh
├── docs/                        # GitHub Pages site (privacy policy + landing)
├── project.yml                  # XcodeGen project definition (source of truth)
└── .github/workflows/ci.yml     # Lint + build CI
```

### Data flow — Flow session model

```
[Tap mic in keyboard]
  └─► KeyboardViewController.pressBegan
        └─► FlowSessionBridge.setRecordingState(.recording)  [App Group UserDefaults]
        └─► Darwin notification: "recordingState changed"
              └─► FlowSessionManager (host app) sees the signal
                    └─► FlowContinuousCapture feeds 16 kHz PCM into ChunkedUtterancePipeline
                          └─► ASRService.transcribe (iOS 26 SpeechAnalyzer)
                                └─► ASREvent.partial / .final
                                      └─► UtteranceTranscriptStitcher stitches the chunks
                                            └─► PolishingService (LLMClient)  [optional, configurable]
                                                  └─► FlowSessionBridge.storeTranscriptionResult
[Keyboard polls + Darwin notif]
  └─► KeyboardViewController sees the result
        └─► textDocumentProxy.insertText(polished)
```

**Engine modes:**

- `local` (default) — on-device ASR via `SpeechAnalyzer`; transcript is inserted as-is. No network round-trip.
- `local` + "Cloud polish after ASR" toggle (Settings → Engine) — same on-device ASR, but the transcript (text only) is routed through your configured LLM before insertion. Useful when iOS speech recognition isn't accurate enough in your environment.
- `cloud` (opt-in, requires an explicit confirmation) — **your voice recordings are uploaded** to the ASR provider you configure (e.g. OpenAI `/audio/transcriptions`, DashScope, Zhipu), and the resulting transcript is sent to your LLM for polish. Choose this only when you accept your provider's privacy terms.

**Cross-process plumbing (host app ↔ keyboard extension):**

- **App Group `group.com.osgkeyboard.shared`** — `UserDefaults` for the live Flow session state, recording state, audio levels, transcription delivery, and most preferences.
- **Shared Keychain group `com.osgkeyboard.shared`** — the LLM API key is written by the host app's Settings, read by both processes before every LLM call.
- **Darwin notifications (`CFNotificationCenter`)** — light-weight "something changed" pings; payloads still travel through the App Group.

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

That's it — no other code changes required.

To set it as the new default for first-time users, also bump the `defaultProviderId` constant used by `ProviderConfig`.

---

## Known limitations

- **iOS 26+ only.** Earlier iOS versions are not supported. We dropped the pre-26 SFSpeechRecognizer / AVAudioSession branching so the entire ASR path can use the iOS 26 `SpeechAnalyzer` API exclusively.
- **~60 MB memory cap** for the keyboard extension (iOS sandbox). The Flow session is hosted in the main app, so audio buffers and ASR models live there, not in the extension.
- **"Allow Full Access" required.** Without it, the keyboard can't reach the microphone or make network requests for cloud polish.
- **Password fields and some `WKWebView` textareas** are blocked by iOS itself — not something we can work around.
- **3.5-minute (210s) per-take cap.** A long take is automatically stopped and dispatched for transcription; a new take can be started immediately.
- **Force-quitting the host app does not resurrect the old session.** The Live Activity is cleared immediately; the next time you open the app (with permissions granted) a fresh voice session starts automatically.
- **3-minute per-utterance ASR cap.** If you exceed it, the pipeline gracefully splits into multiple stitched chunks.
- **No on-device LLM polish.** The local engine is ASR-only; "AI polish" is always cloud-based and configurable. On-device model support was explored in v0.2.0 and rolled back in v0.2.1 to keep the dependency surface at zero SPM packages.
- **URL scheme `osgkeyboard://`** can be opened by any app on the device. We don't trust it for anything beyond "wake the host app and (re)start the Flow session"; it never carries your API key or other secrets.

---

## Development

- **Build setup** — see the [Build Setup](#build-setup) section at the top of this file. Run `./Scripts/generate-xcodeproj.sh` after any `project.yml` change.
- **Tests** — `xcodebuild test -project OSGKeyboard.xcodeproj -scheme OSGKeyboard -destination 'platform=iOS Simulator,name=iPhone 17'` runs both `OSGKeyboardTests` and `OSGKeyboardExtTests` targets.
- **CI** — `.github/workflows/ci.yml` runs SwiftLint, a clean Debug build, and the test suite on every push to `0.1` / `0.2` and PRs.
- **Logging** — `print` is debug-only; release builds use `NSLog` for the few cross-process status messages.

---

## Project status

- **Current release: v0.2.1** (2026-06-24)
- **Default branch: `0.2`** (renamed from `main` on 2026-06-24; the previous `main` is preserved as `0.1`).
- See [`CHANGELOG.md`](./CHANGELOG.md) for the full release history and [`TYPEWHISPER_FLOW_MIGRATION_TRACKER.md`](./TYPEWHISPER_FLOW_MIGRATION_TRACKER.md) for the architecture-decision log behind the Flow session model.

---

## License

[OSGKeyboard Source Available License](./LICENSE) — personal learning and non-commercial local use only. No commercial use, redistribution, or public forks without permission. Commercial licensing: [rocky.hk@gmail.com](mailto:rocky.hk@gmail.com).

---

## Acknowledgements

- Inspired by [Typeless](https://typeless.com) and the desktop open-source [OpenLess](https://github.com/Open-Less/openless)
- Built with [XcodeGen](https://github.com/yonaskolb/XcodeGen)
- Powered by Apple's [SpeechAnalyzer](https://developer.apple.com/documentation/speech/speechanalyzer) and [SFSpeechRecognizer](https://developer.apple.com/documentation/speech/sfspeechrecognizer)
