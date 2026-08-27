import json
import subprocess
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[1] / "apply_verifier_deployment_policy.py"


class VerifierDeploymentPolicyTests(unittest.TestCase):
    def test_rejected_candidate_cannot_change_deployed_manifest(self):
        with self._fixture(accepted=False) as fixture:
            self._run(fixture)

            deployed = self._read(fixture["deployed_manifest"])
            report = self._read(fixture["report"])
            self.assertEqual(2, deployed["schemaVersion"])
            self.assertFalse(report["applied"])
            self.assertEqual(0, report["eligibleVerifierCount"])

    def test_passing_candidate_enters_shadow_and_preserves_classifiers(self):
        with self._fixture(accepted=True) as fixture:
            self._run(fixture)

            deployed = self._read(fixture["deployed_manifest"])
            report = self._read(fixture["report"])
            self.assertEqual(3, deployed["schemaVersion"])
            self.assertEqual("task", deployed["classifiers"][0]["id"])
            self.assertEqual("shadow", deployed["verifiers"][0]["deploymentMode"])
            self.assertFalse(
                deployed["verifiers"][0]["acceptedForAutomaticRouting"]
            )
            self.assertTrue(report["applied"])

    def _fixture(self, accepted):
        temporary = tempfile.TemporaryDirectory()
        root = Path(temporary.name)
        candidate = root / "candidate"
        resource = root / "resource"
        candidate.mkdir()
        resource.mkdir()
        verifier = {
            "id": "action",
            "modelFile": "ActionIntentVerifier.mlmodel",
            "acceptedForAutomaticRouting": accepted,
            "deploymentMode": "automatic" if accepted else "shadow",
        }
        (candidate / verifier["modelFile"]).write_bytes(b"model")
        self._write(
            candidate / "clipboard-semantic-models.json",
            {
                "schemaVersion": 3,
                "classifiers": [{"id": "untrusted-candidate"}],
                "verifiers": [verifier],
            },
        )
        deployed_manifest = resource / "clipboard-semantic-models.json"
        self._write(
            deployed_manifest,
            {
                "schemaVersion": 2,
                "classifiers": [{"id": "task"}],
            },
        )
        fixture = {
            "temporary": temporary,
            "candidate": candidate,
            "resource": resource,
            "deployed_manifest": deployed_manifest,
            "report": root / "report.json",
        }

        class Context:
            def __enter__(self):
                return fixture

            def __exit__(self, *unused):
                temporary.cleanup()

        return Context()

    def _run(self, fixture):
        subprocess.run(
            [
                "python3",
                str(SCRIPT),
                "--candidate-directory",
                str(fixture["candidate"]),
                "--resource-directory",
                str(fixture["resource"]),
                "--report",
                str(fixture["report"]),
                "--apply",
            ],
            check=True,
            capture_output=True,
            text=True,
        )

    def _write(self, path, value):
        path.write_text(json.dumps(value), encoding="utf-8")

    def _read(self, path):
        return json.loads(path.read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main()
