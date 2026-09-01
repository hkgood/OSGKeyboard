# App Store Connect — OSGKeyboard 2.0.3 (build 94)

> Current metadata baseline for the iOS/iPadOS App Store build. Version and build
> numbers come from `project.yml`. The repository also contains a separate
> macOS 15+ Developer ID target; it is not this App Store listing.

## App information

| Field | Value | Notes |
|---|---|---|
| App name | `OSGKeyboard` | ≤ 30 characters |
| Subtitle | `Voice input, everywhere` | ≤ 30 characters |
| Bundle ID | `com.osgkeyboard.ios` | iOS host target |
| Version / build | `2.0.3` / `94` | `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` |
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
| In-App Purchases | Optional consumables: managed-credit packs `500tks`, `1500tks`, `3000tks` |
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
• Optional cloud recognition. Use your own provider credentials, or
  sign in with Apple and choose managed credits.
• Optional AI polish and translation. Use your own provider API key or
  managed credits; without either, recognized text can still be inserted.
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

• Limited first-party product analytics; no third-party analytics,
  advertising, tracking SDKs, ATT, or IDFA.
• Product analytics never includes keyboard input, audio, transcripts,
  prompts, model output, credentials, or personal identifiers. It can be
  disabled in Settings, which deletes queued events.
• Local recognition does not upload audio.
• User-configured cloud requests go directly to that provider. Managed-credit
  requests go through OSGKeyboard's managed gateway to the managed provider.
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
Voice input anywhere, with on-device recognition by default. Use your own AI key or optional managed credits for cloud speech, polish, translation, and AI answers.
```

## Keywords (≤ 100 characters)

```text
keyboard,voice,dictation,speech,transcribe,AI,pinyin,Chinese,English,polish,typing,productivity
```

## What's new in 2.0.3

```text
NEW
• Home can now suggest repeated rare English terms alongside Chinese terms
  for explicit review before adding them to the Personal Dictionary.

CHANGED
• Cards, settings typography, native selection menus, account rows, and
  primary-to-detail navigation transitions now follow one visual system.

FIXED
• Apple account restoration now retries transient secure-session failures and
  keeps sign-in loading feedback consistent.
• English and Chinese candidates now recover reliably after switching apps
  without carrying state from the previous input field.
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
5. Local dictation and user-configured providers require no OSGKeyboard
   account. The Account tab offers optional Sign in with Apple.
6. After signing in, Settings → AI Service → Use Credits enables the managed
   cloud path. The consumable products are `500tks`, `1500tks`, and `3000tks`.
   Purchased credits are verified by the account service before StoreKit
   transactions are finished.
7. AI polish and AI mode can use either managed credits or a user-owned
   provider key. Without either, local dictation still inserts recognized text.
8. Clipboard history is off by default. To test it, open Settings →
   Clipboard, enable History, copy text on this device or through Universal
   Clipboard, then return to the keyboard. Secure fields hide the clipboard
   entry point. Turning History off preserves saved items; use the separate
   confirmed clear action to delete them.
9. First-party Product Analytics is enabled by default under Settings →
   About → Privacy. Turning it off deletes queued events. It does not collect
   keyboard input, audio, transcripts, prompts, model output, or credentials.

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
configured provider may associate requests with the user's credential. In
managed-credit mode, audio is linked to the OSGKeyboard account for service
authorization and credit accounting.

### User Content → Other User Content

- Collected: Yes
- Purpose: App Functionality
- Linked to the user: Yes
- Used for tracking: No

This covers transcripts and nearby cursor context used for polish/translation,
AI questions and skill prompts, optional provider search requests, dictionary
terms included in provider prompts, and clipboard text only after the user
actively invokes a clipboard skill, names the clipboard in AI mode, or inserts
it and requests polish. Skill results may also be handed on-device to an Apple
Shortcut, while navigation addresses may be opened in the selected map app.
Device-local clipboard history and typing-learning data by themselves are not
collected by the developer.

### Contact Info → Name

- Collected: Yes
- Purpose: App Functionality
- Linked to the user: Yes
- Used for tracking: No

The display name supplied by Sign in with Apple is optional and is used only
for the optional OSGKeyboard account profile.

### Purchases → Purchase History

- Collected: Yes
- Purpose: App Functionality
- Linked to the user: Yes
- Used for tracking: No

StoreKit transaction identifiers, product identifiers, and granted-credit
results are processed to verify consumable managed-credit purchases, prevent
replay, and maintain the account credit ledger.

### Identifiers → User ID

- Collected: Yes
- Purpose: App Functionality
- Linked to the user: Yes
- Used for tracking: No

This covers the pseudonymous OSGKeyboard account identifier and scoped
managed-service grant identifiers. Core use remains available without an
OSGKeyboard account.

### Identifiers → Device ID

- Collected: Yes
- Purpose: Analytics
- Linked to the user: Yes
- Used for tracking: No

This is an app-scoped random installation identifier. It rotates when analytics
is re-enabled, after account deletion, or when a different account signs in. It
is not IDFA and is not used across apps.

### Usage Data → Product Interaction

- Collected: Yes
- Purpose: Analytics
- Linked to the user: Yes
- Used for tracking: No

This covers fixed event names for app and keyboard sessions, purchase-page
interactions, and invitation actions. It contains no free-form properties.

### Usage Data → Other Usage Data

- Collected: Yes
- Purpose: Analytics
- Linked to the user: Yes
- Used for tracking: No

This covers fixed AI feature categories, execution modes, outcome categories,
and coarse duration buckets. It does not include prompts, transcripts, model
output, audio, or keyboard content.

### Do not select

- Advertising, marketing, product personalization, or tracking
- Email address, phone number, physical address, location, contacts, photos,
  browsing history, or search history
- Usage data or diagnostics stored only locally or in the user's private iCloud

## Encryption

`Info.plist` declares `ITSAppUsesNonExemptEncryption = false`. Network calls use
standard HTTPS. Re-evaluate this answer if non-exempt cryptography is added.

## Screenshots

OSGKeyboard ships for **iPhone and iPad** (`TARGETED_DEVICE_FAMILY: "1,2"`), so
both device families need screenshots. Apple scales one uploaded set down to
smaller devices, so only the largest size per family is required.

| Set | Capture device | Pixel size | Required |
|---|---|---|---|
| iPhone 6.9" | iPhone 17 Pro Max | 1320 × 2868 (or 1290 × 2796) | Yes |
| iPad 13" | iPad Pro 13" (M4) | 2064 × 2752 (or 2048 × 2732) | Yes, because the app supports iPad |

Apple adjusts accepted sizes over time — confirm the current list in the
App Store Connect media manager before capturing.

### Capture procedure

1. Run the **submitted build** on the simulators above (Xcode 26).
2. Capture with `xcrun simctl io booted screenshot ~/Desktop/shot.png`.
   Simulator captures contain no device bezel, which Apple requires.
3. Verify pixel dimensions; do not upscale a smaller capture.
4. Upload per device family in App Store Connect. Screenshots are **not**
   stored in this repository; `docs/assets/screenshots/` holds the smaller,
   web-optimized images used by the GitHub Pages site only.

### Scenes, in order

1. **Keyboard at rest** — OSGKeyboard in a text field, not recording
2. **Dictation in progress** — recording state with a partial transcript visible
3. **Chinese / English typing** — candidate bar with pinyin candidates or the
   three-slot English QuickType bar
4. **AI assistant** — a streamed answer inside the keyboard before insertion
5. **Clipboard skills** — recommended actions after a copy
6. **Home** — monthly usage calendar, metrics, and personal dictionary

## Submission checklist

- [ ] Confirm `project.yml` still reads version 2.0.3 / build 94
- [ ] Open the existing Xcode project (do not regenerate unless needed)
- [ ] Run the release build and test suites on macOS with Xcode 26
- [ ] Capture fresh iPhone 6.9" and iPad 13" screenshots from the submitted
      build (see Screenshots above)
- [ ] Verify the privacy answers against the submitted provider features
- [ ] In App Store Connect, add Device ID, Product Interaction, and Other
      Usage Data for Analytics; linked to the user, not used for tracking
- [ ] Confirm `500tks`, `1500tks`, and `3000tks` are approved, consumable,
      and mapped to the server credit catalog
- [ ] Upload, select build 94, add review notes, and submit
