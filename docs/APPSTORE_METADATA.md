# App Store Connect — OSGKeyboard v0.1.2

> Use this document as a single source of truth for App Store Connect
> version metadata. All values are Apple-compliant (character limits
> respected, no marketing claims that would trigger Guideline 4.0).

---

## App Information

| Field | Value | Notes |
|---|---|---|
| **App name** | `OSGKeyboard` | CFBundleDisplayName. ≤ 30 chars. |
| **Subtitle** | `Voice input, everywhere` | ≤ 30 chars. |
| **Bundle ID** | `com.osgkeyboard.ios` | project.yml `bundleIdPrefix` + target name. |
| **SKU** | `OSGKB-001` | Internal; not user-visible. |
| **Primary locale** | `en-US` |  |
| **Category (primary)** | `Utilities` | LSApplicationCategoryType. |
| **Category (secondary)** | `Productivity` | Optional, helps discovery. |
| **Content rights** | `No third-party content` | Default. |
| **Age rating** | `4+` | No objectionable content. |

---

## URLs (required)

| Field | Value |
|---|---|
| **Support URL** | `https://github.com/hkgood/OSGKeyboard/issues` |
| **Marketing URL** | `https://github.com/hkgood/OSGKeyboard` |
| **Privacy Policy URL** | `https://hkgood.github.io/OSGKeyboard/privacy/` |
| **EULA** | *Leave blank* — use Apple's standard EULA |

---

## Pricing & Availability

| Field | Value |
|---|---|
| **Price** | Free (0 USD) |
| **In-App Purchases** | Optional voluntary tip — Consumable `ByRockyACoffee` (¥28 China tier; no feature unlock) |
| **Availability** | All App Store territories (default) |
| **Pre-order** | No |
| **Volume purchase** | No |

---

## Description (≤ 4000 chars)

```
OSGKeyboard is a free, open-source custom keyboard for iOS 26 that turns
your voice into clean, AI-polished text — in any app.

Hold the mic key, speak naturally, release. By default the keyboard
transcribes your voice entirely on-device (Apple's iOS 26
SpeechAnalyzer + DictationTranscriber), and only the final text is
sent to the AI you choose to polish it — your audio never leaves your
device unless you explicitly opt into the cloud ASR engine, which
uploads recordings to the provider you configure.

WHY OSGKEYBOARD

• Works everywhere — Messages, Notes, Mail, Slack, ChatGPT, Claude,
  Cursor, browsers, terminal apps. Anywhere you can type, OSGKeyboard
  types for you.
• Push-to-talk, the way voice should work. No more "Hey Siri" mode that
  listens to the whole room.
• On-device speech recognition by default. Powered by Apple's iOS 26
  speech pipeline — no audio upload unless you explicitly enable the
  optional cloud ASR engine (confirmation required).
• Bring-your-own AI. Connect any OpenAI-compatible endpoint (OpenAI,
  DeepSeek, Qwen DashScope, Moonshot, Zhipu, your own self-hosted
  server). Your API key stays in the iOS Keychain.
• Three polish modes:
    – Off: raw transcript.
    – Transcribe: just the cleaned-up text.
    – Polish: punctuation, structure, and grammar via your chosen LLM.
• Continuous flow. One session, many utterances — no need to re-open
  the host app between thoughts.
• Zero dependencies. No trackers, no analytics, no crash reporters.
  The whole project is ~8,700 lines of Swift you can audit in an
  afternoon.
• Privacy first. PrivacyInfo.xcprivacy declares exactly what the app
  touches (voice audio + transcripts, on-device by default, never
  linked or tracked); we don't run a server.

OPTIONAL SUPPORT

OSGKeyboard is completely free — every feature is available without
payment. If you'd like to support development, Settings includes an
optional in-app tip (Consumable). It does not unlock anything extra.

BUILT FOR

• iOS 26 and later, iPhone and iPad.
• Anyone who types more than 100 words a day on their phone.
• Developers, writers, students, and translators who want voice input
  that respects their privacy.

OPEN SOURCE

OSGKeyboard is MIT-licensed and developed in the open. Issues, pull
requests, and translations are welcome on GitHub.

https://github.com/hkgood/OSGKeyboard
```

---

## Promotional Text (≤ 170 chars, editable without new build)

```
Voice input, everywhere. Hold the mic, speak, release — AI-polished
text lands at your cursor. On-device speech, your own API key, zero
trackers. iOS 26+, free & open-source.
```

> Apple allows you to change the Promotional Text at any time without
> submitting a new build. Use it for launch-day announcements.

---

## Keywords (≤ 100 chars, comma-separated)

```
keyboard,voice,dictation,speech,transcribe,AI,polish,whisper,gpt,openai,productivity,accessibility
```

> 97 chars. Apple matches keywords against search terms; avoid the
> app name (already indexed) and competitor names.

---

## Release Notes (for v0.1.2, ≤ 4000 chars)

```
Welcome to OSGKeyboard v0.1.2 — our App Store debut!

This release focuses on review-driven polish for the iOS 26 launch:

NEW
• Dynamic ASR locale picker — Settings now lists every locale Apple's
  speech framework supports, with an on-device badge so you know which
  ones keep your audio on your phone.
• Apple-on-device flow polish — the continuous-capture session survives
  app switching and can run for up to an hour in the foreground.
• Per-locale on-device indicator — choose Chinese (Simplified) and
  you'll see the iPhone icon next to it, confirming audio never leaves
  your device.

FIXED
• Light/dark mode is now consistent — cards and buttons follow the
  active theme everywhere, including the in-app keyboard preview.
• iPhone-only lock — we removed iPad multitasking support; the app
  declares iPhone as the only target family. This fixed TestFlight
  error 90474 and the previously-misleading "supports iPad" badge.
• Keyboard preview cycling — tapping the disc now correctly cycles
  through idle → recording → processing → idle, with sample
  transcripts in the recording state.
• Embedded keyboard strings — Chinese and English keyboard strings
  are now properly bundled into the extension binary, so language
  switching works the moment you install the keyboard.
• Actool crash on iOS 26 — the legacy Icon Composer icon was removed
  to stop App Store Connect rejecting the build.

CHANGED
• The keyboard's top divider line is gone — the subtle highlight
  gradient is retained for visual structure without the hard separator.
• README is consistent with the implemented capability set (iOS 26
  on-device SpeechAnalyzer + DictationTranscriber only).

KNOWN ISSUES
• Continuous mode requires Full Access (Apple's policy, not ours).
  The onboarding flow walks you through enabling it.
• Some iCloud-synced keyboards can take a few seconds to appear in
  the Add New Keyboard list. This is iOS 26 behavior.

We'd love to hear from you — open an issue on GitHub, or rate this
version to help others find it.
```

---

## What's New in This Version

*(Same as Release Notes, but shorter; the What's New field is also
capped at 4000 chars. Apple displays it in the Updates tab.)*

```
Welcome to v0.1.2 — our App Store debut!

NEW: Dynamic ASR locale picker with on-device indicator. Continuous
flow sessions survive app switching for up to an hour. Polish modes:
off / transcribe / polish.

FIXED: Light/dark mode is now consistent across the keyboard preview.
TestFlight error 90474 (iPhone-only) is resolved. Keyboard preview
disc correctly cycles idle → recording → processing. Keyboard
strings are properly embedded in the extension bundle for instant
language switching.

CHANGED: The hard divider line on the keyboard is gone; the subtle
gradient highlight remains.

We'd love your feedback — open an issue on GitHub or rate this app.
```

---

## App Privacy (App Store Connect "Privacy" section)

Choose **"Data Not Collected"** in the first question.

The OSGKeyboard app and keyboard extension collect **no data** from
you. All processing happens on-device or through the LLM endpoint you
explicitly configure. The app does not embed any analytics, crash
report, or tracking SDK.

| Question | Answer |
|---|---|
| Data collected from this app? | **No** |
| Data used to track you? | **No** |
| Data linked to your identity? | **No** |

The `PrivacyInfo.xcprivacy` files in both `OSGKeyboard/` and
`OSGKeyboardExt/` declare `NSPrivacyTracking: false` and
`NSPrivacyCollectedDataTypes: []` to match.

---

## Encryption (annual survey)

`Info.plist` declares `ITSAppUsesNonExemptEncryption = false`. The
annual survey will be auto-skipped on upload. If prompted manually:

* Does your app use encryption? **No** (the LLM call uses HTTPS, which
  Apple classifies as "standard internet protocols" and is exempt
  under category 5 part 2 note 4 of the EAR).
* Is your app exempt under Category 5 Part 2? **Yes** (HTTPS only).

---

## App Review information

When the build is uploaded and you click "Add for Review", fill in:

| Field | Value |
|---|---|
| **Sign-in required** | No (no account) |
| **Demo account** | n/a |
| **Contact info** | (your Apple Developer account email) |
| **Phone** | (your phone; only Apple sees it) |
| **Notes to reviewer** | (see below) |

### Notes to App Review

```
OSGKeyboard is a free, open-source custom keyboard. To test it end
to end, please:

1. Install the keyboard:
   Settings → General → Keyboard → Keyboards → Add New Keyboard →
   under "Third-Party Keyboards" choose "OSGKeyboard".
2. Enable Full Access for OSGKeyboard (onboarding in the app walks
   through this, but you can also tap it in the keyboard settings).
   Full Access is required for the continuous-capture flow session
   (network access for the LLM polish step + shared App Group
   container with the main app). The mic is captured on-device; the
   network call only sends the final text transcript to the LLM
   endpoint configured in Settings.
3. In any app, switch to OSGKeyboard (globe key), then hold the
   purple mic key, speak, and release.
4. For the LLM polish demo: open OSGKeyboard's main app, Settings,
   Provider. Enter any OpenAI-compatible key (OpenAI, DeepSeek,
   Qwen, Moonshot, Zhipu, or a self-hosted URL). The default
   provider "Custom" works with a local mock server if you have
   one running.
5. The privacy policy is at
   https://hkgood.github.io/OSGKeyboard/privacy/

6. Optional tip (Consumable IAP ByRockyACoffee): open
   Settings → "Support the Developer". All features remain free before
   and after purchase; the tip does not unlock anything. Consumable
   tips cannot be restored (stated in UI).

Source code: https://github.com/hkgood/OSGKeyboard
```

---

## Submission checklist

- [ ] All 10 screenshots replaced with real Simulator captures
      (5 × 1290×2796 + 5 × 1179×2556)
- [ ] Archive in Xcode → Product → Archive → Distribute App → App
      Store Connect → Upload
- [ ] Select the new build under "Builds" in the version
- [ ] Fill in metadata from this document
- [ ] Privacy: "Data Not Collected"
- [ ] Encryption: skip (auto-skipped via Info.plist key)
- [ ] Add for review
- [ ] Submit
