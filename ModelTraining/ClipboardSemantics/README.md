# Clipboard semantic models

This directory contains the reproducible training inputs and evaluation output
for OSGKeyboard's fully local clipboard analyzer.

## Scope

The model suite predicts five independent intents (`task`, `question`,
`invitation`, `complaint`, and `replyableMessage`) plus three-way sentiment.
`replyableMessage` distinguishes messages that invite a response from terminal
acknowledgments, personal notes, quoted questions, and factual notices. Apple
data detectors remain responsible for dates, addresses, phone numbers, and
URLs; `NLTagger` provides best-effort person and organization names.

The corpus contains 7,272 Chinese and English records:

- 4,660 generated training records
- 1,260 generated validation records
- 1,260 template-held-out test records
- 92 manually authored golden records

No user clipboard content is included.

## Reproduce

```bash
python3 Scripts/clipboard_semantics/generate_corpus.py
xcrun swift Scripts/clipboard_semantics/train_models.swift
```

The trainer balances labels, trains maxEnt and BERT candidates, calibrates
high-precision thresholds, writes detailed errors to `evaluation-report.json`,
and copies the selected models into
`OSGKeyboardShared/Resources/ClipboardSemantics`.

## Deployment decision

Only maxEnt models are eligible for keyboard automatic routing. Create ML BERT
transfer models depend on `NLContextualEmbedding` assets that are not guaranteed
to exist in a simulator or keyboard-extension runtime, so they remain evaluation
candidates only.

The selected intent models passed the automatic-routing precision gates. The
replyable-message model reached 100% test precision and 97.96% golden precision;
its measured recall remains part of release monitoring. The complaint model is
also high precision but remains conservative because golden recall is limited.
Sentiment returns `unknown` unless confidence and top-two margin checks both
pass.

Synthetic results are not treated as production truth. Real opt-in, anonymized
or manually reviewed examples are still required before widening labels or
lowering thresholds.
