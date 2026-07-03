# AGENTS.md

## Cursor Cloud specific instructions

### Platform reality: this is an iOS-only project on a Linux VM

OSGKeyboard is a native **iOS 18+** app (main app + custom keyboard extension + shared
framework, all Swift 6 / SwiftUI). The Cursor Cloud VM is **Linux x86_64**. iOS development
is fundamentally macOS-only, so the following **cannot run in this environment**:

- **Build** — needs `xcodebuild` + the iOS SDK (Xcode, macOS only).
- **Run** — needs the iOS Simulator or a physical iPhone (macOS only).
- **Tests** — `OSGKeyboardTests` / `OSGKeyboardExtTests` run via `xcodebuild test` against the
  iOS Simulator (macOS only).

Nearly every source file imports iOS-only frameworks (`SwiftUI`, `UIKit`, `AVFoundation`,
`Speech`, `Combine`), so there is no meaningful subset that compiles with Swift-for-Linux.
Do **not** attempt to build/run/test on the Linux VM — escalate to a macOS host with Xcode 16+
(see `README.md` / `CONTRIBUTING.md` for the `xcodegen generate` + `xcodebuild` flow).

### What *does* work on Linux: SwiftLint

`swiftlint` (the `swiftlint-static` Linux binary, installed to `/usr/local/bin` by the update
script) runs here because its rules are SwiftSyntax/source-based. Run it from the repo root:

```bash
swiftlint lint --quiet            # used by CI
swiftlint lint --quiet --strict   # used by CI; promotes warnings to errors
```

Caveats:
- On Linux, SourceKit is unavailable, so SourceKit-only rules are **skipped** (e.g. you will see
  `Skipping enabled rule 'statement_position' because it requires SourceKit`). Lint results can
  therefore differ slightly from a macOS run. Treat macOS/CI lint as the source of truth.
- The repo currently has **pre-existing** SwiftLint violations on `main`; a non-zero exit from
  `swiftlint lint` reflects code, not a broken environment.

### Project generation

The `.xcodeproj` is **gitignored**; `project.yml` (XcodeGen) is the source of truth. On macOS run
`xcodegen generate` before any `xcodebuild`. XcodeGen is macOS-oriented and is not installed on
the Linux VM.

### CI note

`.github/workflows/ci.yml` runs on `macos-14` and currently fails at the `xcode-select -s
/Applications/Xcode_16.0.app` step because that Xcode version is absent from GitHub's current
`macos-14` image — this is a CI runner-image issue, unrelated to the code or this Linux setup.
