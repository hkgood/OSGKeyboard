# Clipboard semantic evidence adjudication v5

Review only the fields listed in `unresolvedFields`. Judge from the text itself;
do not inspect source labels, provenance, previous model votes, human anchors,
or another adjudicator.

Apply `labeling-instructions-v6.md`. Return one JSON object per input record
using the evidence schema from `adjudication-instructions-v2.md`:

```json
{
  "id": "same id",
  "recordDisposition": "keep",
  "dispositionConfidence": 0.98,
  "dispositionEvidence": "play my workout playlist",
  "resolutions": {
    "assistantCommand": "true",
    "domain": "media"
  },
  "confidence": {
    "assistantCommand": 0.97,
    "domain": 0.95
  },
  "evidence": {
    "assistantCommand": "play",
    "domain": "workout playlist"
  }
}
```

Requirements:

- `recordDisposition` remains `keep` or `exclude-device-command` for file-format
  compatibility. Under v6, assistant commands, information queries, and system
  notifications are taxonomy records and must be `keep`.
- Use `exclude-device-command` only when replaying a queue explicitly frozen
  under v4/v5 exclusion policy. Do not use it in a new v6 queue.
- `dispositionConfidence` and every per-field confidence must be between 0 and
  1.
- `dispositionEvidence` and field evidence must be short exact quotes copied
  from the input text.
- `resolutions`, `confidence`, and `evidence` must contain exactly the fields in
  `unresolvedFields`, even if a legacy replay record is excluded.
- Intent and flag values are `true`, `false`, or `unknown`.
- `domain` is `finance`, `travel`, `calendar`, `communication`, `media`,
  `smartHome`, `shopping`, `dining`, `health`, `weather`, `accountService`,
  `generalKnowledge`, or `unknown`.
- `sentiment` is `positive`, `neutral`, `negative`, or `unknown`.
- Use `unknown` when the text alone does not justify a stable decision. A
  low-information fragment must not be forced to `false` or into
  `generalKnowledge`.
- Do not output explanations, markdown, comments, or additional fields.

Critical boundary checks:

- Resolve clearly device-, app-, or assistant-directed direct digital
  operations as `assistantCommand=true`; resolve generic lookups as
  `informationQuery=true`; resolve machine-authored alerts and status messages
  as `systemNotification=true`.
- A request for a real-world service that naturally needs confirmation, such as
  booking a taxi, restaurant, hotel, or ticket, remains `task=true` rather than
  `assistantCommand=true`.
- Do not infer `task`, `question`, or `replyableMessage` from those records
  unless the text independently contains an interpersonal act.
- A named-recipient communication request with actual content is an
  interpersonal replyable task. A bare “call Mark” remains unknown for affected
  fields when the addressee is unclear.
- Invitation questions are `invitation=true`, `question=false`; explicit
  self-reminders are `followUpReminder=true`, `task=false`; first-person needs
  implying personal action remain tasks.
- Complaints require explicit dissatisfaction, and blessings require an
  explicit wish, prayer, congratulation, or conventional blessing.
- Choose one domain from the operation target. If no primary target can be
  established, resolve `domain` as `unknown`.

`knownLabels` is corpus metadata and must not appear in adjudicator output.
Downstream merging may add an adjudicated field to `knownLabels` only when both
the field value and its evidence pass the configured acceptance gate and the
value is not `unknown`.
