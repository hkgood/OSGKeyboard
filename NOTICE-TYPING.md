# Third-party notices — OSGKeyboard

OSGKeyboard itself is source-available under the repository `LICENSE`; it is
not an open-source or MIT-licensed application. The notices below apply only
to the named third-party components or explicitly identified data subsets.

The generated Chinese source manifest is
`OSGKeyboard/Resources/Typing/Rime/manifest.json`. Exact librime
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
| [Google Material Icons](https://github.com/google/material-design-icons) | Bundled font snapshot | Apache-2.0 | iOS Settings and navigation iconography |

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
- Project-curated bilingual AI/technology speech phrases under
  `Scripts/lexicon/seeds/ai_tech_brands_seed.tsv`. This data subset and its
  generated CLM phrase list are MIT-licensed; that grant does not change the
  source-available license of the app.
- Offline English typing data under
  `OSGKeyboardShared/Resources/Typing/English/`:
  - `english_lexicon.bin` — mmap-friendly binary of the top 40k alphabetic
    unigrams (log-scaled ranks) plus truncated bigrams; this is what the
    keyboard extension loads
  - `english_lexicon.tsv` / `english_bigrams.tsv` — build inputs derived from
    Peter Norvig’s public-domain `count_1w.txt` / `count_2w.txt`
    (https://norvig.com/ngrams/; not GPL/LGPL dictionaries). Not copied into
    the app bundle.
  - Rebuild with `python3 Scripts/typing/build_english_lexicon.py`
    (add `--from-tsv` to compile the binary from existing TSV without network)

## macOS local speech stack

| Component | Pinned version | License | Purpose |
|-----------|----------------|---------|---------|
| [mlx-audio-swift](https://github.com/Blaizzy/mlx-audio-swift) | `d302a5c…` | MIT | Qwen3 streaming ASR integration |
| [mlx-swift](https://github.com/ml-explore/mlx-swift) | `0.31.3` | MIT | Apple MLX tensor runtime |
| [mlx-swift-lm](https://github.com/ml-explore/mlx-swift-lm) | `3.31.3` | MIT | MLX model utilities |
| [swift-transformers](https://github.com/huggingface/swift-transformers) | `1.1.9` | Apache-2.0 | Tokenizer and model utilities |
| [swift-huggingface](https://github.com/huggingface/swift-huggingface) | `0.8.1` | Apache-2.0 | Model download client |
| [Qwen3-ASR 0.6B / 1.7B MLX 4-bit](https://huggingface.co/mlx-community) | Runtime download | Apache-2.0 | Optional on-device speech-model weights |

The Qwen models are downloaded only after the user selects a local model on
macOS. They are not committed to this repository. Their model cards identify
the original Qwen3-ASR model and the mlx-community conversion.


## Reference only

NanoMouse commit `a6177d898a01662ce551b43a01cf82a9f84ca54c`
(MIT) was used to understand iOS Rime lifecycle boundaries. Its KeyboardKit,
UI, data packages and application features are not linked into OSGKeyboard.

## Explicitly excluded

- rime-ice / 雾凇拼音 — GPL-3.0
- rime-double-pinyin schemas — GPL-3.0
- rime-luna-pinyin and rime-essay — LGPL-3.0
- KeyboardKit Pro — proprietary
