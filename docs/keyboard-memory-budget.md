# Keyboard memory budget — acceptance (OSGDiag)

Phase 0 / 2 memory work is validated on a **physical iPhone** with Console
filtering for `OSGDiag`. Unit tests and `xcodebuild` cover compile-time
wiring; jetsam behavior is device-only.

## Hybrid Flow (product default)

- Foreground host is **light by default**: orphan Live Activity cleanup only —
  **no** auto `startSession` / continuous capture on appear.
- Capture starts only on explicit Start / `osgkeyboard://startflow` / mic press.
- Idle background capture is stopped so a parked host does not jetsam the keyboard.
- **Do not** stack CLM + Rime + ASR in the same second after onboarding.
- ASR warmup runs on **first mic press** (`beginUtterance`), gated by
  `HostMemoryBudget` (~260 MB RSS). `hostHeavy` is set only while heavy work
  actually runs, then cleared. A sticky `hostHeavy` (host died mid-work)
  expires after `hostHeavyMaxAge` (~120 s) and is cleared on
  `clearFlowState` / host-launch reconciliation so typing 中文/EN is not
  permanently blocked.

## Console checklist

Filter Console by process separately: host `OSGKeyboard` vs extension
`com.osgkeyboard.ios.keyboard`. Host-only filter will never show `KVC.*`.

| Scenario | Expect |
|----------|--------|
| **Force-quit host**, open Notes, switch to OSG | First `dyld.constructor`, then `KVC.init` → `viewDidLoad` → `viewDidAppear` |
| Host foreground right after launch | `skip capture` + `postOnboardingWarmup scheduled … delay=45s` (no immediate Rime/CLM) |
| ~45 s later, host still active | Serial `rime.installIfNeeded` then `clm.prepare` |
| First mic press | `scheduleASRWarmup`; `hostHeavy` only while work runs |
| Switch to typing | Single `rime.prepare` / `englishPrepare` |

If neither `dyld.constructor` nor `KVC.init` appears after force-quitting the host,
the extension is dying in dyld (Shared≈9.4 MB + librime) — next lever is splitting
Rime out of Shared.

## RSS comparison (optional)

Record `OSGDiag` `rss=` tags for:

1. Cold voice surface only
2. Cold typing after prepare
3. Host foreground + extension

Target: typing peak below the old “voice + eager Librime construct” baseline.

## Structural split

- Extension links **OSGKeyboardShared** only (no Charts / StoreKit / Speech / HostSupport).
- Host embeds **OSGKeyboardHostSupport** (ASR, CLM, CloudASR, tip/charts UI).
- Heavy assets (`osg_pinyin.dict.yaml`, CLM bin, licenses, local-asr catalog)
  ship in the **host app** bundle; extension reads Rime from App Group after deploy.
