# Six-model clipboard semantics baseline

This directory preserves the complete evaluation report that was deployed before
the three new intent classifiers were added. It is a metrics baseline, not a
second set of deployable model binaries.

- Report generated at: `2026-08-22T09:30:13Z`
- Corpus records: `7,272`
- Models: `task`, `question`, `invitation`, `complaint`, `replyableMessage`,
  `sentiment`
- Manifest schema: `1`
- Report SHA-256:
  `eaa3c2c3fe4151bd6585bfbe7404f848543e4b7321d9ba4376b9c872d2844fdd`

The original deployment manifest used these global thresholds:

- `task`: `0.60`
- `question`: `0.60`
- `invitation`: `0.77`
- `complaint`: `0.68`
- `replyableMessage`: `0.60`
- `sentiment`: no binary threshold

Deployed asset SHA-256 values:

```text
443ce5406a14e3b2051fb265caec116025ee8db088eff496dadb337535843b24  ComplaintIntentClassifier.mlmodel
b7e2266e0926daa9b37926170da200b150024edc55c6bd7644f4252ecaead07c  ConversationalReplyIntentClassifier.mlmodel
e3b9391a5349a43eea511c2e3c7a6697f350510532dc4f190ef707a871a86125  InvitationIntentClassifier.mlmodel
eb0f57da2ea17abcb3847d7c318feb3f50fd0393ffd2ec57c93d9d59bc583dc3  QuestionIntentClassifier.mlmodel
3c7c849cb00163ae0b17d9444f2359aa5f1aecb6d9d65a945b91e9f1d09f9b6d  SentimentClassifier.mlmodel
e4f465e1b62da6ad916e3af1be10d1c63487865134857145476143499af408db  TaskIntentClassifier.mlmodel
722047dbe2df7d4f73d3f7d75cd8fbd9a05e47cb7fa5ec71cab2981a5b91c6ac  clipboard-semantic-models.json
```

See `evaluation-report.json` in this directory for every aggregate,
per-language, and error-example metric from the baseline run.
