# Clipboard semantic models

This directory contains the reproducible training inputs and evaluation output
for OSGKeyboard's fully local clipboard analyzer.

## Scope

The model suite predicts four independent intents (`task`, `question`,
`invitation`, and `complaint`) plus three-way sentiment. Apple data detectors
remain responsible for dates, addresses, phone numbers, and URLs; `NLTagger`
provides best-effort person and organization names.

The corpus contains 6,334 Chinese and English records:

- 4,100 generated training records
- 1,080 generated validation records
- 1,080 template-held-out test records
- 74 manually authored golden records

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

The selected task, question, and invitation models passed the automatic-routing
precision gates. The complaint model is packaged for further evaluation but its
automatic-routing flag remains disabled because golden-set precision is 88.89%,
below the 90% release gate. Sentiment returns `unknown` unless confidence and
top-two margin checks both pass.

Synthetic results are not treated as production truth. Real opt-in, anonymized
or manually reviewed examples are still required before widening labels or
lowering thresholds.
