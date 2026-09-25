# Clipboard semantic evidence adjudication v4

Review only the fields listed in `unresolvedFields`. Judge from the text itself;
do not inspect human anchor labels, previous model votes, source labels, or
another adjudicator.

Apply `labeling-instructions-v5.md` and every inherited rule from
`labeling-instructions-v4.md`. Return one JSON object per input record using the
exact schema from `adjudication-instructions-v2.md`.

For compatibility, `recordDisposition` remains `keep` or
`exclude-device-command`; the excluded state also covers generic search,
system/account queries, and clearly virtual-assistant-only commands.

Evidence must be an exact text quote. Use `unknown` for every affected intent
when a short fragment lacks enough context. Do not output explanations,
markdown, or additional fields.
