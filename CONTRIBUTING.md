# Contributing to OSGKeyboard

Thanks for your interest! OSGKeyboard is a small, opinionated iOS app. We welcome bug reports, feature ideas, and pull requests — please read this guide first.

## Code of Conduct

This project follows the [Contributor Covenant](https://www.contributor-covenant.org/version/2/1/code_of_conduct/). By participating you agree to its terms.

## Filing a bug

Open an issue using the **Bug report** template. Please include:

- iOS version + device model
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
   xcodegen generate          # or: ./Scripts/generate-xcodeproj.sh
   ```
3. **Code style.** SwiftLint config lives in `.swiftlint.yml` — keep it green. We use Swift 6 strict concurrency, no `Sendable` shims where avoidable.
4. **Tests.** Add XCTest coverage in `OSGKeyboardTests/` for any non-trivial logic.
5. **Build & test before pushing:**
   ```bash
   xcodebuild -project OSGKeyboard.xcodeproj \
     -scheme OSGKeyboard \
     -destination 'platform=iOS Simulator,name=iPhone 17' \
     test
   ```
6. **Commit messages.** Short imperative summary (`fix: handle empty transcript`), longer body if needed.
7. **Open the PR** against `main`. The CI pipeline (`.github/workflows/ci.yml`) will lint + build + test automatically.

## Project structure

```
OSGKeyboard/       Main iOS app target
OSGKeyboardExt/    Custom Keyboard Extension target
OSGKeyboardShared/ Framework shared by app + extension
OSGKeyboardTests/  XCTest unit tests
project.yml        XcodeGen project definition (source of truth)
.github/workflows/ CI
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

Maintainers cut releases from `main` via GitHub Releases. The release tag follows `vX.Y.Z`. CHANGELOG.md is updated as part of the release PR.
