# Clipboard semantic consensus labeling

Prompt version: clipboard-consensus-v1

Label every JSONL queue record independently. Use only the text itself; do not
infer missing conversational context. Return one JSON object per input record:

{"id":"same id","labels":["task"],"ambiguous":false,"quotedOrMeta":false,"confidence":0.98}

Allowed labels:
- task: another person is explicitly asked/assigned to perform an action.
- question: a genuine information question, including request-shaped questions.
- invitation: invitation to join an event or social activity.
- complaint: present dissatisfaction, malfunction, bad service, or unresolved problem.
- scheduleNegotiation: proposing, changing, or choosing between times; a fixed time is not enough.
- confirmationDecision: explicit approval, rejection, or selection of an option.
- followUpReminder: request to remind, check back, or follow up later/after a trigger.
- blessing: a genuine birthday, holiday, congratulations, or good-wish message.
- replyableMessage: a direct conversational message that naturally invites a response.

Rules:
- Multi-label is allowed. "Could you send it?" is task + question + replyableMessage.
- Set quotedOrMeta when intent-like words are quoted, documented, searched, or discussed.
- Set ambiguous when the text cannot be labeled without missing context.
- Empty labels mean none of the product intents.
- Negative sentiment alone is not complaint. Fixed appointments are not schedule negotiation.
- Do not expose reasoning or add fields. Confidence must be between 0 and 1.
