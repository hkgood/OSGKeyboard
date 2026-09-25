import json
import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import evaluate_product_policy_anchors as policy


class ProductPolicyAnchorTests(unittest.TestCase):
    def test_prepare_and_evaluate_anchor_accuracy(self):
        with tempfile.TemporaryDirectory() as raw_directory:
            directory = Path(raw_directory)
            anchors = directory / "anchors.json"
            anchors.write_text(
                json.dumps(
                    [
                        {
                            "id": "one",
                            "text": "open my inbox",
                            "language": "en",
                            "expected": {
                                "recordDisposition": "exclude-device-command"
                            },
                        },
                        {
                            "id": "two",
                            "text": "Could you send the report?",
                            "language": "en",
                            "expected": {
                                "recordDisposition": "keep",
                                "replyableMessage": "true",
                                "task": "true",
                                "question": "true",
                                "ambiguous": "false",
                            },
                        },
                    ]
                ),
                encoding="utf-8",
            )
            queue = directory / "queue.jsonl"
            policy.prepare(SimpleNamespace(anchors=anchors, queue=queue))
            labeler = directory / "labeler.jsonl"
            records = [
                self._record(
                    "one",
                    "open my inbox",
                    disposition="exclude-device-command",
                    replyableMessage="false",
                    task="true",
                    question="false",
                    ambiguous="false",
                ),
                self._record(
                    "two",
                    "Could you send the report?",
                    disposition="keep",
                    replyableMessage="true",
                    task="true",
                    question="true",
                    ambiguous="false",
                ),
            ]
            labeler.write_text(
                "\n".join(json.dumps(record) for record in records) + "\n",
                encoding="utf-8",
            )
            report = policy.evaluate(
                SimpleNamespace(
                    anchors=anchors,
                    queue=queue,
                    labeler=[("test", labeler)],
                    minimum_accuracy=0.95,
                    report=directory / "report.json",
                )
            )

            self.assertTrue(report["eligibleForCorpusReadjudication"])
            self.assertEqual(
                1.0,
                report["labelers"]["test"]["decisionAccuracy"],
            )

    def test_target_gate_ignores_non_target_mismatch(self):
        anchors = [
            {
                "id": "one",
                "text": "take your time",
                "language": "en",
                "expected": {
                    "recordDisposition": "keep",
                    "replyableMessage": "true",
                    "task": "false",
                    "question": "false",
                    "ambiguous": "false",
                },
            }
        ]
        adjudication = self._record(
            "one",
            "take your time",
            disposition="keep",
            replyableMessage="true",
            task="false",
            question="false",
            ambiguous="true",
        )

        result = policy.evaluate_labeler(
            anchors,
            {"one": adjudication},
            {"replyableMessage", "task", "question"},
        )

        self.assertEqual(1.0, result["gateDecisionAccuracy"])
        self.assertLess(result["decisionAccuracy"], 1.0)

    def _record(self, identifier, text, disposition, **values):
        resolutions = {
            field: (
                "unknown"
                if field == "domain"
                else "false"
            )
            for field in policy.ANCHOR_FIELDS
        }
        resolutions.update(values)
        return {
            "id": identifier,
            "recordDisposition": disposition,
            "dispositionConfidence": 0.99,
            "dispositionEvidence": text,
            "resolutions": resolutions,
            "confidence": {field: 0.99 for field in resolutions},
            "evidence": {field: text for field in resolutions},
        }


if __name__ == "__main__":
    unittest.main()
