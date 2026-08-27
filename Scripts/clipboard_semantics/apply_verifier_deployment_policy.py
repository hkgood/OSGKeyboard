#!/usr/bin/env python3
"""Promote only acceptance-gated verifiers into privacy-safe shadow mode."""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
from datetime import datetime, timezone
from pathlib import Path


DEFAULT_CANDIDATE_DIRECTORY = Path(
    "ModelTraining/ClipboardSemantics/VerifierCandidates"
)
DEFAULT_RESOURCE_DIRECTORY = Path(
    "OSGKeyboardShared/Resources/ClipboardSemantics"
)
DEFAULT_REPORT = Path(
    "ModelTraining/ClipboardSemantics/verifier-deployment-report.json"
)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(128 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--candidate-directory",
        type=Path,
        default=DEFAULT_CANDIDATE_DIRECTORY,
    )
    parser.add_argument(
        "--resource-directory",
        type=Path,
        default=DEFAULT_RESOURCE_DIRECTORY,
    )
    parser.add_argument("--report", type=Path, default=DEFAULT_REPORT)
    parser.add_argument(
        "--apply",
        action="store_true",
        help="Copy eligible models and update the deployed manifest.",
    )
    return parser.parse_args()


def main() -> None:
    arguments = parse_arguments()
    candidate_manifest_path = (
        arguments.candidate_directory / "clipboard-semantic-models.json"
    )
    deployed_manifest_path = (
        arguments.resource_directory / "clipboard-semantic-models.json"
    )
    candidate_manifest = json.loads(
        candidate_manifest_path.read_text(encoding="utf-8")
    )
    deployed_manifest = json.loads(
        deployed_manifest_path.read_text(encoding="utf-8")
    )

    candidate_verifiers = candidate_manifest.get("verifiers") or []
    eligible = [
        verifier
        for verifier in candidate_verifiers
        if verifier.get("acceptedForAutomaticRouting") is True
        and verifier.get("deploymentMode") == "automatic"
    ]
    entries = []
    for verifier in candidate_verifiers:
        model_path = arguments.candidate_directory / verifier["modelFile"]
        if not model_path.is_file():
            raise FileNotFoundError(model_path)
        entries.append(
            {
                "id": verifier["id"],
                "eligible": verifier in eligible,
                "candidateDeploymentMode": verifier.get("deploymentMode"),
                "candidateSHA256": sha256(model_path),
                "decision": (
                    "promote-to-shadow"
                    if verifier in eligible
                    else "retain-current-models"
                ),
            }
        )

    applied = False
    if arguments.apply and eligible:
        promoted_verifiers = []
        for verifier in eligible:
            source = arguments.candidate_directory / verifier["modelFile"]
            destination = arguments.resource_directory / verifier["modelFile"]
            shutil.copy2(source, destination)
            shadow = dict(verifier)
            shadow["acceptedForAutomaticRouting"] = False
            shadow["deploymentMode"] = "shadow"
            shadow["candidatePassedAcceptance"] = True
            promoted_verifiers.append(shadow)

        # Always start from the deployed manifest so binary classifiers cannot
        # be replaced by an experimental candidate as a side effect.
        deployed_manifest["schemaVersion"] = 3
        deployed_manifest["verifiers"] = promoted_verifiers
        deployed_manifest["verifierGeneratedAt"] = candidate_manifest.get(
            "verifierGeneratedAt"
        )
        deployed_manifest["verifierLabelPolicy"] = candidate_manifest.get(
            "verifierLabelPolicy"
        )
        deployed_manifest_path.write_text(
            json.dumps(
                deployed_manifest,
                ensure_ascii=False,
                indent=2,
                sort_keys=True,
            )
            + "\n",
            encoding="utf-8",
        )
        applied = True

    report = {
        "schemaVersion": 1,
        "generatedAt": datetime.now(timezone.utc).isoformat(),
        "applyRequested": arguments.apply,
        "applied": applied,
        "eligibleVerifierCount": len(eligible),
        "deployedClassifierCountPreserved": len(
            deployed_manifest.get("classifiers") or []
        ),
        "policy": (
            "Only acceptance-gated automatic candidates may be copied, and "
            "their first deployed mode is forced to shadow. If none pass, the "
            "deployed manifest and current binary models remain untouched."
        ),
        "verifiers": entries,
    }
    arguments.report.parent.mkdir(parents=True, exist_ok=True)
    arguments.report.write_text(
        json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    print(
        "VERIFIER_DEPLOYMENT_POLICY "
        f"eligible={len(eligible)} applied={str(applied).lower()}"
    )


if __name__ == "__main__":
    main()
