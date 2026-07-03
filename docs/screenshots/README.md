# App Store Screenshots

> ⚠️ **PLACEHOLDERS.** The 10 PNGs in this directory are
> automatically generated blanks produced by
> `scripts/generate_screenshot_placeholders.py` and must be
> **replaced with real Simulator screenshots** before App Store
> submission. They use the correct dimensions (1290×2796 for
> 6.7", 1179×2556 for 6.1") so the upload validator will accept
> them, but they contain no real UI.

## Required dimensions (2026)

| Size | Devices | Dimensions | Apple requirement |
|------|---------|-----------|---|
| 6.7" | iPhone 17 Pro Max, 17, 16 Pro Max, 16 Plus, 15 Pro Max, 15 Plus | 1290 × 2796 px | **Required** (3-10 images) |
| 6.1" | iPhone 17 Pro, 17, 16 Pro, 16, 15 Pro, 15, 14 Pro, 14 | 1179 × 2556 px | **Required** (3-10 images) |
| 5.5" | iPhone 8 Plus (legacy) | 1242 × 2208 px | Optional since 2024 |

iPad screenshots are not required because OSGKeyboard is iPhone-only
(`TARGETED_DEVICE_FAMILY = 1`).

## Layout

```
docs/screenshots/
├── 6.7/    ← 1290×2796 (iPhone 17 Pro Max / 17)
│   ├── 01-keyboard-default.png
│   ├── 02-flow-session.png
│   ├── 03-on-device-asr.png
│   ├── 04-llm-polish.png
│   └── 05-providers.png
└── 6.1/    ← 1179×2556 (iPhone 17 Pro / 17)
    ├── 01-keyboard-default.png
    ├── 02-flow-session.png
    ├── 03-on-device-asr.png
    ├── 04-llm-polish.png
    └── 05-providers.png
```

## How to capture real screenshots

1. Open `OSGKeyboard.xcodeproj` in Xcode 26+
2. Run on **iPhone 17 Pro** simulator (6.1" set) and **iPhone 17 Pro Max** simulator (6.7" set)
3. For each scene:
   ```bash
   # Take a screenshot of the simulator window
   xcrun simctl io booted screenshot ~/Desktop/shot.png
   ```
4. Process for App Store (Apple rejects frames containing the device bezel — full-screen content only):
   ```bash
   # The simulator screenshot already has a thin device frame.
   # Open in Preview, crop to full screen (⌘+K with ⌥ for precision),
   # export as PNG at 1290×2796 or 1179×2556.
   sips -z 2796 1290 shot.png --out final-6.7.png
   sips -z 2556 1179 shot.png --out final-6.1.png
   ```
5. Replace the placeholders with the real captures, keeping the
   same filenames so the App Store Connect → Version → Uploads UI
   auto-pairs by file.

## Scenes to capture

The 5 placeholders are intentional scene placeholders. Capture these
*exact* screens, in this order:

1. **Keyboard at rest** — the iOS keyboard, OSGKeyboard mode, no recording
2. **Flow session active** — keyboard with the green/orange recording ring,
   partial transcript visible in the host text field
3. **On-device ASR** — Settings view with the locale list, the on-device
   indicator (iPhone icon) visible next to ≥ 3 supported locales
4. **LLM polish** — Settings view with the API provider card, a sample
   "polish" transformation shown in the inline preview
5. **Providers** — API Settings card scrolled to show all 6 provider logos
