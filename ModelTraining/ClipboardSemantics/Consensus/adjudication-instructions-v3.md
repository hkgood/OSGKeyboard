# Clipboard semantic evidence adjudication v3

Review only the fields listed in `unresolvedFields`. Judge from the text itself;
do not inspect previous model votes, source labels, or another adjudicator.
Apply `labeling-instructions-v4.md`.

Return one JSON object per input record using the exact schema defined in
`adjudication-instructions-v2.md`.

For compatibility, `recordDisposition` remains `keep` or
`exclude-device-command`. In v3, `exclude-device-command` also covers generic
search, system/account queries, and other clearly virtual-assistant-only text.
It does not cover real-world service requests, named-recipient communication
with content, or private/shared-context interpersonal questions.

Requirements:

- Evidence must be a short exact quote copied from the input text.
- `resolutions`, `confidence`, and `evidence` must contain exactly the fields in
  `unresolvedFields`.
- Use `unknown` rather than inventing context for low-information fragments.
- Confidence is per field and must be between 0 and 1.
- Do not output explanations, markdown, or additional fields.
