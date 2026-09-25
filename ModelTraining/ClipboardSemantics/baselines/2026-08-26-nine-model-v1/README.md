# Nine-model v1 baseline

This snapshot predates the second low-recall corpus expansion.

- Training corpus: 11,172 records
- Corrected development holdout: 640 records, zero exact training overlap
- Binary macro precision: 0.9492
- Binary macro recall: 0.5091
- Binary macro F1: 0.6374
- Runtime-gated sentiment macro F1: 0.6228

The holdout is a development benchmark, not a final blind release gate.

`ScheduleNegotiationIntentClassifier.mlmodel` is preserved here because it
outperformed the expanded-corpus replacement and remains the deployed model.
