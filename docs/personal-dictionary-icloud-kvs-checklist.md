# Personal Dictionary iCloud KVS — Manual Verification Checklist

Use this on **macOS with Xcode 16+** and at least two devices signed into the **same Apple ID** with iCloud Drive / iCloud enabled.

## Prerequisites

1. In Apple Developer Portal, enable **iCloud** → **Key-value storage** for `com.osgkeyboard.ios`.
2. Regenerate provisioning profiles after entitlements change.
3. Run `xcodegen generate` and install a fresh build on each device.

## Scenarios

| # | Steps | Expected |
|---|--------|----------|
| 1 | Device A: open Personal Dictionary, enable **Sync via iCloud**, add term `TestWordA` | Toggle stays on; term appears locally |
| 2 | Device B: open app → Personal Dictionary tab | `TestWordA` appears after pull (may take up to ~1 min) |
| 3 | Device B: add `TestWordB` | Device A eventually shows both terms |
| 4 | Both devices: edit same term offline, then go online | Newer edit wins; aliases union when terms match |
| 5 | Device A: delete a term | Term disappears on Device B after sync |
| 6 | Device A: disable iCloud sync | Local dictionary remains; Device B stops receiving new edits from A |
| 7 | Sign out of iCloud on one device | App keeps local dictionary; sync errors may surface in UI |
| 8 | Keyboard extension on Device A | Uses App Group cache immediately after main-app save — no iCloud wait |

## Notes

- KVS propagation is **eventual**; force-quit and reopen the app to speed up pulls.
- The keyboard extension never talks to iCloud directly; only the main app syncs.
- Payload limit is ~1 MB per key; very large dictionaries should show the “too large” error.
