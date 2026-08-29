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

## Taxonomy v6 candidate contract

The deployed models above remain the historical nine-intent suite. The next
corpus taxonomy is defined by
`Consensus/labeling-instructions-v6.md`: it retains `task`, `question`,
`invitation`, `complaint`, `scheduleNegotiation`, `confirmationDecision`,
`followUpReminder`, `blessing`, and `replyableMessage`, then adds
`assistantCommand`, `informationQuery`, and `systemNotification`. Assistant,
search, and machine-notification text is therefore preserved as explicit
routing data instead of being flattened into legacy negatives or discarded.

Every record also receives one primary domain or `unknown`: `finance`,
`travel`, `calendar`, `communication`, `media`, `smartHome`, `shopping`,
`dining`, `health`, `weather`, `accountService`, or `generalKnowledge`.
`Consensus/adjudication-instructions-v5.md` defines evidence-based resolution
for the expanded fields while retaining the existing queue format.

Intent values remain three-state: `true`, `false`, or `unknown`.
`knownLabels` lists only fields the source actually annotates after an audited
mapping; an absent field is unknown and contributes neither a positive nor a
negative training example. External sources may produce candidates only from a
pinned upstream official `train` split under documented commercial-use terms.
Upstream dev/validation/test data and every local frozen holdout are barred from
training, including normalized near-duplicates.

`chinese-corpus-candidate-audit-v1.json` records the first versioned source
decision. MASSIVE, CrossWOZ, BiToD, MultiDoGO, Taskmaster-1, SNIPS, MInDS-14,
GoEmotions, ASAP, Restaurant8k, and FormosaNLU are admitted to the candidate
audit pipeline subject to their per-source conditions. BANKING77, ABCD,
MultiWOZ, CLINC150, CFPB, `openclaw-zh-greetings`, and LCCC remain quarantined.
Admission is not automatic commercial training approval: revision pinning,
license evidence, attribution, privacy/content review, deterministic mapping,
and holdout deduplication still apply.

Synthetic records are train-only, retain generation and upstream provenance,
use a sample weight no greater than `0.25`, and declare only contractually known
fields. They never enter calibration, evaluation, human gold, or policy-anchor
sets and cannot override conflicting human or licensed non-synthetic evidence.

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
and ASAP. It also includes the MIT-licensed `openclaw-zh-greetings` labels and
the pinned MIT blessing templates from `SWHL/WeChat-AutoSendBless`:

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

## Broad blessing supplement

`blessing-labeling-guidelines.md` defines the broad product boundary. The
dedicated generator creates equal numbers of positive examples and difficult
negatives such as greeting-only, blessing requests, received thanks,
celebration mentions, quotations, reported wishes, and sarcasm:

```bash
python3 Scripts/clipboard_semantics/generate_blessing_training_corpus.py \
  --records-per-language 50000
```

Every generated record declares only `blessing` in `knownLabels`, so unknown
clipboard intents are not treated as false. The generator rejects normalized
base-corpus and frozen-holdout overlap, duplicate text, and common PII shapes.

LCCC may be mined only as an isolated research queue. Although its dataset card
declares MIT, the official CDial-GPT README limits the dataset and pretrained
models to research use. Its source is crawled Weibo dialogue without a complete
underlying content-rights or privacy chain. Download LCCC-base from the official
CDial-GPT link or the `silver/lccc` Hugging Face mirror, then run:

```bash
python3 Scripts/clipboard_semantics/extract_lccc_blessing_candidates.py \
  /path/to/LCCC-base.zip \
  --output /tmp/lccc-blessing-candidates.jsonl \
  --manifest /tmp/lccc-blessing-candidates-manifest.json
```

The resulting unreviewed records are research-only and must not be merged into
a commercial training corpus without legal, privacy, and manual label review.

## Blessing benchmark review

Prepare a blind queue with 3,000 Chinese and 1,500 English records from the
frozen comprehensive holdout:

```bash
python3 Scripts/clipboard_semantics/prepare_blessing_benchmark.py
```

Two different people independently complete `annotator-a.jsonl` and
`annotator-b.jsonl` without seeing `sealed-provenance.jsonl`. Finalization is
strict: incomplete labels, duplicate IDs, reused annotator identity, and
unadjudicated disagreement are fatal.

```bash
python3 Scripts/clipboard_semantics/finalize_blessing_benchmark.py \
  --annotator-a-id reviewer-a \
  --annotator-b-id reviewer-b
```

`BlessingBenchmark/README.md` defines the stable positive and negative boundary
categories. The finalized calibration/test benchmark remains evaluation-only
and must never enter a training corpus.

## Consensus silver data and joint verifiers

The corpus registry combines the preserved historical product corpus, current
and scaled product generators, licensed open data, and project-owned blessing
data without flattening provenance:

```bash
python3 Scripts/clipboard_semantics/build_corpus_registry.py
```

`corpus-registry-sources.json` is the source-of-truth inventory. Exact duplicate
texts retain every source claim, while any occurrence in calibration or frozen
evaluation data globally bars that text from training. Labels use three states:
`true`, `false`, and `unknown`; a missing source annotation is never converted
to a negative label. LCCC and other research-only or unclear-rights sources are
explicitly excluded.

The v2 blind-labeling pilot samples 1,000 distinct near-duplicate clusters.
Three primary models label every record without seeing source labels. Any
non-unanimous record is sent, still blind, to two review models:

```bash
python3 Scripts/clipboard_semantics/merge_consensus_labels_v2.py \
  prepare-review \
  --queue ModelTraining/ClipboardSemantics/CorpusRegistry/labeling-pilot.jsonl \
  --primary sol=/path/to/primary-sol.jsonl \
  --primary grok=/path/to/primary-grok.jsonl \
  --primary codex=/path/to/primary-codex.jsonl \
  --output /path/to/review-queue.jsonl \
  --report /path/to/review-report.json
```

Primary unanimity produces Tier A silver data. Reviewed records require at
least four of five votes for every intent and sentiment field to produce Tier B
silver data at lower training weight. Remaining conflicts, ambiguity, and
positive quoted/meta cases enter a human adjudication queue and never train
automatically. `Consensus/labeling-instructions-v2.md` defines the shared
taxonomy and strict output schema.

The frozen 2026-08-28 pilot used Sol, Grok, and Luna as primary labelers, then
Composer and Claude for blind conflict review. Of 1,000
records, 81 reached Tier A, 290 reached Tier B, and 629 entered human review.
The 0.80 per-language/per-field kappa gate failed, so this pilot is not eligible
for automatic scale-up or model training. `replyableMessage`, `task`,
`question`, and Chinese coordination/blessing boundaries require adjudication
and instruction refinement first.

The 629 unresolved records were then reviewed independently by Claude and Grok
using `Consensus/adjudication-instructions-v1.md`. A record reaches Tier C only
when both adjudicators select the same non-unknown value for every unresolved
field, quote exact supporting text, and report confidence of at least 0.90.
Only 21 records passed; 608 remain unresolved. Tier C keeps a 0.35 sample weight
and remains silver data rather than human gold.

The 608-record remainder was then re-adjudicated with Sol 5.6 and Grok 4.6
using the product-approved boundaries in
`Consensus/labeling-instructions-v3.md` and the disposition-aware schema in
`Consensus/adjudication-instructions-v2.md`. The approved rules exclude clear
device/assistant commands, separate invitation questions from information
questions, treat self-reminders as follow-up only, treat first-person needs as
implicit tasks, require explicit dissatisfaction for complaints, and require
explicit wishes or congratulations for blessings. At the unchanged 0.90
two-model confidence gate, all seven policy-sensitive intent fields were
rechecked even when the old panel had agreed on them. In the final result, 202
additional records reached Tier C, 109 clear device/assistant commands were
isolated, and 297 remained unresolved. A
deterministic language/field/severity-stratified sample of 60 records is the
human product-policy acceptance set; the new silver data must not be promoted
until that sample reaches 95% accuracy. The original per-language/per-field
kappa gate still applies before full-corpus labeling can scale up.

The product owner subsequently labeled 30 high-information anchors for
`replyableMessage`, `task`, and `question`. These decisions are frozen in
`Consensus/product-policy-anchors-v1.json`, and the clarified taxonomy is
documented in `Consensus/labeling-instructions-v5.md`. On a blind replay, Grok
4.6 matched all 63 scored target-field decisions, while Luna 5.6 matched 62 of
63 (98.41%); both pass the 95% target-intent gate. Sol 5.6 was rejected for this
role because it forced low-information fragments into negative labels. The
target fields are eligible for focused re-adjudication, but the broader corpus
is still blocked by the independent ambiguity/disposition and kappa gates.

The original verifier pipeline remains available for reproducing its earlier
three-model study:

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

## Iterative weakly supervised research

The portable research harness runs a fixed 20-round matrix over bilingual
character/word n-grams, sparse logistic classifiers, class balancing,
deterministic label-preserving augmentation, hard-example weighting, and
three-round high-confidence self-training consensus:

```bash
python3 -m pip install -r \
  Scripts/clipboard_semantics/requirements-research.txt
python3 Scripts/clipboard_semantics/generate_open_training_corpus.py \
  --allow-unavailable-sources
python3 Scripts/clipboard_semantics/run_iterative_retraining.py
```

The harness fits thresholds only on the generated validation split. Synthetic
test, golden, random, targeted-release, and comprehensive online corpora never
enter training or threshold calibration. Exact normalized overlap with every
frozen holdout is a fatal error.

The 2026-08-27 study completed the requested 20 rounds and two additional
20-round fine-tuning phases after the first phase missed its release target:

- The shared-configuration phase selected round 1. Random-holdout macro F1 was
  `0.5709`; research-only comprehensive macro F1 was `0.2383`.
- Per-intent selection improved those values to `0.5770` and `0.2645`.
- Explicit evidence gates raised golden macro precision to `0.9877` and
  research-only precision to `0.6097`, but reduced recall too severely.
- The current deployed reference remains stronger: random-holdout macro F1
  `0.7669` and research-only comprehensive macro F1 `0.2783`.

All three phases failed the release gate, so no model was promoted. The compact
study summary and macOS replay instructions are stored under
`IterativeResearch/`; detailed round and evaluation JSON is reproducible and
gitignored.

This harness is deliberately a Linux surrogate. It cannot emit the
`NLModel`-compatible Create ML artifacts used by the keyboard extension.
Deployable training, Core ML compilation, simulator regression, latency, and
memory checks still require macOS with Xcode 26+. A surrogate result can
nominate a data/threshold policy for macOS replay, but cannot authorize
automatic deployment.

## Taxonomy v6 candidate result

The 2026-08-28 v6 run integrated 31,087 license-reviewed open-training
records, 7,200 low-weight bilingual boundary records, and 99 high-confidence
relabels from the former assistant-command exclusion queue. The registry
contains 327,337 canonical records and emits 273,626 train candidates. The
frozen 120-record bilingual product holdout has zero exact overlap with
training.

The additive maxEnt candidate trained `assistantCommand`, `informationQuery`,
`systemNotification`, and the 12-way `domain` classifier. Runtime performance
passed: the four models total 570,083 bytes, load in 49.30 ms, have 0.250 ms
maximum warm p95 latency, and add 25,001,984 bytes of peak RSS in the macOS
benchmark process.

Quality did not pass. Golden new-intent macro F1 is 0.5915, minimum intent
precision is 0.2500, and domain macro F1 is 0.3282, below the 0.90, 0.95, and
0.85 release gates. Only 60 blind records have product-owner labels; the
remaining v6 fields use per-field model consensus and are not human gold.
Therefore the candidate remains staging-only and the deployed models are not
replaced. See `v6-release-gate-report.json` for the machine-readable decision.

## Deployment decision

Only maxEnt models are trained and deployed because they are self-contained in
the keyboard extension. Create ML BERT transfer models depend on
`NLContextualEmbedding` assets that are not guaranteed to exist in a simulator
or keyboard-extension runtime.

The deployed manifest remains schema version 2 until a candidate passes its
frozen acceptance gates. Schema version 3 adds optional joint verifiers,
per-language confidence thresholds, top-1/top-2 margins, and an explicit
`shadow` or `automatic` deployment mode. Schema version 4 adds the three
display-only public intent heads and optional domain classifier. Consumers
accept schema versions 1 through 4 and fall back to the current binary routing
behavior when newer classifiers are absent.

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
