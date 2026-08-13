# App Store Connect — OSGKeyboard 1.7.5 (build 66)

> Current metadata baseline for the iOS/iPadOS App Store build. Version and build
> numbers come from `project.yml`. The repository also contains a separate
> macOS 15+ Developer ID target; it is not this App Store listing.

## App information

| Field | Value | Notes |
|---|---|---|
| App name | `OSGKeyboard` | ≤ 30 characters |
| Subtitle | `Voice input, everywhere` | ≤ 30 characters |
| Bundle ID | `com.osgkeyboard.ios` | iOS host target |
| Version / build | `1.7.5` / `66` | `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` |
| Minimum system | iOS/iPadOS 26 | iPhone and iPad |
| Primary locale | `en-US` | Simplified Chinese is also bundled |
| Primary category | Utilities | |
| Secondary category | Productivity | Optional |
| Age rating | 4+ | No objectionable content |

## URLs

| Field | Value |
|---|---|
| Support URL | `https://github.com/hkgood/OSGKeyboard/issues` |
| Marketing URL | `https://hkgood.github.io/OSGKeyboard/` |
| Privacy Policy URL | `https://hkgood.github.io/OSGKeyboard/privacy/` |
| EULA | Leave blank; use Apple's standard EULA |

## Pricing and availability

| Field | Value |
|---|---|
| Price | Free |
| In-App Purchases | Optional consumable tip `ByRockyACoffee`; unlocks no feature |
| Availability | All configured App Store territories |
| Pre-order | No |

## Description (≤ 4000 characters)

```text
OSGKeyboard is a voice and typing keyboard for iPhone and iPad. Speak in
any app and insert the transcript at the cursor, or switch to Chinese and
English typing without leaving the keyboard.

VOICE INPUT

• On-device by default. iOS 26 SpeechAnalyzer and DictationTranscriber
  transcribe locally.
• Optional cloud recognition. Audio leaves the device only after you
  enable a cloud ASR provider and configure its credentials.
• Optional AI polish and translation. Add your own provider API key;
  without a key, recognized text can still be inserted.
• AI keyboard mode. Ask a spoken question, review the generated answer,
  then explicitly insert or send it.
• Edit the last verified OSGKeyboard insertion by voice before replacing
  or appending the result.

TYPING

• Chinese full pinyin, Microsoft double pinyin, and Sogou double pinyin,
  with optional fuzzy-pinyin pairs.
• English autocomplete, autocorrect, and next-word prediction from
  offline resources.
• Personal dictionary terms can participate in Chinese candidates,
  English suggestions, ASR correction, and polish protection.
• iPhone and iPad layouts, including iPad globe and editing controls.
• Optional clipboard history is off by default and keeps up to 15 text
  items from this device or Universal Clipboard in this device's App Group.
  Turning it off keeps existing history; clearing is a separate confirmed action.

PRIVACY

• No advertising, analytics, or tracking SDKs.
• Local recognition does not upload audio.
• Cloud ASR and LLM requests go directly to the provider you configure.
• Provider keys are stored in Keychain.
• Clipboard history stays device-local, does not iCloud-sync, and is not
  sent to AI automatically. Text you insert may later be included when you
  actively invoke polish with your configured provider.
• Core use requires no OSGKeyboard account.

OSGKeyboard's own code is source available for audit and personal,
non-commercial local use. It is not MIT-licensed or open source; see the
repository LICENSE for redistribution and commercial-use restrictions.

Requires iOS or iPadOS 26 or later.

https://github.com/hkgood/OSGKeyboard
```

## Promotional text (≤ 170 characters)

```text
Voice input anywhere, with on-device recognition by default. Add your own AI key for polish, translation, and AI answers. Also types Chinese and English.
```

## Keywords (≤ 100 characters)

```text
keyboard,voice,dictation,speech,transcribe,AI,pinyin,Chinese,English,polish,typing,productivity
```

## What's new in 1.7.5

```text
NEW
• Optional clipboard history (latest 15 plain-text items) with a top-bar
  panel and suggestion strip; AI idle hints can use a fresh copy for ~30s.
• AI mode empty state rotates one-line suggestions; tap sends the card
  prompt without using the mic.
• Spoken clipboard requests in AI mode attach stored clipboard text when
  you name the clipboard out loud.
• Settings → AI Agent adds Response length (Short / Medium / Detailed).
• AI answers stream into the keyboard as the model writes.

CHANGED
• History and Personal dictionary move from the tab bar onto Home preview
  cards; engine status scrolls with the page.
• Translation control sits beside the mic (mirrored with Undo); the former
  top-bar slot is the Clipboard button.
• Undo covers clipboard pastes as well as dictation, AI answers, and edits.
```

## App Review information

| Field | Value |
|---|---|
| Sign-in required | No |
| Demo account | Not applicable |
| Contact info | Maintainer's Apple Developer account details |

### Notes to App Review

```text
OSGKeyboard is a custom keyboard for iOS/iPadOS 26.

1. Add the keyboard:
   Settings → General → Keyboard → Keyboards → Add New Keyboard →
   OSGKeyboard.
2. Enable Full Access. It is required for App Group communication between
   the keyboard and host app and for optional provider network requests.
3. Complete onboarding in the OSGKeyboard host app.
4. In any editable field, switch to OSGKeyboard and tap the microphone.
   The default local engine uses on-device Apple speech recognition.
5. AI polish and AI mode require a user-owned provider key in Settings.
   Without a key, local dictation still inserts recognized text.
6. Optional tip product `ByRockyACoffee` is consumable and unlocks no
   feature.
7. Clipboard history is off by default. To test it, open Settings →
   Clipboard, enable History, copy text on this device or through Universal
   Clipboard, then return to the keyboard. Secure fields hide the clipboard
   entry point. Turning History off preserves saved items; use the separate
   confirmed clear action to delete them.

Privacy policy:
https://hkgood.github.io/OSGKeyboard/privacy/

Source and license:
https://github.com/hkgood/OSGKeyboard
```

## App Privacy answers

Use conservative disclosures that cover optional cloud recognition, cloud
polish/translation, and AI mode even though local recognition is the default.

### User Content → Audio Data

- Collected: Yes
- Purpose: App Functionality
- Linked to the user: Yes
- Used for tracking: No

Audio is sent off-device only when the user enables cloud recognition. The
configured provider may associate requests with the user's provider
credential.

### User Content → Other User Content

- Collected: Yes
- Purpose: App Functionality
- Linked to the user: Yes
- Used for tracking: No

This covers transcripts, polish/translation text, AI questions, optional
provider search requests, dictionary terms included in provider prompts, and
clipboard text only after the user inserts it and actively invokes polish.
Device-local clipboard history by itself is not collected by the developer.

### Do not select

- Advertising, marketing, analytics, product personalization, or tracking
- Contact information, location, contacts, photos, browsing/search history
- Usage data or diagnostics stored only locally or in the user's private iCloud

## Encryption

`Info.plist` declares `ITSAppUsesNonExemptEncryption = false`. Network calls use
standard HTTPS. Re-evaluate this answer if non-exempt cryptography is added.

## Submission checklist

- [ ] Confirm `project.yml` still reads version 1.7.5 / build 66
- [ ] Open the existing Xcode project (do not regenerate unless needed)
- [ ] Run the release build and test suites on macOS with Xcode 26
- [ ] Replace screenshots with captures from the submitted build
- [ ] Verify the privacy answers against the submitted provider features
- [ ] Confirm the tip product remains optional and unlocks no feature
- [ ] Upload, select build 66, add review notes, and submit
