# Clipboard semantic consensus labeling v3

Prompt version: `clipboard-consensus-v3`

Label each record independently using only its text. Do not infer missing
conversation history, and do not inspect source labels or other model outputs.

Return exactly one JSON object per input record using the schema from
`labeling-instructions-v2.md`.

## Product-approved boundaries

These rules override the corresponding v2 boundaries:

- Exclude commands that are clearly addressed to a device, app, search engine,
  or virtual assistant rather than another person. Examples include opening an
  inbox, playing music, changing device volume, or showing an account value.
  Ordinary requests sent to another person remain in scope.
- `task`: a first-person need that implies an action is a task even when the
  recipient is not explicit. A self-reminder is not a task. A device or virtual
  assistant command is excluded before intent labeling.
- `question`: an invitation phrased as a question is not a `question`.
  Request-shaped commands are also not information questions.
- `invitation`: an invitation phrased as a question is
  `invitation=true`, `question=false`, and normally
  `replyableMessage=true`.
- `complaint`: require an explicit expression of dissatisfaction, criticism, or
  objection. A loss, theft, malfunction, or unresolved problem without
  expressed dissatisfaction is not a complaint.
- `followUpReminder`: an explicit self-reminder is
  `followUpReminder=true` and `task=false`.
- `blessing`: require an explicit wish, prayer, congratulation, or conventional
  blessing. Generic encouragement, happiness for someone, optimism, or “good
  luck”-free motivational language is not sufficient. Conventional expressions
  such as “生日快乐”, “一路顺风”, “恭喜晋升”, “happy birthday”, and
  “congratulations on the promotion” are explicit.

## Unchanged requirements

- Every intent value is `true`, `false`, or `unknown`.
- `sentiment` is `positive`, `neutral`, `negative`, or `unknown`.
- Set `quotedOrMeta=true` for quoted, reported, searched, documented, or
  example-only intent language.
- Set `ambiguous=true` only when missing context materially prevents a stable
  product label.
- Do not output reasoning, markdown, comments, or additional fields.
