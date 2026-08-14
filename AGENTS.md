# AGENTS.md

## License boundary

OSGKeyboard is **source available, not open source**. `LICENSE` permits personal,
non-commercial local use and forbids unauthorized redistribution or public derivative
versions. Do not describe the project as MIT-licensed, open source, or freely forkable.

## Versioning and releases

OSGKeyboard uses **Conventional Commits** as the single source of truth for version bumps
and `CHANGELOG.md` entries. Agents must follow this section whenever cutting a release or
writing commit messages that will ship to users.

### Version format

The current source-of-truth version is **1.8.0 (build 72)**. Releases use stable SemVer:

| Field | File | Rule |
|-------|------|------|
| Marketing version | `project.yml` → `MARKETING_VERSION` | `MAJOR.MINOR.PATCH` (SemVer) |
| Build number | `project.yml` → `CURRENT_PROJECT_VERSION` | Monotonic integer; **+1 on every release cut**, never decrease |

**Bump rules** (evaluate all commits since the last tagged/released version; take the **highest** bump):

| Commit prefix | Version bump | Example |
|---------------|--------------|---------|
| `feat:` | **MINOR** + reset PATCH → `0` | `1.7.0` → `1.8.0` |
| `fix:`, `perf:` (user-visible) | **PATCH** | `1.7.0` → `1.7.1` |
| `feat!:` or footer `BREAKING CHANGE:` | **MAJOR** | `1.7.0` → `2.0.0` |
| `refactor:`, `style:`, `docs:`, `test:`, `chore:`, `ci:` | **no bump by itself** | group with user-facing commits or skip release |

Pragmatic overrides (experienced-maintainer judgment, still objective):

- A release that is **only** internal/tooling (`chore`, `ci`, lexicon scripts with no app wiring) → **do not cut** a user-facing version; keep `[Unreleased]` in the changelog.
- A release that mixes `feat` + `fix` → bump **MINOR** (the `feat` wins).
- Security fixes that change behavior (`fix(security):`) → **PATCH** minimum; bump **MINOR** if users must change setup (e.g. new local key file).
- Whitespace-only or comment-only diffs → no release entry.

### Conventional Commit format

```
<type>(<optional scope>): <imperative summary>

[optional body]

[optional footer: BREAKING CHANGE: ...]
```

Allowed types: `feat`, `fix`, `perf`, `refactor`, `style`, `docs`, `test`, `chore`, `ci`.

Examples:

```
feat(keyboard): add cursor drag pad for precise caret movement
fix(home): use View-backed gradient on stats card
chore(lexicon): add offline SFCustomLanguageModelData export scripts
```

### Changelog (`CHANGELOG.md`)

- Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
- **Bilingual**: every bullet is **English first**, then ` / `, then **简体中文**.
- Sections per release: `Added`, `Changed`, `Deprecated`, `Removed`, `Fixed`, `Security`.
- Workflow:
  1. During development, add bullets under `## [Unreleased]` (bilingual).
  2. On release cut, rename `[Unreleased]` → `[X.Y.Z] - YYYY-MM-DD`, insert a fresh empty `[Unreleased]` above it.
  3. Derive section headings and bullets from Conventional Commits in the release range.

**Bullet template:**

```markdown
### Added
- **Short title**: English sentence. / **简短标题**：中文句子。
```

**Example entry:**

```markdown
## [1.8.0] - 2026-09-01

### Added
- **Cursor navigation**: drag pad on the keyboard for precise caret movement. / **光标导航**：键盘拖动手势区，精确移动光标。

### Fixed
- **API key handling**: keep user-owned provider keys in Keychain. / **API 密钥**：将用户自备的服务商密钥保存在 Keychain。
```

### Release checklist (agent)

When the user asks to release or bump version:

1. `git log` from last release tag/commit → classify commits → pick bump level.
2. Update `CHANGELOG.md` (`[Unreleased]` → `[X.Y.Z] - date`, bilingual bullets).
3. Update `project.yml`:
   - `MARKETING_VERSION` → new SemVer version
   - `CURRENT_PROJECT_VERSION` → previous build **+ 1**
4. Commit: `chore(release): bump version to X.Y.Z (build N)` — or include in the release PR.
5. Do **not** bump version for work that stays on a feature branch until it merges to `main`.

### Single source of truth

| What | Where |
|------|--------|
| Version numbers | `project.yml` (`MARKETING_VERSION`, `CURRENT_PROJECT_VERSION`) |
| Human-readable history | `CHANGELOG.md` |
| Machine-readable history | `git log` with Conventional Commit prefixes |

`Info.plist` files reference `$(MARKETING_VERSION)` / `$(CURRENT_PROJECT_VERSION)` — do not hardcode versions in plists.

---

## Cursor Cloud specific instructions

### Platform reality: this is an Apple-platform project on a Linux VM

OSGKeyboard contains a native **iOS/iPadOS 26+** app and keyboard extension plus a
native **macOS 15+** menu-bar app (Swift 6 / SwiftUI). The iOS host links
`OSGKeyboardShared` and the host-only `OSGKeyboardHostSupport`; the Mac target reuses
shared/host-support sources and links MLX Audio for Qwen3 streaming ASR. The Cursor Cloud VM
is **Linux x86_64**. Apple-platform development is macOS-only, so the following **cannot run
in this environment**:

- **Build** — needs `xcodebuild` + the iOS SDK (Xcode, macOS only).
- **Run** — needs the iOS Simulator or a physical iPhone (macOS only).
- **Tests** — iOS/extension tests require an iOS Simulator; `OSGKeyboardMacTests` requires macOS.

Nearly every source file imports iOS-only frameworks (`SwiftUI`, `UIKit`, `AVFoundation`,
`Speech`, `Combine`), so there is no meaningful subset that compiles with Swift-for-Linux.
Do **not** attempt to build/run/test on the Linux VM — escalate to a macOS host with Xcode 26+
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
