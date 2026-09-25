# Clipboard semantic evidence adjudication v1

Review only the fields listed in `unresolvedFields`. Judge from the text itself;
do not inspect previous model votes, source labels, or another adjudicator.

Return one JSON object per input record:

```json
{
  "id": "same id",
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

- `resolutions`, `confidence`, and `evidence` must contain exactly the fields in
  `unresolvedFields`.
- Intent and flag values are `true`, `false`, or `unknown`.
- Sentiment values are `positive`, `neutral`, `negative`, or `unknown`.
- Evidence must be a short exact quote copied from the input text.
- Use `unknown` when the text alone does not justify a decision.
- Confidence is per field and must be between 0 and 1.
- Do not output explanations, markdown, or additional fields.

Use the boundaries from `labeling-instructions-v2.md`. In particular, distinguish
requests from personal plans, genuine information questions from request-shaped
commands, direct messages from terminal notices, and expressed wishes from
quoted, future, sarcastic, or received blessings.
