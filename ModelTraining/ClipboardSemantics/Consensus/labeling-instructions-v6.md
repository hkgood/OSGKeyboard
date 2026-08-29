# Clipboard semantic consensus labeling v6

Prompt version: `clipboard-consensus-v6`

Label each record independently from its text. Do not inspect source labels,
model votes, provenance, or hidden conversation history. This version keeps the
nine product intents from v5 and adds three routing intents plus one domain
field. Its definitions override earlier instructions when they conflict.

## Output schema

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
    "replyableMessage": "true",
    "assistantCommand": "false",
    "informationQuery": "false",
    "systemNotification": "false"
  },
  "domain": "communication",
  "sentiment": "neutral",
  "ambiguous": false,
  "quotedOrMeta": false,
  "confidence": 0.96
}
```

Every intent value is `true`, `false`, or `unknown`. `domain` is one of the
twelve values below or `unknown`. `sentiment` is `positive`, `neutral`,
`negative`, or `unknown`. Do not output reasoning, comments, markdown, or
additional fields.

## Nine product intents

- `task`: a person is assigned or asked to perform an action, or the author
  states an explicit personal commitment or need that implies action. A
  request for a real-world service that naturally needs confirmation, such as
  booking a taxi, restaurant, hotel, or ticket, is also a task. A status
  question, self-reminder, passive decision notice, and pure device/app
  operation are not tasks.
- `question`: a genuine interpersonal request for information. It includes
  imperative requests such as “tell me her email address” when they could
  naturally be sent to a person. Invitation questions and clearly generic
  assistant/search/account queries are not questions.
- `invitation`: an invitation to join an event, meeting, visit, meal, or social
  activity. A question-shaped invitation is normally also
  `replyableMessage=true`, but `question=false`.
- `complaint`: explicit present dissatisfaction, criticism, objection, bad
  service, or an unresolved problem framed as a complaint. A loss,
  malfunction, negative fact, or negative sentiment without expressed
  dissatisfaction is insufficient.
- `scheduleNegotiation`: proposing, changing, comparing, or choosing between
  times. A fixed appointment, reminder time, or deadline alone is insufficient.
- `confirmationDecision`: explicit approval, rejection, commitment, or
  selection of an option. Acknowledgment, receipt confirmation, and passive
  status notice alone are insufficient.
- `followUpReminder`: an explicit request to remind, check back, or follow up
  later or after a trigger, including a self-reminder. An ordinary task with a
  deadline is insufficient; a self-reminder is not a `task`.
- `blessing`: the author directly expresses an explicit wish, prayer,
  congratulation, or conventional blessing. Generic encouragement, optimism,
  happiness for someone, quoted wishes, and requests to write a blessing are
  insufficient.
- `replyableMessage`: an interpersonal message that naturally supports a
  response. Questions, assignments, invitations, ongoing decisions, emotional
  updates, and outcome sharing may qualify. Terminal acknowledgments or thanks,
  private notes, passive factual notices, generic assistant interactions, and
  machine notifications do not.

The v5 product-owner examples remain authoritative: “take your time” is
replyable but not a task; “知道了，谢谢” is terminal; personal outcome sharing
may be replyable; a private first-person need may be a task without being
replyable; and named-recipient communication with actual content is a replyable
task.

## Three routing intents

- `assistantCommand`: an instruction to a device, app, service, search engine,
  or virtual assistant to perform a direct digital or device operation. This
  includes opening or changing app state, alarms and calendar operations, media
  playback, smart-home control, and immediate account/app settings. A
  real-world service request that naturally needs confirmation remains a
  `task`, even when submitted through an assistant.
- `informationQuery`: a generic assistant, search, reference, weather, account,
  or service-status lookup that asks for information rather than asking a
  person. “tell me what's new”, “my claim status”, and generic recommendation
  searches qualify.
- `systemNotification`: machine- or service-generated status, alert, receipt,
  security warning, delivery update, or other notification presented to the
  user rather than authored as an interpersonal message.

These three labels replace the old blanket exclusion of assistant-only text.
Keep such records and label them explicitly. They are normally mutually
exclusive, and their clearly assistant/system-scoped records must not become
`task`, `question`, or `replyableMessage` merely because similar words could
occur in human conversation. Real-world bookings remain tasks. A request to
contact a named person with message content is interpersonal, not an
`assistantCommand`; a bare fragment such as “call Mark” remains ambiguous when
addressee and interaction mode cannot be determined.

## Domains

Choose the single primary subject or operation target:

- `finance`: banking, payments, cards, transfers, investments, insurance, or
  claims.
- `travel`: transport, routes, tickets, hotels, trips, or reservations other
  than restaurant bookings.
- `calendar`: dates, events, meetings, availability, alarms, reminders, or
  scheduling.
- `communication`: calls, contacts, messages, email, social communication, or
  interpersonal conversation.
- `media`: music, podcasts, radio, video, photos, news playback, or media
  discovery.
- `smartHome`: lights, appliances, climate, locks, cameras, or other connected
  home devices.
- `shopping`: products, orders, retail delivery, returns, refunds, or
  marketplace activity.
- `dining`: restaurants, food, menus, takeaway, restaurant reservations, or
  dining service.
- `health`: symptoms, care, medicine, fitness, wellbeing, or medical
  appointments.
- `weather`: current conditions, forecasts, temperature, or weather alerts.
- `accountService`: login, identity, profile, PIN/password, subscription,
  membership, entitlement, or general service support not better covered above.
- `generalKnowledge`: general facts, definitions, recommendations, and
  non-specialized content that does not fit another domain.

Use the action target to resolve a cross-domain record: “text Sam about the
flight” is `communication`, while “is my flight delayed?” is `travel`. Use
`unknown`, not `generalKnowledge`, when missing context prevents a stable
choice.

## Unknown, ambiguity, and metadata

- Use `unknown` only when the text lacks enough evidence for that field. Do not
  turn missing annotation or missing context into `false`.
- Use `false` when the field is in scope and the text provides enough evidence
  that the intent is absent.
- Set `ambiguous=true` when missing context materially prevents a stable product
  label. Set each affected intent and `domain` to `unknown`; unaffected fields
  may still be resolved.
- Set `quotedOrMeta=true` when intent-bearing language is quoted, reported,
  searched, documented, requested as a writing example, or discussed rather
  than performed.
- Multi-label product combinations remain valid, such as
  `task + question + replyableMessage` for an interpersonal “Could you send the
  report?”

## `knownLabels` contract for corpus records

`knownLabels` is ingestion metadata, not part of labeler output. It lists only
the fields a source genuinely annotates after an audited deterministic mapping.
Allowed names are the twelve intent names, `domain`, and `sentiment`.

- A field in `knownLabels` may train from its resolved value, including an
  explicit `false`.
- A field absent from `knownLabels` is `unknown` for training and contributes no
  positive or negative loss.
- Source intent names, topic names, or missing columns must never be expanded
  into negative labels for the rest of the taxonomy.
- A mapped source label may make only its audited target fields known.
  Synthetic data must not claim all labels known merely because the generator
  omitted them.
- Consensus or human review may add a field to `knownLabels` only after that
  field receives a non-`unknown` decision under this taxonomy.

## Training-data boundary

- External data may enter candidate generation only when its commercial-use
  rights and required notices are recorded, its immutable revision is pinned,
  and it comes from the upstream official `train` split. Upstream validation,
  development, test, challenge, and hidden-evaluation records never train.
- When an upstream source publishes only one split explicitly named `train`, it
  may supply training candidates but may not supply OSGKeyboard calibration or
  evaluation truth. If no official train designation exists, the source waits
  in audit and is not locally re-split into eligibility.
- Exact and normalized near-duplicate overlap with any frozen local holdout is a
  fatal exclusion. Privacy, credentials, direct contact data, unsafe content,
  and unsupported language variants are filtered before labeling.
- Synthetic records are training-only, carry explicit synthetic provenance,
  use sample weight at most `0.35`, and may know only the fields guaranteed by
  their generation contract. They cannot enter calibration, evaluation, human
  gold, or policy-anchor sets; cannot override a conflicting human or licensed
  non-synthetic example; and cannot by themselves authorize a new boundary or
  deployment threshold.
- Dataset admission means eligibility for the audited candidate queue, not
  automatic inclusion in commercial training. Every generated artifact still
  requires pinned license evidence, attribution, mapping review, deduplication,
  and acceptance gates.
