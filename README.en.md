# OSGKeyboard

**Speak it. It's typed. You can also type, ask, and edit.**

OSGKeyboard is a voice input tool for iPhone, iPad, and Mac. Its iOS keyboard combines on-device dictation, Chinese and English typing, an AI assistant, clipboard skills, and optional managed credits in one input surface. On Mac, hold Option for global dictation.

![Platform](https://img.shields.io/badge/iOS%20%2F%20iPadOS-26%2B-0078D4?logo=apple)
![Platform](https://img.shields.io/badge/macOS-15%2B-555?logo=apple)
![Swift](https://img.shields.io/badge/Swift-6.0-FA7343?logo=swift)
![Version](https://img.shields.io/badge/version-2.0.0-3aa05a)
![License](https://img.shields.io/badge/license-Source%20Available-blue)

[Website](https://hkgood.github.io/OSGKeyboard/?lang=en) · [中文](./README.md) · [Privacy Policy](https://hkgood.github.io/OSGKeyboard/privacy/) · [Changelog](./CHANGELOG.md)

<p align="center">
  <a href="https://apps.apple.com/app/osgkeyboard/id6781553267">
    <img src="docs/assets/badges/ios-en.svg" alt="Download on the App Store" height="44">
  </a>
  &nbsp;
  <a href="https://github.com/hkgood/OSGKeyboard/releases/download/v1.1-mac/OSGKeyboard-1.1.dmg">
    <img src="docs/assets/badges/macos-en.svg" alt="Download historical macOS version 1.1" height="44">
  </a>
</p>

> The public Mac DMG is the signed and notarized historical version 1.1. The macOS target in this repository evolves with the 2.0 codebase; build with Xcode 26 for the latest source capabilities.

## One keyboard, four ways to input

### Voice dictation

- iOS 26 uses Apple `SpeechAnalyzer` and `DictationTranscriber` on-device by default
- Tap the microphone to start or stop; text lands in the current app at the cursor
- Optional AI polish, punctuation, structure, and post-polish translation
- Nine built-in polish styles, custom styles, Light / Heavy playful intensity, and optional mood emoji
- The Mac menu-bar app supports Option-hold global dictation; Apple Silicon Macs can download local Qwen3 MLX models

### Chinese and English typing

- Chinese: full pinyin, Microsoft double pinyin, Sogou double pinyin, optional fuzzy pairs, abbreviation ranking, and an expanded candidate panel
- English: three-slot QuickType, a ~40k-word offline lexicon, completion, correction, and next-word suggestions
- Touch behavior: proximity correction, overlapping presses, hold-to-delete, double-space period, and system Return semantics
- One personal dictionary participates in Chinese candidates, English suggestions, speech biasing, and polish protection

### Unified AI assistant

- Tap to dictate or hold to ask AI; voice and AI share one Assistant entry
- Answers stream into the keyboard and auto-insert only while the original field and cursor context still match
- Voice-edit the last verified OSGKeyboard insertion, then replace or append
- Follow the focused field with Send, Search, Go, Done, Next, or newline actions
- One undo action covers dictation, AI answers, edits, and clipboard pastes

### Clipboard and skills

- Clipboard history is off by default; when enabled, it keeps up to 15 plain-text items in the device-local App Group
- Reply, Summarize, and Translate appear briefly after a copy
- Built-in skills extract tasks and events, save to Notes, and open map navigation through Apple Shortcuts or map apps
- Create custom skills with a name, SF Symbol, prompt, and optional iCloud Shortcut
- Pin up to eight skills to the keyboard and reorder them by long press

## Three service paths

OSGKeyboard does not make cloud service the only option:

1. **On-device** — the default. Local iOS dictation requires no account or API key and does not upload raw audio.
2. **Bring your own provider (BYOK)** — configure your own cloud ASR / LLM credentials. Requests go directly to the selected provider, and credentials stay in Keychain.
3. **OSG managed credits** — optional on iOS / iPadOS. After Sign in with Apple, use managed speech and AI without entering provider credentials. Before first use, the app explains which data leaves the device and asks for explicit consent.

Local dictation and user-owned providers remain independent and never require an OSGKeyboard account.

## Optional account and credits

The iOS / iPadOS account center includes:

- Sign in with Apple, profile controls, sign-out, and in-app account deletion
- Managed balance, consumable App Store credit packs, and referrals
- Server verification of purchases and a synchronized credit ledger
- Short-lived, scope-limited managed-service grants for the keyboard extension

The voluntary `ByRockyACoffee` tip is separate from credit packs and does not unlock core functionality.

## History, statistics, and sync

- Home brings together seven-day dictation statistics, recent history, and the personal dictionary
- Voice history keeps up to 300 entries and supports day-based deletion
- Settings, personal dictionary, polish styles, history, and statistics can be selectively synced through private iCloud
- API keys stay in Keychain by default and replicate through iCloud Keychain only after iCloud settings sync is enabled; clipboard history, account tokens, and typing learning are not carried by settings sync

## Platform capabilities

| Capability | iOS / iPadOS 26+ | macOS 15+ |
|---|:---:|:---:|
| System keyboard / global hotkey | Custom keyboard | Hold Option |
| On-device speech | Apple SpeechAnalyzer | Qwen3 MLX (Apple Silicon) + Apple Speech fallback |
| Chinese full / double pinyin | Yes | — |
| English completion / correction | Yes | — |
| AI polish and translation | Yes | Yes |
| Unified assistant and voice questions | Yes | — |
| Clipboard history and skills | Yes | — |
| Optional OSG account and managed credits | Yes | — |
| Personal dictionary, history, and statistics | Yes | Yes |
| iCloud sync | Optional settings, dictionary, history, statistics, and more | Compatible shared data |

## Privacy principles

- **On-device first** — raw audio stays on-device with local recognition
- **Cloud by explicit action** — relevant data is sent only after you choose cloud recognition, polish, AI, or a skill
- **Transparent routing** — user-configured requests go directly to that provider; managed-credit requests go through `account.osglab.com`
- **No keystroke uploads** — Chinese candidate learning and English preferences remain local; secure fields are not learned
- **Clipboard control** — history is off by default, capped at 15 items, device-local, and never sends itself to AI
- **Credential isolation** — user API keys stay in Keychain; account session tokens stay in the main app's private Keychain
- **No ad tracking** — no advertising, analytics, or tracking SDKs, and no sale of personal data

See the [Privacy Policy](https://hkgood.github.io/OSGKeyboard/privacy/) for data categories, retention, account deletion, and third-party services.

## Quick start

### iPhone / iPad

1. Install OSGKeyboard from the App Store.
2. Follow onboarding to add the keyboard, enable Full Access, and grant microphone and speech-recognition permissions.
3. Choose local recognition, your own provider, or optional managed credits.
4. In any text field, switch to OSGKeyboard: tap to dictate, hold to ask AI, or enter Chinese / English typing.

### Mac

1. Download historical DMG 1.1, or build the current `OSGKeyboardMac` target from source.
2. Grant microphone and Accessibility permissions.
3. Hold Option in any app, speak, and release to insert.

## Build from source

Requirements:

- macOS
- Xcode 26+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

```bash
git clone https://github.com/hkgood/OSGKeyboard.git
cd OSGKeyboard
./Scripts/generate-xcodeproj.sh
open OSGKeyboard.xcodeproj
```

- iOS / iPadOS: run the `OSGKeyboard` scheme on an iOS 26 simulator or device
- macOS: build the `OSGKeyboardMac` scheme to produce `OSGKeyboard.app`
- Tests: use the suite manifest and scripts documented in [docs/TESTING.md](./docs/TESTING.md)

[project.yml](./project.yml) is the XcodeGen source of truth. The generated `.xcodeproj` is not tracked.

## Architecture at a glance

```text
OSGKeyboard/             iOS / iPadOS host app, Flow session, and settings
OSGKeyboardExt/          Custom keyboard extension
OSGKeyboardMac/          macOS menu-bar app and global dictation
OSGKeyboardShared/       Shared models, typing, sync, AI, and design system
OSGKeyboardHostSupport/  Host-only ASR, cloud clients, account, and StoreKit
```

On iOS, the host app owns audio capture and recognition for a Flow session. The keyboard extension sends lightweight commands and receives results through App Group. Managed services use short-lived, scope-limited grants, so the main app's account token is never exposed to the keyboard extension.

See [CONTRIBUTING.md](./CONTRIBUTING.md) for development, testing, and contribution guidelines, and [CHANGELOG.md](./CHANGELOG.md) for release history.

## Acknowledgements and notices

Major dependencies and inspirations include Apple Speech, librime, librime-xcframework, rime-pinyin-simp, NanoMouse, Hamster, mlx-audio-swift, Peter Norvig's public-domain n-gram counts, and Google Material Icons.

See [NOTICE-TYPING.md](./NOTICE-TYPING.md) for exact versions, licenses, and the OSG-owned English lexicon notice, or open Settings → About → Third-Party Licenses in the app.

## License

The [OSGKeyboard Source Available License](./LICENSE) is not an open-source or MIT license.

- Permitted: personal learning and non-commercial local building and use
- Prohibited: unauthorized redistribution, public derivatives, and commercial use
- Commercial licensing: [rocky.hk@gmail.com](mailto:rocky.hk@gmail.com)

<p align="center">
  开口即文字 · Speak it. It's typed.
</p>
