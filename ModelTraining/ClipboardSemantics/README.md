# Clipboard semantic models

This directory contains the reproducible training inputs and evaluation output
for OSGKeyboard's fully local clipboard analyzer.

## Scope

The model suite predicts nine independent intents (`task`, `question`,
`invitation`, `complaint`, `scheduleNegotiation`, `confirmationDecision`,
`followUpReminder`, `blessing`, and `replyableMessage`) plus three-way sentiment.
`replyableMessage` distinguishes messages that invite a response from terminal
acknowledgments, personal notes, quoted questions, and factual notices. Apple
data detectors remain responsible for dates, addresses, phone numbers, and
URLs; `NLTagger` provides best-effort person and organization names.

The generated base corpus contains 17,692 Chinese and English records:

- 11,500 generated training records
- 2,970 generated validation records
- 2,970 template-held-out test records
- 252 manually authored golden records

The generator reserves golden text before expansion, keeps template families
strictly split, and rejects duplicate IDs/text, cross-split text leakage,
unsupported labels, insufficient bilingual golden coverage, and content that
resembles direct contact data or credentials. No user clipboard content is
included.

## Reproduce

```bash
python3 Scripts/clipboard_semantics/generate_corpus.py
xcrun swift Scripts/clipboard_semantics/train_models.swift --algorithms maxEnt
python3 Scripts/clipboard_semantics/apply_deployment_policy.py
```

The trainer deterministically balances labels with classifier-specific hard
negatives, trains ten self-contained maxEnt models, calibrates high-precision
global and per-language thresholds on validation data, writes detailed errors
to `evaluation-report.json`, and copies the selected models into
`OSGKeyboardShared/Resources/ClipboardSemantics`. The deployment-policy step
applies thresholds reviewed on the separate development holdout and restores
the preserved schedule-negotiation model, which remained stronger than its
expanded-corpus replacement.

The targeted task/complaint round trains only those classifiers into a
candidate directory, then promotes the reviewed artifacts without replacing
the other eight deployed models:

```bash
xcrun swift Scripts/clipboard_semantics/train_models.swift \
  --algorithms maxEnt --classifiers task,complaint \
  --candidate-directory /tmp/osg-targeted-candidates \
  --resource-directory /tmp/osg-targeted-resources \
  --report /tmp/osg-targeted-training-report.json
python3 Scripts/clipboard_semantics/apply_deployment_policy.py \
  --candidate-resource-directory /tmp/osg-targeted-resources \
  --promote-classifier task --promote-classifier complaint
```

## Licensed open-data training

The reproducible open-data supplement uses official training splits from
MASSIVE, CrossWOZ, GoEmotions, MultiDoGO, Taskmaster-1, CLINC150, CFPB,
and ASAP:

```bash
python3 Scripts/clipboard_semantics/generate_open_training_corpus.py
xcrun swift Scripts/clipboard_semantics/train_models.swift \
  --algorithms maxEnt \
  --corpus ModelTraining/ClipboardSemantics/combined-training-corpus.jsonl \
  --candidate-directory ModelTraining/ClipboardSemantics/baselines/open-data/Candidates \
  --resource-directory ModelTraining/ClipboardSemantics/baselines/open-data \
  --report ModelTraining/ClipboardSemantics/baselines/open-data/training-report.json
```

`open-training-sources.json` pins source revisions and licenses. Each external
record declares `knownLabels`; classifiers ignore labels that the source did
not annotate instead of treating them as negatives. The generator removes
normalized text found in any frozen `*holdout-corpus.jsonl` and leaves the base
validation, test, and golden splits unchanged. Deleted, non-commercial,
license-unclear, ShareAlike-pending, and holdout-only sources are excluded.
CPED is also excluded because the repository license does not establish
commercial rights to the underlying television dialogue; synthetic blessing
datasets without a clear per-record rights chain are excluded as well.

## Consensus silver data and joint verifiers

The precision-first pipeline prepares a license-traceable queue from public
training data, accepts only three-model agreement or source-supported
two-of-three agreement, and keeps conflicts out of training:

```bash
python3 Scripts/clipboard_semantics/generate_consensus_labels.py prepare
python3 Scripts/clipboard_semantics/generate_consensus_labels.py merge \
  --labeler gpt=ModelTraining/ClipboardSemantics/Consensus/labeler-gpt.jsonl \
  --labeler grok=ModelTraining/ClipboardSemantics/Consensus/labeler-grok.jsonl \
  --labeler luna=ModelTraining/ClipboardSemantics/Consensus/labeler-luna.jsonl
xcrun swift Scripts/clipboard_semantics/train_verifiers.swift
```

The merge step preserves source license/revision, prompt version, labeler
confidence, votes, agreement, conflict reason, and Fleiss kappa. Accepted
records are separated into train, calibration, and frozen acceptance splits by
a stable near-duplicate signature, so slot variants cannot cross splits.

`train_verifiers.swift` trains two local maxEnt models:

- Action: `taskOnly`, `complaintOnly`, `both`, `questionRequest`, `neither`
- Coordination: `invitation`, `scheduleNegotiation`,
  `confirmationDecision`, `followUpReminder`, `neither`

Candidate manifests use schema version 3 and record confidence plus top-1/top-2
margin thresholds by language. A verifier remains `shadow` unless every routed
label in English and Simplified Chinese has at least 100 acceptance predictions
at 95% consensus-relative precision. The runtime retains schema 1/2
compatibility, evaluates schema 3 shadow verifiers only after a Stage A
candidate, and stores only bounded aggregate disagreement counters without
clipboard text.

Without human-reviewed gold labels, these results measure agreement with the
model committee, not production truth. A passing verifier may enter shadow
deployment, but cannot be described as having 95% real-user precision.

## Deployment decision

Only maxEnt models are trained and deployed because they are self-contained in
the keyboard extension. Create ML BERT transfer models depend on
`NLContextualEmbedding` assets that are not guaranteed to exist in a simulator
or keyboard-extension runtime.

The deployed manifest remains schema version 2 until a verifier passes its
frozen acceptance gates. Schema version 3 adds optional joint verifiers,
per-language confidence thresholds, top-1/top-2 margins, and an explicit
`shadow` or `automatic` deployment mode. Consumers fall back to the current
binary routing behavior when verifiers are absent.

All ten deployed models pass the golden precision gate after deployment
policy is applied. The preserved six-model and first nine-model reports are
under `baselines`; `deployment-golden-report.json` records the final deployed
models and thresholds.

Synthetic results are not treated as production truth. Real opt-in, anonymized
or manually reviewed examples are still required before widening labels or
lowering thresholds.

## Random holdout

The deployment models also have a reproducible random-combination holdout check
whose templates and vocabulary are separate from the training generator:

```bash
python3 Scripts/clipboard_semantics/generate_random_holdout.py
xcrun swift Scripts/clipboard_semantics/evaluate_random_holdout.swift
```

Seed `20260826` produces 680 records across 17 scenario families, split evenly
between English and Simplified Chinese. The corpus has zero exact-text overlap
with the training corpus. It is a development benchmark used for threshold
selection and is never consumed by `train_models.swift`.

The current development report reaches 0.9832 binary macro precision, 0.6557
recall, and 0.7669 macro F1. Runtime-gated sentiment macro F1 is 0.6994.

A separate focused acceptance profile is generated once with seed `20260827`:

```bash
python3 Scripts/clipboard_semantics/generate_random_holdout.py \
  --profile fresh --seed 20260827 --samples-per-family 20
xcrun swift Scripts/clipboard_semantics/evaluate_random_holdout.swift \
  --corpus ModelTraining/ClipboardSemantics/fresh-metric-holdout-corpus.jsonl \
  --seed 20260827 \
  --report ModelTraining/ClipboardSemantics/fresh-metric-holdout-report.json
```

This 480-record, zero-overlap holdout now serves as a focused development
benchmark. The deployed task model reaches 1.0000 precision and 0.7500 recall
on English records; complaint reaches 1.0000 precision and 0.6000 recall
overall.

Three later zero-overlap profiles exercise different task and complaint
wording. The final 640-record release gate (seed `20260830`) records 1.0000
precision for English task and complaint, with 0.4000 and 0.5375 recall
respectively. The preceding 600-record confirmation gate also records 1.0000
precision for both, with 0.3000 English-task recall and 0.6056 complaint
recall. This variation is intentional evidence that the 95% precision target
is met conservatively while English-task recall remains the next improvement
target.

At runtime, task results are suppressed when complaint confidence is at least
0.60 and the text contains no explicit assignment/request marker. The same
policy is applied by the holdout evaluator so reported task precision matches
the product behavior.

## Performance snapshot

The ten deployed source models retain the local-inference constraint; the
preserved six-model baseline totals 105,619 bytes. On an iPhone 17 Pro iOS 26.5 simulator, the
debug unit-test harness measured 98.8 ms for the first full analysis and
3.7 ms average across 20 warm analyses. Simulator process memory is not a
substitute for the keyboard extension's physical-device peak RSS; that remains
a release gate before widening automatic routing.
