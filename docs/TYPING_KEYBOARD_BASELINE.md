# Typing Keyboard Baseline (Phase 0)

Frozen reference for NanoMouse × OSGKeyboard fusion.

## NanoMouse reference

| Field | Value |
|-------|--------|
| Repo | https://github.com/xjwhnxjwhn/nanomouse |
| Frozen commit | `a6177d898a01662ce551b43a01cf82a9f84ca54c` (2026-07-29 tip at clone) |
| Local clone (gitignored) | `.refs/nanomouse/` |

## KeyboardKit / key shell

NanoMouse does **not** SPM-pin upstream KeyboardKit Pro. It vendors an MIT KeyboardKit tree inside:

`ios/Packages/HamsterKeyboardKit/Sources/KeyboardKit/` (see that folder’s `LICENSE`).

OSG ships a **lean SwiftUI key shell** in-repo (`OSGKeyboardExt/Typing/`)
behind `TypingLayoutProviding`; KeyboardKit is not linked.

**KeyboardKit Pro is not used.**

## Chinese schema / lexicon

| Choice | Detail |
|--------|--------|
| Product intent | Full pinyin + Microsoft/Sogou double pinyin + opt-in fuzzy pairs |
| Engine | librime 1.17.0 via static XCFramework (BSD-3-Clause) |
| Binary package | `ghostflyby/librime-xcframework` `1.17.0-pack.1`, checksum `0f0fc13b…1164` |
| Baseline | rime-pinyin-simp (Apache-2.0) |
| Modern words | Jieba frequencies + phrase-pinyin-data + pinyin-data (MIT) |
| Generated lexicon | `Resources/Typing/Rime/osg_pinyin.dict.yaml` (~365K entries) |
| User learning | librime userdb in App Group |
| Explicitly excluded | rime-ice / rime-double-pinyin (GPL), Luna / Essay (LGPL) |

The dictionary is rebuilt deterministically by
`Scripts/typing/build_rime_dictionary.py`; `manifest.json` pins every source
commit and SHA-256.

## Memory / height budget

| Mode | Target height | Memory notes |
|------|---------------|--------------|
| Voice | 281 pt (`KeyboardRootView.totalHeight`) | Matches typing height; no typing engine loaded |
| Typing | 281 pt (`TypingRootView.totalHeight`) | Host-prebuilt Rime data; extension opens one session |
| RSS goal | Typing peak &lt; 50 MB | Session closes on voice switch / memory warning |

## Success criteria (Phase 1)

- Top-right tab switches voice ↔ typing; recording/processing locks voice.
- English QWERTY + 123 / basic symbols.
- Full pinyin and Microsoft/Sogou double pinyin produce phrase candidates.
- Fuzzy pairs default off and are enabled individually in Settings.
- No GPL/LGPL input data in the app; NOTICE lists exact source licenses.
