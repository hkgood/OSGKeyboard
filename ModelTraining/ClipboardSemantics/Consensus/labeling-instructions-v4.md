# Clipboard semantic consensus labeling v4

Prompt version: `clipboard-consensus-v4`

Label from the text alone. Do not inspect source labels, model votes, or hidden
conversation history. The product owner decisions below override all earlier
versions.

## Record scope

Exclude text that is clearly a generic search, device control, app/account
query, alarm/calendar operation, or other virtual-assistant-only command.

Keep these in scope:

- a request to perform a real-world service that naturally needs confirmation,
  such as booking a taxi;
- a request to communicate with a named recipient when the content to convey is
  present;
- a private or shared-context information question that could naturally be sent
  to another person, such as asking for a relative's email address.

If a short fragment does not contain enough evidence to distinguish a human
message from a query or command, keep it unresolved with `ambiguous=true` and
the affected intents set to `unknown`. Do not force it into the excluded or
negative class.

## Product intent boundaries

- `replyableMessage=true` when an in-scope interpersonal message naturally
  supports a response. Questions, assignments, ongoing decisions, emotional
  updates, and outcome sharing can be replyable.
- Terminal acknowledgments and thanks such as “知道了，谢谢” are not
  replyable. A passive factual notice that creates no conversational next step
  is also not replyable.
- `task=true` for an assigned action, an explicit first-person commitment, or a
  first-person need that implies a personal action. A pure status question is
  not a task.
- A request to email, text, or otherwise contact a named recipient is a
  replyable task when the message content or purpose is included. A bare
  command such as “call Mark” is ambiguous without more context.
- `question=true` for any genuine request for information, including an
  imperative such as “tell me her email address”.
- A polite interrogative action request such as “Can you send the report?” is
  both `task=true` and `question=true`. A question about when an existing task
  will happen is `question=true`, `task=false`.
- A request for a recommendation is excluded when it is clearly a generic
  assistant/search query rather than an interpersonal request.
- An invitation phrased as a question remains `invitation=true`,
  `question=false`, and normally `replyableMessage=true`.
- An explicit self-reminder remains `followUpReminder=true`, `task=false`.
- A complaint still requires explicit dissatisfaction, criticism, or objection.
- A blessing still requires an explicit wish, prayer, congratulation, or
  conventional blessing.

## Output states

- Intent values are `true`, `false`, or `unknown`.
- `sentiment` is `positive`, `neutral`, `negative`, or `unknown`.
- Use `ambiguous=true` only when missing context materially prevents a stable
  product label.
- Use `quotedOrMeta=true` for quoted, reported, searched, documented, or
  example-only intent language.
- Do not output explanations, markdown, comments, or additional fields.
