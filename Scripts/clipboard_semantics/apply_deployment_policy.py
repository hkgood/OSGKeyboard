#!/usr/bin/env python3
"""Apply the reviewed deployment thresholds and pinned model selections."""

from __future__ import annotations

import argparse
import json
import shutil
from pathlib import Path


DEFAULT_RESOURCE_DIRECTORY = Path(
    "OSGKeyboardShared/Resources/ClipboardSemantics"
)
DEFAULT_BASELINE_DIRECTORY = Path(
    "ModelTraining/ClipboardSemantics/baselines/2026-08-26-nine-model-v1"
)

# Core thresholds were selected on the 680-record development holdout and
# checked against the golden gate. Task and complaint were later tightened on
# focused development gates; the 20260830 release profile is acceptance-only.
THRESHOLD_POLICY = {
    "task": {
        "global": 0.88,
        "byLanguage": {"en": 0.88, "zh-Hans": 0.73},
    },
    "complaint": {
        "global": 0.82,
        "byLanguage": {"en": 0.84, "zh-Hans": 0.82},
    },
    "scheduleNegotiation": {
        "global": 0.68,
        "byLanguage": {"en": 0.68, "zh-Hans": 0.53},
    },
    "confirmationDecision": {
        "global": 0.72,
        "byLanguage": {"en": 0.72, "zh-Hans": 0.72},
    },
    "followUpReminder": {
        "global": 0.73,
        "byLanguage": {"en": 0.73, "zh-Hans": 0.73},
    },
    "blessing": {
        "global": 0.69,
        "byLanguage": {"en": 0.69, "zh-Hans": 0.77},
    },
}

PINNED_MODELS = {
    "scheduleNegotiation": "ScheduleNegotiationIntentClassifier.mlmodel",
}


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--resource-directory",
        type=Path,
        default=DEFAULT_RESOURCE_DIRECTORY,
    )
    parser.add_argument(
        "--baseline-directory",
        type=Path,
        default=DEFAULT_BASELINE_DIRECTORY,
    )
    parser.add_argument(
        "--candidate-resource-directory",
        type=Path,
        default=None,
    )
    parser.add_argument(
        "--promote-classifier",
        action="append",
        default=[],
    )
    return parser.parse_args()


def main() -> None:
    arguments = parse_arguments()
    resource_directory: Path = arguments.resource_directory
    baseline_directory: Path = arguments.baseline_directory
    manifest_path = resource_directory / "clipboard-semantic-models.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    classifiers = {
        classifier["id"]: classifier
        for classifier in manifest["classifiers"]
    }
    promoted_classifiers = arguments.promote_classifier

    if promoted_classifiers:
        candidate_directory: Path | None = arguments.candidate_resource_directory
        if candidate_directory is None:
            raise RuntimeError(
                "--candidate-resource-directory is required when promoting classifiers"
            )
        candidate_manifest_path = (
            candidate_directory / "clipboard-semantic-models.json"
        )
        candidate_manifest = json.loads(
            candidate_manifest_path.read_text(encoding="utf-8")
        )
        candidates = {
            classifier["id"]: classifier
            for classifier in candidate_manifest["classifiers"]
        }
        for classifier_id in promoted_classifiers:
            if classifier_id not in candidates:
                raise RuntimeError(
                    f"Cannot promote missing classifier: {classifier_id}"
                )
            candidate = dict(candidates[classifier_id])
            candidate["trainedAt"] = candidate_manifest["generatedAt"]
            candidate["trainingCorpusRecordCount"] = candidate_manifest[
                "corpusRecordCount"
            ]
            model_file = candidate["modelFile"]
            shutil.copy2(
                candidate_directory / model_file,
                resource_directory / model_file,
            )
            if classifier_id in classifiers:
                classifiers[classifier_id].clear()
                classifiers[classifier_id].update(candidate)
            else:
                manifest["classifiers"].append(candidate)
                classifiers[classifier_id] = candidate

    missing = sorted(set(THRESHOLD_POLICY) - set(classifiers))
    if missing:
        raise RuntimeError(f"Manifest is missing classifiers: {missing}")

    for classifier_id, policy in THRESHOLD_POLICY.items():
        classifier = classifiers[classifier_id]
        classifier["acceptedForAutomaticRouting"] = True
        classifier["confidenceThreshold"] = policy["global"]
        classifier["confidenceThresholdsByLanguage"] = policy["byLanguage"]

    for classifier_id, model_file in PINNED_MODELS.items():
        source = baseline_directory / model_file
        destination = resource_directory / classifiers[classifier_id]["modelFile"]
        if not source.is_file():
            raise RuntimeError(f"Pinned model is missing: {source}")
        shutil.copy2(source, destination)

    manifest_path.write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    print(
        "DEPLOYMENT_POLICY_DONE "
        f"thresholds={len(THRESHOLD_POLICY)} pinnedModels={len(PINNED_MODELS)} "
        f"promotedModels={len(promoted_classifiers)}"
    )


if __name__ == "__main__":
    main()
