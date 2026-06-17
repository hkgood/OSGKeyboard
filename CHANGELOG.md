# Changelog

All notable changes to OSGKeyboard will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Initial open-source release.
- Custom Keyboard Extension with push-to-talk UI.
- iOS 26 `SpeechAnalyzer` + `DictationTranscriber` on-device ASR.
- iOS 18 `SFSpeechRecognizer` fallback path (on-device only).
- OpenAI-compatible LLM client (BaseURL / API Key / Model / System Prompt user-editable).
- Built-in presets: OpenAI, DeepSeek, Qwen DashScope, Custom.
- Three-page onboarding (welcome → enable keyboard → API config).
- `ProviderConfig` persisted in App Group `group.com.osgkeyboard.ios`.
- 8-second LLM call timeout with graceful fallback to raw transcript.
- App Store privacy manifest (`PrivacyInfo.xcprivacy`) for both targets.
- SwiftLint config, XcodeGen project definition, GitHub Actions CI.
- Unit tests for `ProviderConfig` and `OpenAICompatibleClient`.

### Known limitations
- 2 failing tests stub state pollution was fixed in this release; regression coverage in place.
- The keyboard does not work in password fields (iOS limitation).
- Microphone requires "Allow Full Access" to be enabled in iOS Settings.
- Whisper.cpp / on-device LLM polish is intentionally out of scope for v1 (cloud-only).

## [0.1.0] - 2026-06-17

### Added
- First public pre-release.
