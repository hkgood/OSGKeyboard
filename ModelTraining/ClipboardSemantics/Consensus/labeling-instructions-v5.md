# Clipboard semantic consensus labeling v5

Prompt version: `clipboard-consensus-v5`

Apply every rule in `labeling-instructions-v4.md`, with the following
product-owner clarifications taking precedence.

## Replyable message clarifications

- “take your time” is an interpersonal supportive message:
  `replyableMessage=true`, `task=false`.
- “知道了，谢谢” is terminal and not replyable.
- “活动规则按当前方案通过” is a passive decision notice and not replyable.
- Sharing a personal outcome such as “事情总算处理完了，结果居然成了” is
  replyable even without a direct question.
- A private first-person need such as “I need to set up a new PIN” is a task
  but not replyable unless it is addressed to another person.

## Task clarifications

- A first-person decision followed by an impersonal consequence is not
  automatically an assignment. “我拍板先发布基础版，其他候选停止评估” is
  replyable but not a task because it does not directly assign the recipient.
- A decision that explicitly hands off a next action is a task. “我批准退款流程
  的最终版本，可以签字” is replyable and a task.
- Named-recipient communication with actual content is a replyable task:
  “text Sarah that I'll be late” and “send an email to Julie that I can meet
  Saturday” are both `replyableMessage=true`, `task=true`.

## Scope and ambiguity clarifications

- “tell me what's new” and “my claim status” are generic assistant/system
  queries and must be excluded.
- A bare fragment such as “call Mark” does not reveal whether it is an
  interpersonal assignment or an assistant command. Keep it unresolved:
  `ambiguous=true`, with `replyableMessage`, `task`, and `question` all
  `unknown`.
- Apply the same unknown treatment to other low-information fragments rather
  than converting unspecified fields to `false`.
