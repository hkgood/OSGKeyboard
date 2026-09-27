# OSGKeyboard

**Speak it. It's typed. You can also type, ask, and edit.**

OSGKeyboard is a voice input tool for iPhone, iPad, and Mac. Its iOS keyboard combines on-device dictation, Chinese and English typing, an AI assistant, clipboard skills, and optional managed credits in one input surface. On Mac, hold Option for global dictation.

<p align="center">
  <img src="download/OSG_All-1600.png" srcset="download/OSG_All-1600.png 1600w, download/OSG_All.png 13742w" alt="OSGKeyboard running on iPad, Mac, and iPhone" width="100%">
</p>

![Platform](https://img.shields.io/badge/iOS%20%2F%20iPadOS-26%2B-0078D4?logo=apple)
![Platform](https://img.shields.io/badge/macOS-15%2B-555?logo=apple)
![Swift](https://img.shields.io/badge/Swift-6.0-FA7343?logo=swift)
![Version](https://img.shields.io/badge/version-2.1.0-3aa05a)
![License](https://img.shields.io/badge/license-Source%20Available-blue)

[Website](https://hkgood.github.io/OSGKeyboard/?lang=en) · [TestFlight Beta](https://testflight.apple.com/join/c2Bz4qK9) · [中文](./README.md) · [Privacy Policy](https://hkgood.github.io/OSGKeyboard/privacy/) · [Changelog](./CHANGELOG.md)

<p align="center">
  <a href="https://apps.apple.com/app/osgkeyboard/id6781553267">
    <img src="docs/assets/badges/ios-en.svg" alt="Download on the App Store" height="44">
  </a>
  &nbsp;
  <a href="https://github.com/hkgood/OSGKeyboard/releases/download/v1.1-mac/OSGKeyboard-1.1.dmg">
    <img src="docs/assets/badges/macos-en.svg" alt="Download historical macOS version 1.1" height="44">
  </a>
</p>

> The public Mac DMG is the signed and notarized historical version 1.1. The macOS target in this repository has moved forward with the 2.2 codebase; build with Xcode 26 for the latest source capabilities.
>
> The repository version follows [`project.yml`](./project.yml) (2.1.0, build 110). The `2.2.0` and later entries in CHANGELOG are already reflected in the capability descriptions below.

## One keyboard, four ways to input

### Voice + AI assistant: preview, then insert

- Tap the microphone to dictate or hold it to ask AI; voice and AI share one Assistant entry
- Answers stream into the keyboard and auto-insert only while the original field and cursor context still match
- Voice-edit the last verified OSGKeyboard insertion and replace or append
- Follow the focused field with Send, Search, Go, Done, Next, or newline
- One undo covers dictation, AI answers, edits, and clipboard pastes

### Voice input: on-device by default

- iOS and iPadOS use Apple `SpeechAnalyzer` and `DictationTranscriber` on-device by default
- A personal dictionary and contextual hotwords lift recognition of names, terminology, and phrases you use often
- Voice-edit the last text inserted by OSGKeyboard
- Optional AI polish: nine built-in styles, custom styles, Light / Heavy playful intensity, and optional mood emoji
- Optional post-polish translation that re-targets the polished result into your chosen language

### Chinese and English typing: effortless when speaking is not convenient

- **Chinese**: full pinyin, Ziranma, Xiaohe, Microsoft, and Sogou double pinyin — with fuzzy pairs, abbreviation ranking, candidate paging, number selection, swipe selection, and mixed Chinese-English input
- **English**: three-slot QuickType, a ~40k-word offline lexicon, prefix completion, autocorrect, next-word prediction, candidate undo, and sentence capitalization
- Touch behavior: proximity correction, overlapping presses, hold-to-delete, double-space period, and system Return semantics
- One personal dictionary participates in Chinese candidates, English suggestions, speech biasing, and polish protection

### Clipboard and skills: copy, then act

- Clipboard history is off by default; when enabled, it keeps up to 15 plain-text items in the device-local App Group
- On-device semantic analysis recommends up to five relevant actions from the complete skill catalog after a copy
- Built-in Reply, Summarize, Translate, Tasks, Events, Notes, and navigation through Apple Maps, Amap, or Baidu Maps
- Extract Tasks and Extract Events now write through native EventKit, with no companion Shortcut to install; Calendar uses write-only access so existing events are never read
- Create custom skills with a name, SF Symbol, prompt, and optional iCloud Shortcut
- Install any number of skills; manage and reorder them in the Skills tab while the keyboard dynamically shows relevant actions for the current clipboard text

## Three service paths

OSGKeyboard does not make cloud service the only option:

1. **On-device** — the default. Local iOS dictation requires no account or API key and does not upload raw audio. Apple Silicon Macs default to a local Qwen3 MLX model, with Apple Speech Recognition as a fallback.
2. **Bring your own provider (BYOK)** — configure your own cloud ASR / LLM credentials. Requests go directly to the selected provider, and credentials stay in Keychain.
3. **OSG managed credits** — optional on iOS / iPadOS. After Sign in with Apple, use managed speech and AI without entering provider credentials. Before first use, the app explains which data leaves the device and asks for explicit consent.

Local dictation and user-owned providers remain independent and never require an OSGKeyboard account.

First-run onboarding uses a short-lived anonymous credential issued after App Attest verification so users can try voice input, clipboard translation, smart reply, and hold-to-ask AI once each. These four lessons create no account, require no API key, and consume no credits. Afterward, users may skip sign-in or use Sign in with Apple to claim the eligible 1,000-credit signup reward.

## Optional account and credits

The iOS / iPadOS account center includes:

- Sign in with Apple, profile controls, sign-out, and in-app account deletion
- Managed balance, consumable App Store credit packs, and referrals
- Server verification of purchases and a synchronized credit ledger
- Short-lived, scope-limited managed-service grants for the keyboard extension; the main app's account token is never exposed to the keyboard

## History, statistics, and sync

- Home surfaces a monthly calendar, recent history, and the personal dictionary; the four metric cards for dictation characters, time, translation characters, and custom terms jump straight to their detail screens
- Voice history keeps up to 300 entries and supports day-based deletion; the corrected pre-polish ASR transcript and active-style metadata are kept alongside the final text for future style learning
- Settings, personal dictionary, polish styles, history, and statistics can be selectively synced through private iCloud
- API keys stay in Keychain by default and replicate through iCloud Keychain only after iCloud settings sync is enabled; clipboard history, account tokens, and typing learning are not carried by settings sync

## Reliability and recovery

- The keyboard loads engines on demand, samples memory throughout its lifetime, and proactively releases the Chinese engine, English lexicon, and in-flight pipeline work at the 40 MiB and 48 MiB budget thresholds; a hard shed waits while you are mid-composition
- MetricKit integration (iOS 26 and later) records crash, hang, CPU, and disk-write diagnostics on device — including keyboard-extension memory kills that never surface as crashes in App Store Connect — and exports them from Settings ▸ Diagnostics
- Beta builds (local Debug and TestFlight) batch-upload those diagnostics when the Settings toggle is on, so `0xdead10cc` shutdowns can be investigated without asking testers to export by hand; App Store builds never upload
- CI gates on a static check that the App Group identifier and the shared Keychain access-group ordering agree across the app, the keyboard extension, the Mac target, and `project.yml`

## Platform capabilities

| Capability | iOS / iPadOS 26+ | macOS 15+ |
|---|:---:|:---:|
| System keyboard / global hotkey | Custom keyboard | Hold Option |
| On-device speech | Apple SpeechAnalyzer | Qwen3 MLX (Apple Silicon) + Apple Speech fallback |
| Chinese full / double pinyin / fuzzy pairs | Yes | — |
| English completion / correction / next-word | Yes | — |
| AI polish and translation | Yes | Yes |
| Unified assistant and voice questions | Yes | — |
| Clipboard history and skills | Yes | — |
| Native Reminders / Calendar export | Yes | — |
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

## Frequently asked questions

**Do I need an OSG account?**
No. You do not need an OSG account for on-device dictation or when using providers you configure yourself. Sign in with Apple is used only for managed credits, credit purchases, referral rewards, and profile management.

**Does my audio get uploaded?**
On-device recognition does not upload your recordings. Audio leaves the device only when you explicitly choose cloud recognition configured with your own API key or cloud recognition paid for with managed credits.

**Why does the keyboard need Full Access?**
Full Access lets the keyboard share settings with the OSGKeyboard app, read saved provider configurations, and access the clipboard only after you opt in. We do not collect what you type during normal keyboard use.

**Is OSGKeyboard open source?**
No. It uses a source-available license for personal learning and non-commercial local use. Redistribution, public derivative versions, and commercial use require permission.

**Why is the Mac download version 1.1?**
The signed and notarized Mac installer currently available for download is version 1.1. The Mac source in the repository has moved forward to version 2.2; build it on macOS with Xcode 26 or later to use the latest capabilities.

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