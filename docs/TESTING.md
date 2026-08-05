# Testing

OSGKeyboard keeps **one hermetic XCTest suite**, organized so you can run **all** or **a subset** without duplicating cases.

## Single source of truth

| File | Role |
|------|------|
| [`Tests/suite-manifest.json`](../Tests/suite-manifest.json) | Atomic groups + presets. Each `*Tests` class appears in **exactly one** group. |
| [`Scripts/resolve_test_suite.py`](../Scripts/resolve_test_suite.py) | Expand presets, validate membership vs on-disk files. |
| [`Scripts/run-tests.sh`](../Scripts/run-tests.sh) | Resolve → `xcodebuild test -only-testing:…` (iOS and/or Mac). |

Helpers such as `FakeUbiquitousKeyValueStore.swift` are not listed (they are not XCTest classes).

## Quick start (Mac + Xcode)

```bash
./Scripts/generate-xcodeproj.sh   # once / after project.yml changes
./Scripts/run-tests.sh list       # presets + groups
./Scripts/run-tests.sh validate   # every on-disk *Tests.swift is in the manifest once
./Scripts/run-tests.sh pr         # default CI / PR gate
```

### Presets

| Preset | Contains | When to use |
|--------|----------|-------------|
| `pr` | config, sync, polish, cloud_asr, local_asr, utterance, flow, keyboard | PR / default CI |
| `all` | `pr` + `host_misc` + `pipeline_perf` | Full iOS+Ext hermetic run before release |
| `api` | cloud_asr, polish | Online API contracts + polish/LLM stubs |
| `asr` | cloud_asr, local_asr, utterance | Transcription path |
| `polish` | polish | Polish only |
| `keyboard` | keyboard, **flow** | Keyboard + handoff/mic |
| `flow` | flow | Flow session only |
| `sync` | sync | iCloud sync only |
| `perf` | pipeline_perf | Hermetic voice→polish stage timings (stub ASR/LLM) |
| `mac` | mac | macOS host only (separate scheme) |

`live_api` is reserved for optional live-network smoke and is **empty / excluded** from `all` and `pr` by design.

### Atomic groups or mixes

```bash
./Scripts/run-tests.sh polish
./Scripts/run-tests.sh cloud_asr utterance
./Scripts/run-tests.sh perf
./Scripts/run-tests.sh api keyboard
DRY_RUN=1 ./Scripts/run-tests.sh all
```

### Environment

| Variable | Meaning |
|----------|---------|
| `DESTINATION` | iOS Simulator destination (default: `platform=iOS Simulator,name=iPhone 17`) |
| `MAC_DESTINATION` | macOS destination (default: `platform=macOS`) |
| `CONFIGURATION` | `Debug` (default) or `Release` |
| `DRY_RUN=1` | Print `xcodebuild` only |
| `SKIP_GENERATE=1` | Do not call `generate-xcodeproj.sh` even if the project is missing |

## CI

`.github/workflows/ci.yml` runs `./Scripts/run-tests.sh pr` (critical path, including `OSGKeyboardExtTests`).

## Adding a new test

1. Add the XCTest class under the correct target folder (`OSGKeyboardTests`, `OSGKeyboardExtTests`, or `OSGKeyboardMacTests`).
2. Register it in **exactly one** group in `Tests/suite-manifest.json`.
3. Run `./Scripts/run-tests.sh validate`.
4. Prefer extending an existing group; only add a new group when the domain is genuinely new.

## Layer note (avoid false “duplicates”)

- `ChunkedUtterancePipelineTests` (HostSupport pipeline orchestration) and `FinalChunkRecoveryTests` (Ext short/empty final recovery) cover **different layers** — both stay, both live in `utterance`.
- Cloud ASR **runtime** WebSocket clients and `live_api` smoke are future work inside `cloud_asr` / `live_api`, not a second parallel suite.
- Flow keyboard mic regressions (orange stuck / jetsam re-adopt / command seq) are covered by `FlowKeyboardPolicies` helpers in the `flow` group.
- Streaming provider event JSON / Volcengine frames are covered by `CloudASRStreamingEventParsingTests` in `cloud_asr`.
- Translation chip App Group poll clobber is covered by `KeyboardTranslationConfigProtectionTests` in `keyboard`.

## Pipeline performance (`perf` / `pipeline_perf`)

Hermetic **voice → chunk ASR → transcript guard → (optional batch fallback) → polish → App Group bridge deliver** timings live in `VoicePipelinePerformanceTests`.

- Synthetic PCM + stub ASR/LLM only — **no mic, no live network**.
- Each run attaches a stage report (`pcm_feed`, `chunk_asr`, `transcript_guard`, `batch_fallback?`, `polish`, `bridge_deliver`, `total_e2e`) to the xcresult.
- Run alone: `./Scripts/run-tests.sh perf`. Included in `all`, **not** in `pr` (keeps the PR gate free of timing-sensitive ceilings).

These measure harness/orchestration cost under stubs — not on-device SpeechAnalyzer or real LLM latency.

## Physical-device Flow audio gate

Bluetooth HFP and PiP route transitions cannot be validated by the simulator.
Before release, run [FLOW_BLUETOOTH_TESTING.md](FLOW_BLUETOOTH_TESTING.md) and
retain the filtered trace log with the release record.

## Manual / non-XCTest checklists

Some product surfaces still use manual docs (StoreKit, personal-dictionary iCloud, etc.). Those are complementary; they are not duplicated into XCTest.
