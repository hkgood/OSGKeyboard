# Contributing to OSGKeyboard

Thanks for your interest! OSGKeyboard is a Swift 6 app for iOS/iPadOS 26+ and macOS 15+. We welcome bug reports, feature ideas, and pull requests — please read this guide first.

## License

OSGKeyboard is source available, not open source. By contributing, you agree to the contribution terms in [`LICENSE`](LICENSE). The license permits personal, non-commercial local builds but does not permit unauthorized redistribution or public derivative versions.

## Code of Conduct

This project follows the [Contributor Covenant](https://www.contributor-covenant.org/version/2/1/code_of_conduct/). By participating you agree to its terms.

## Filing a bug

Open an issue using the **Bug report** template. Please include:

- OS version + device model (iPhone, iPad, or Apple-silicon Mac)
- Xcode version (run `xcodebuild -version`)
- Steps to reproduce
- Relevant logs (Console.app filtered to `OSGKeyboard`)

## Proposing a feature

Open an issue using the **Feature request** template. Briefly describe:

- What problem it solves
- Your proposed UX / API
- Any alternatives you considered

## Submitting a pull request

1. **Fork & branch.** Branch from `main` with a descriptive name (`feat/custom-provider`, `fix/asr-timeout`).
2. **Generate the project locally:**
   ```bash
   brew install xcodegen swiftlint
   ./Scripts/generate-xcodeproj.sh
   ```
   Building requires macOS with Xcode 26. `project.yml` is the project source of truth.
3. **Code style.** SwiftLint config lives in `.swiftlint.yml` — keep it green. We use Swift 6 strict concurrency, no `Sendable` shims where avoidable.
4. **Tests.** Add XCTest coverage under `OSGKeyboardTests/` (or Ext/Mac targets) for any non-trivial logic, and register the class in **exactly one** group in `Tests/suite-manifest.json`. See [`docs/TESTING.md`](docs/TESTING.md).
5. **Build & test before pushing:**
   ```bash
   ./Scripts/run-tests.sh validate
   ./Scripts/run-tests.sh pr          # default CI gate; or: all / api / keyboard / …
   ```
6. **Commit messages.** Short imperative summary (`fix: handle empty transcript`), longer body if needed.
7. **Open the PR** against `main`. The CI pipeline (`.github/workflows/ci.yml`) will lint + build + test automatically.

## Project structure

```
OSGKeyboard/            Main iOS/iPadOS app target and host resources
OSGKeyboardExt/         Custom Keyboard Extension target
OSGKeyboardShared/      Lightweight app/extension shared framework
OSGKeyboardHostSupport/ Host-only ASR, cloud, CLM, charts, and StoreKit
OSGKeyboardMac/         macOS menu-bar app; Qwen3 MLX local ASR
OSGKeyboardTests/       XCTest unit tests (host / shared)
OSGKeyboardExtTests/ Keyboard / typing XCTest
OSGKeyboardMacTests/ Mac XCTest
Tests/                  Suite manifest (grouped presets — see docs/TESTING.md)
project.yml             XcodeGen definition; version/build source of truth
.github/workflows/      CI
```

## Adding a new LLM provider

The simplest contribution: add a preset to `OSGKeyboardShared/Models/LLMProvider.swift`. No other code change is needed — `OpenAICompatibleClient` handles any OpenAI-compatible endpoint.

## Coding conventions

- Swift 6 strict concurrency
- `@MainActor` on any UI-touching type
- `async/await` everywhere; no completion-handler chains
- Public types use `PascalCase`, internal-only types can use `lowerCamelCase`
- File headers use the `// FileName.swift` → `// OSGKeyboard · <Target>` → blank-line → doc-comment style already in the repo

## Releasing

Maintainers cut releases from `main`. The marketing version and monotonic build number live in `project.yml`; `CHANGELOG.md` is updated as part of the release PR. Do not infer the current Mac binary version from the historical download URL in the README.
