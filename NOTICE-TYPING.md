# Third-party notices — Typing keyboard

The generated Chinese source manifest is
`OSGKeyboardShared/Resources/Typing/Rime/manifest.json`. Exact librime
binary dependency licenses are bundled beside `NOTICE.txt`.

## Distributed components (Chinese IME)

| Component | Pinned version / commit | License | Purpose |
|-----------|-------------------------|---------|---------|
| [librime-xcframework](https://github.com/ghostflyby/librime-xcframework) | `1.17.0-pack.1`, package `d578192…` | BSD-3-Clause + bundled dependency notices | Static iOS librime runtime |
| [rime/librime](https://github.com/rime/librime) | `1.17.0` | BSD-3-Clause | Chinese input-method engine |
| [rime-pinyin-simp](https://github.com/rime/rime-pinyin-simp) | `0c6861e…` | Apache-2.0 | Permissive baseline dictionary |
| [fxsjy/jieba](https://github.com/fxsjy/jieba) | `67fa2e3…` | MIT | Modern Simplified-Chinese word frequencies |
| [phrase-pinyin-data](https://github.com/mozillazg/phrase-pinyin-data) | `cee0ed6…` | MIT | Phrase pronunciations |
| [pinyin-data](https://github.com/mozillazg/pinyin-data) | `923b108…` | MIT | Character-pronunciation fallback |

`Scripts/typing/build_rime_dictionary.py` deterministically merges these
sources into `osg_pinyin.dict.yaml`; its manifest records every source URL,
commit, SHA-256 and output SHA-256.

## OSG-owned pieces

- SwiftUI QWERTY / candidate UI, `RimeEngineBridging`, and the English
  suggestion / autocorrect / next-word session layer.
- Objective-C++ C-API bridge for librime.
- Full-pinyin, Microsoft-double-pinyin and Sogou-double-pinyin schemas.
- Microsoft/Sogou mappings were independently encoded from public key-map
  specifications; GPL schema files were not copied.
- Eight opt-in fuzzy-pinyin rule groups.
- Offline English typing data under
  `OSGKeyboardShared/Resources/Typing/English/`:
  - `english_lexicon.tsv` — curated word list with synthetic relative
    frequency ranks for autocomplete / autocorrect
  - `english_bigrams.tsv` — light next-word candidates
  - Not derived from GPL/LGPL dictionaries; ranks are ordering weights,
    not a single third-party corpus dump

## Reference only

NanoMouse commit `a6177d898a01662ce551b43a01cf82a9f84ca54c`
(MIT) was used to understand iOS Rime lifecycle boundaries. Its KeyboardKit,
UI, data packages and application features are not linked into OSGKeyboard.

## Explicitly excluded

- rime-ice / 雾凇拼音 — GPL-3.0
- rime-double-pinyin schemas — GPL-3.0
- rime-luna-pinyin and rime-essay — LGPL-3.0
- KeyboardKit Pro — proprietary
