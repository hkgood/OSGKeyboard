# Blessing benchmark review

This directory contains a blind, evaluation-only review queue derived from the
frozen comprehensive holdout. It must never be merged into training.

## Review process

1. Give `review-queue.jsonl` and one annotation template to each of two
   independent human annotators.
2. Do not give annotators `sealed-provenance.jsonl`, the other annotator's
   answers, model predictions, or previous weak labels.
3. Each annotator fills every `label`, `boundaryCategory`, and `confidence`
   field in their own JSONL file.
4. Run `finalize_blessing_benchmark.py` with distinct annotator IDs.
5. If annotations disagree, give only `adjudication-needed.jsonl` to a third
   reviewer and rerun the finalizer with the adjudication file.

## Label

Set `label` to `true` only when the author directly expresses a good wish,
congratulation, prayer, or hope for a recipient. Third-person and self-directed
wishes count. Requests for a blessing, quoted examples, received thanks,
celebration descriptions, ordinary greetings, reports of someone else's wish,
and sarcasm do not count.

## Boundary categories

Use one of these stable values:

### Positive

- `festival_or_birthday`
- `congratulation`
- `health_or_recovery`
- `travel_or_safety`
- `study_or_career`
- `general_good_wish`
- `third_person_or_group`
- `spiritual_or_prayer`

### Negative

- `meta_request_or_template`
- `received_thanks`
- `quoted_or_documented`
- `celebration_mention`
- `ordinary_greeting`
- `positive_language_only`
- `reported_wish`
- `sarcasm_or_anti_blessing`
- `unrelated`

Use `confidence` values `high`, `medium`, or `low`. Explain genuinely
ambiguous context in `notes`.

## Finalization

```bash
python3 Scripts/clipboard_semantics/finalize_blessing_benchmark.py \
  --annotator-a-id reviewer-a \
  --annotator-b-id reviewer-b
```

The command refuses incomplete annotation, duplicate IDs, non-boolean labels,
invalid confidence, missing adjudication, or use of the same person as both
annotators. The finalized benchmark is split deterministically into calibration
and test records.
