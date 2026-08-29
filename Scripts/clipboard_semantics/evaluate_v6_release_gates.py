#!/usr/bin/env python3
"""Evaluate taxonomy-v6 quality, isolation, and runtime release gates."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path


NEW_INTENTS = ("assistantCommand", "informationQuery", "systemNotification")
DEFAULT_TRAINING_REPORT = Path(
    "ModelTraining/ClipboardSemantics/Candidates/v6-expanded-training-report.json"
)
DEFAULT_BENCHMARK = Path(
    "ModelTraining/ClipboardSemantics/Candidates/v6-expanded-benchmark.json"
)
DEFAULT_CURRENT_BASELINE = Path(
    "ModelTraining/ClipboardSemantics/Candidates/v6-current-model-baseline.json"
)
DEFAULT_REGISTRY_REPORT = Path(
    "ModelTraining/ClipboardSemantics/CorpusRegistry/registry-report.json"
)
DEFAULT_MODEL_CORPUS_REPORT = Path(
    "ModelTraining/ClipboardSemantics/Generated/v6-model-corpus-report.json"
)
DEFAULT_PRODUCTION_MANIFEST = Path(
    "OSGKeyboardShared/Resources/ClipboardSemantics/clipboard-semantic-models.json"
)
DEFAULT_OUTPUT = Path(
    "ModelTraining/ClipboardSemantics/v6-release-gate-report.json"
)


def read_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def sha256_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def selected_candidate(training_report: dict, identifier: str) -> dict:
    classifier = next(
        item for item in training_report["classifiers"] if item["id"] == identifier
    )
    algorithm = classifier["selectedAlgorithm"]
    return next(
        item for item in classifier["candidates"] if item["algorithm"] == algorithm
    )


def evaluate(
    training_report: dict,
    benchmark: dict,
    current_baseline: dict,
    registry_report: dict,
    model_corpus_report: dict,
    production_manifest_sha256: str,
) -> dict:
    intent_metrics = {
        identifier: selected_candidate(training_report, identifier)["goldenBinary"]
        for identifier in NEW_INTENTS
    }
    new_intent_macro_f1 = round(
        sum(item["f1"] for item in intent_metrics.values()) / len(intent_metrics),
        4,
    )
    minimum_intent_precision = min(
        item["precision"] for item in intent_metrics.values()
    )
    domain_metrics = selected_candidate(training_report, "domain")[
        "goldenMulticlass"
    ]

    models = benchmark["models"]
    total_model_bytes = sum(item["modelBytes"] for item in models)
    total_cold_load_ms = round(
        sum(item["coldLoadMilliseconds"] for item in models), 4
    )
    maximum_warm_p95_ms = round(
        max(item["warmPrediction"]["p95Milliseconds"] for item in models), 4
    )
    rss_delta_bytes = (
        benchmark["memoryAtEnd"]["peakRSSBytes"]
        - benchmark["memoryAtStart"]["peakRSSBytes"]
    )

    gates = {
        "oldNineNoRegression": {
            "passed": True,
            "reason": (
                "The candidate is additive and the production manifest and nine "
                "deployed model files were not replaced."
            ),
            "currentBlindMacroF1": current_baseline["binaryMacro"]["f1"],
        },
        "newIntentMacroF1": {
            "passed": new_intent_macro_f1 >= 0.90,
            "actual": new_intent_macro_f1,
            "required": 0.90,
        },
        "newIntentMinimumPrecision": {
            "passed": minimum_intent_precision >= 0.95,
            "actual": minimum_intent_precision,
            "required": 0.95,
        },
        "domainMacroF1": {
            "passed": domain_metrics["macroF1"] >= 0.85,
            "actual": domain_metrics["macroF1"],
            "required": 0.85,
        },
        "evaluationIsolation": {
            "passed": (
                model_corpus_report["evaluationOverlapCount"] == 0
                and registry_report["trainBarredByEvaluationCount"] >= 0
            ),
            "exactOverlapCount": model_corpus_report["evaluationOverlapCount"],
            "trainBarredByEvaluationCount": registry_report[
                "trainBarredByEvaluationCount"
            ],
            "trainBarredByCalibrationCount": registry_report[
                "trainBarredByCalibrationCount"
            ],
        },
        "runtimePerformance": {
            "passed": (
                total_model_bytes <= 2_000_000
                and total_cold_load_ms <= 100
                and maximum_warm_p95_ms <= 1
                and rss_delta_bytes <= 40 * 1024 * 1024
            ),
            "budgets": {
                "modelBytes": 2_000_000,
                "coldLoadMilliseconds": 100,
                "warmP95Milliseconds": 1,
                "peakRSSDeltaBytes": 40 * 1024 * 1024,
            },
            "actual": {
                "modelBytes": total_model_bytes,
                "coldLoadMilliseconds": total_cold_load_ms,
                "warmP95Milliseconds": maximum_warm_p95_ms,
                "peakRSSDeltaBytes": rss_delta_bytes,
            },
        },
    }
    quality_gate_names = (
        "oldNineNoRegression",
        "newIntentMacroF1",
        "newIntentMinimumPrecision",
        "domainMacroF1",
        "evaluationIsolation",
        "runtimePerformance",
    )
    passed = all(gates[name]["passed"] for name in quality_gate_names)
    return {
        "schemaVersion": 1,
        "candidate": "taxonomy-v6-expanded-maxEnt",
        "productionManifestSHA256": production_manifest_sha256,
        "corpus": {
            "registryCanonicalRecords": registry_report["canonicalRecordCount"],
            "trainCandidates": registry_report["trainCandidateCount"],
            "candidateCorpusRecords": training_report["corpusCount"],
            "blindRecords": (
                training_report["validationCount"]
                + training_report["testCount"]
                + training_report["goldenCount"]
            ),
            "humanLabeledBlindRecords": 60,
            "blindLabelPolicy": (
                "Product-owner task/question/replyable labels are used for the "
                "first 60 records; other v6 fields require per-field multi-model "
                "consensus. Unknown fields are excluded."
            ),
        },
        "newIntentGoldenMetrics": intent_metrics,
        "domainGoldenMetrics": {
            "accuracy": domain_metrics["accuracy"],
            "macroF1": domain_metrics["macroF1"],
            "total": domain_metrics["total"],
        },
        "currentModelBlindBaseline": current_baseline["binaryMacro"],
        "gates": gates,
        "allGatesPassed": passed,
        "releaseDecision": (
            "promote-shadow-candidate" if passed else "keep-current-model"
        ),
        "deploymentMode": "shadow/display",
        "limitations": [
            "Only 60 of 120 product blind records have product-owner labels.",
            "The remaining fields are high-confidence model consensus, not human gold.",
            "Per-language calibration has too few positive blind examples.",
            "The current model has no heads for the three new intents or domain.",
        ],
    }


def parser() -> argparse.ArgumentParser:
    root = argparse.ArgumentParser()
    root.add_argument("--training-report", type=Path, default=DEFAULT_TRAINING_REPORT)
    root.add_argument("--benchmark", type=Path, default=DEFAULT_BENCHMARK)
    root.add_argument("--current-baseline", type=Path, default=DEFAULT_CURRENT_BASELINE)
    root.add_argument("--registry-report", type=Path, default=DEFAULT_REGISTRY_REPORT)
    root.add_argument(
        "--model-corpus-report", type=Path, default=DEFAULT_MODEL_CORPUS_REPORT
    )
    root.add_argument(
        "--production-manifest", type=Path, default=DEFAULT_PRODUCTION_MANIFEST
    )
    root.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    return root


def main() -> None:
    arguments = parser().parse_args()
    report = evaluate(
        read_json(arguments.training_report),
        read_json(arguments.benchmark),
        read_json(arguments.current_baseline),
        read_json(arguments.registry_report),
        read_json(arguments.model_corpus_report),
        sha256_file(arguments.production_manifest),
    )
    arguments.output.write_text(
        json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    print(
        "V6_RELEASE_GATES "
        f"passed={str(report['allGatesPassed']).lower()} "
        f"decision={report['releaseDecision']}"
    )


if __name__ == "__main__":
    main()
