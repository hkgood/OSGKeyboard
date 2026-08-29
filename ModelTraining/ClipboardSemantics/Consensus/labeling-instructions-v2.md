# Clipboard semantic consensus labeling v2

Prompt version: `clipboard-consensus-v2`

Label each record independently using only its text. Do not infer missing
conversation history, and do not inspect source labels or other model outputs.

Return exactly one JSON object per input record:

```json
{
  "id": "same id",
  "labels": {
    "task": "false",
    "question": "false",
    "invitation": "false",
    "complaint": "false",
    "scheduleNegotiation": "false",
    "confirmationDecision": "false",
    "followUpReminder": "false",
    "blessing": "false",
    "replyableMessage": "true"
  },
  "sentiment": "neutral",
  "ambiguous": false,
  "quotedOrMeta": false,
  "confidence": 0.96
}
```

Every intent value must be `true`, `false`, or `unknown`. Use `unknown` when
the text alone does not contain enough evidence. Absence of evidence is not
automatically evidence of a negative label.

## Intent boundaries

- `task`: another person is explicitly requested or assigned to perform an
  action. A personal plan is not a task.
- `question`: a genuine request for information. Rhetorical, quoted, search,
  and documentation examples are not questions.
- `invitation`: an invitation to join an event, meeting, visit, meal, or social
  activity.
- `complaint`: present dissatisfaction, malfunction, bad service, or an
  unresolved problem. Negative sentiment alone is insufficient.
- `scheduleNegotiation`: proposing, changing, comparing, or choosing between
  times. A fixed appointment or deadline alone is insufficient.
- `confirmationDecision`: explicit approval, rejection, commitment, or
  selection of an option. Acknowledgment alone is insufficient.
- `followUpReminder`: a request to remind, check back, or follow up later or
  after a trigger. An ordinary task with a deadline is insufficient.
- `blessing`: the author directly expresses a good wish, congratulation,
  prayer, or hope for any recipient, including self or third parties.
- `replyableMessage`: a direct conversational message that naturally invites
  a response. Terminal acknowledgments, personal notes, quoted examples, and
  factual notices are negative.

Multi-label combinations are valid. For example, “Could you send the report?”
is `task + question + replyableMessage`.

## Special cases

- Set `quotedOrMeta = true` when intent-bearing language is quoted, reported,
  searched, documented, requested as a writing example, or discussed rather
  than performed.
- Set `ambiguous = true` when material context is missing or multiple
  interpretations remain equally plausible.
- Sarcasm, negation, hypothetical future intent, and received thanks must be
  interpreted semantically rather than by keyword matching.
- `sentiment` must be `positive`, `neutral`, `negative`, or `unknown`.
- Do not output reasoning, markdown, comments, or additional fields.
