# Clipboard semantic evidence adjudication v2

Review only the fields listed in `unresolvedFields`. Judge from the text itself;
do not inspect previous model votes, source labels, or another adjudicator.
Apply the product-approved boundaries from `labeling-instructions-v3.md`.

Return one JSON object per input record:

```json
{
  "id": "same id",
  "recordDisposition": "keep",
  "dispositionConfidence": 0.98,
  "dispositionEvidence": "send the report",
  "resolutions": {
    "task": "true",
    "ambiguous": "false"
  },
  "confidence": {
    "task": 0.97,
    "ambiguous": 0.94
  },
  "evidence": {
    "task": "send the report",
    "ambiguous": "by Friday"
  }
}
```

Requirements:

- `recordDisposition` must be `keep` or `exclude-device-command`.
- Use `exclude-device-command` only when the text is clearly addressed to a
  device, app, search engine, or virtual assistant. Do not use it for an
  ordinary request to another person.
- `dispositionConfidence` must be between 0 and 1.
- `dispositionEvidence` must be a short exact quote copied from the text.
- `resolutions`, `confidence`, and `evidence` must contain exactly the fields in
  `unresolvedFields`, even when the record is marked for exclusion.
- Intent and flag values are `true`, `false`, or `unknown`.
- Sentiment values are `positive`, `neutral`, `negative`, or `unknown`.
- Field evidence must be a short exact quote copied from the input text.
- Use `unknown` when the text alone does not justify a decision.
- Confidence is per field and must be between 0 and 1.
- Do not output explanations, markdown, or additional fields.

Critical product decisions:

- An invitation question is `invitation=true`, `question=false`, and normally
  `replyableMessage=true`.
- An explicit self-reminder is `followUpReminder=true`, `task=false`.
- A first-person need implying action is `task=true`.
- A problem is not a complaint unless dissatisfaction, criticism, or objection
  is explicitly expressed.
- Generic encouragement or happiness is not a blessing; require an explicit
  wish, prayer, congratulation, or conventional blessing.
