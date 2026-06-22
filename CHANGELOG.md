# Changelog

All notable changes to OSGKeyboard will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.2.0] - 2026-06-22

### Added
- **Local engine with on-device Qwen models**: Optional Qwen3-ASR 0.6B speech recognition and Qwen3.5-0.8B text polish, fully offline after download.
- **On-device model management**: Download, progress, delete, and readiness status in Settings; mirror auto-selection between ModelScope and Hugging Face with fallback.
- **Engine picker**: Choose between local (on-device ASR + polish) and cloud (ASR + user-configured LLM polish).
- **Flow session dictation**: TypeWhisper-style continuous capture in the host app with keyboard handoff via App Group.
- **Open-source licenses** screen for bundled third-party components.

### Changed
- **Settings simplified**: Merged language and model sections; cloud mode always enables polish (removed off/transcribe mode picker).
- **Keyboard UI**: Local/cloud engine badges replace the mode menu; shows model-not-downloaded guidance when the local stack is incomplete.
- **iPhone only**: Set `TARGETED_DEVICE_FAMILY` to `"1"` for both targets; portrait-only orientations.
- **Keyboard preview always dark**: Preview injects the dark palette regardless of app theme.
- **Docs consistency**: README/README.zh aligned to the iOS 26+ capability set.

### Fixed
- **ModelScope download progress**: Progress now tracks byte counts instead of jumping to 50% after the first file.
- **Light/Dark mode consistency** for shared button/card modifiers via `@Environment(\.themePalette)`.

## [0.1.2] - 2026-06-20

### Fixed
- **Light/Dark mode consistency**: `cardSurface()`, `primaryButton()`, `secondaryButton()`, and `pillChip()` view modifiers in `Theme.swift` now use `ViewModifier` structs that read from `@Environment(\.themePalette)`. Previously they used hardcoded dark `Palette` constants, causing cards and buttons to always render in dark mode even when the main App was in light mode.
- **TestFlight error 90474** (Invalid bundle): Added `UIRequiresFullScreen: true` and all four `UISupportedInterfaceOrientations` values to `Info.plist` via `project.yml`. The app targets iPhone + iPad (`TARGETED_DEVICE_FAMILY: "1,2"`), and Apple requires all four orientations for iPad multitasking; setting `UIRequiresFullScreen` opts out of slide-over/split-view while still satisfying the validator.
- **Keyboard Preview cycling**: The "Tap the disc to cycle states" prompt now actually works. `KeyboardPreviewStub` gained an `onTap` closure wired to `cyclePhase()` in `KeyboardPreviewSheet`, which rotates `.idle → .recording → .processing → .idle` with animation. Sample transcript text is shown during the `.recording` phase.

### Added
- **Dynamic ASR locale picker**: Settings now loads the full list of supported locales from `SFSpeechRecognizer.supportedLocales()` on appear (off the main thread). Each locale shows an on-device badge (iPhone icon) when the device supports on-device recognition for that language — giving users confidence about which locales avoid sending audio to the cloud. A static fallback list is shown while the async load is in progress.
- `Speech.framework` linked to the main App target in `project.yml` (needed by the new dynamic locale loader in `SettingsView`).

### Changed
- `pillChip(foreground:)` signature changed from `foreground: Color = Palette.textSecondary` to `foreground: Color? = nil`; callers that pass an explicit color are unaffected.

> **Note: v0.1.1 polish** — this is a small follow-up to v0.1.0 focused on review-driven cleanup
> (theme follow-up, ASR robustness, debug-print hygiene, docs). **No features are removed.**
### Fixed
- **PrivacyInfo.xcprivacy audited for honesty**: removed the three undeclared `NSPrivacyAccessedAPIType` entries (`FileTimestamp` / `DiskSpace` / `SystemBootTime`) the project doesn't actually use, and added `ActiveKeyboards` (reason `DDA9.1`) to the keyboard extension's manifest because `advanceToNextInputMode()` is in the tap path. The main App now declares only `UserDefaults` (reason `CA92.1`), which is the only Required Reason API it touches.
- **Theme follows system appearance**: main App now renders a true light palette in light mode via `ThemedRoot` + `EnvironmentKey<ThemePalette>`. The keyboard extension deliberately stays dark (Apple's default) and now uses a transparent `.background(Color.clear)` so the system UI chrome shows through.
- **Speech Recognition permission requested on first press**: added `NSSpeechRecognitionUsageDescription` to both targets' `Info.plist` and an explicit `SFSpeechRecognizer.requestAuthorization` call inside `pressBegan()`. Without these, speech authorization could remain `.denied` and recognition would fail silently.
- **ASRService emits a DEBUG warning when on-device recognition isn't supported**, so it's obvious during dev that the request fell back to cloud.
- **App Group fallback behaviour**:
  - In `DEBUG`, a missing App Group now `fatalError`s with a precise remediation message (was a soft print + `.standard` fallback, which desynced the keyboard extension from the main App).
  - In release, the fallback is preserved but logged via `NSLog`.
- **`KeyboardViewController.loadPersistedLocale` self-check** (DEBUG only) prints the active provider / baseURL / masked API key / mode / locale, so the keyboard extension's view of the App Group is visible in the device console.
- **`KeyboardViewController.handleFinalTranscript` typed-error routing**: `LLMError.noAPIKey` (401) and `LLMError.http(429)` now surface as red, explicit error messages instead of silently inserting the raw transcript. Network / timeout errors still fall back to the raw transcript + error badge (no data loss).
- **`PolishingService` timeout** raised from 12 s to 15 s to align with `LLMClient`'s URL request timeout. Previously the polisher would race the network call and discard a successful response that arrived in the 12–15 s window.
- **DEBUG `print` cleanup**: the four `🔥 [OSGKeyboardApp] …` instrumentation prints in `OSGKeyboardApp.init()` and root views are now wrapped in `#if DEBUG`.

### Added
- "Test connection" button in `APISettingsCard`: fires a single `polish("ping")` round-trip and surfaces success or the typed LLM error inline. Helps the user confirm the App Group + key are working without leaving the main App.
- 5 new unit tests in `OSGKeyboardTests`: App Group cross-process persistence, 401 / 429 / timeout / noAPIKey catch paths, and `mode = .off` short-circuit.

### Changed
- README + `README.zh.md`: replaced `<OWNER>` placeholder with `hkgood` and aligned capability statements to the implemented iOS 26 path.

### Known limitations
- The keyboard does not work in password fields (iOS limitation).
- Microphone requires "Allow Full Access" to be enabled in iOS Settings.
- Whisper.cpp / on-device LLM polish is intentionally out of scope for v1 (cloud-only).

## [0.1.0] - 2026-06-17

### Added
- First public pre-release.
