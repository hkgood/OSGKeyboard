import json
import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import adjudicate_consensus_conflicts as adjudication


class AdjudicationTests(unittest.TestCase):
    def test_prepare_adds_all_product_policy_fields(self):
        with tempfile.TemporaryDirectory() as raw_directory:
            directory = Path(raw_directory)
            conflicts = directory / "conflicts.jsonl"
            self._write(
                conflicts,
                [
                    {
                        "id": "one",
                        "text": "Could you send the report?",
                        "language": "en",
                        "unresolvedFields": ["sentiment"],
                    }
                ],
            )
            queue = directory / "queue.jsonl"
            report = adjudication.prepare(
                SimpleNamespace(
                    conflicts=conflicts,
                    queue=queue,
                    chunk_directory=directory / "chunks",
                    chunk_size=10,
                    report=directory / "report.json",
                    include_product_policy_fields=True,
                )
            )

            fields = self._read(queue)[0]["unresolvedFields"]
            self.assertTrue(set(adjudication.PRODUCT_POLICY_FIELDS) <= set(fields))
            self.assertIn("sentiment", fields)
            self.assertTrue(report["includesProductPolicyFields"])

    def test_requires_evidence_from_input_text(self):
        queue = {
            "id": "one",
            "text": "Could you send the report?",
            "unresolvedFields": ["task"],
        }
        record = self._adjudication("one", task="true")
        record["evidence"]["task"] = "not present"

        with self.assertRaisesRegex(ValueError, "exact text quote"):
            adjudication.validate_adjudication(record, queue)

    def test_accepts_matching_high_confidence_adjudication(self):
        report, accepted, excluded, remaining = self._merge(
            first=self._adjudication("one", task="true"),
            second=self._adjudication("one", task="true"),
        )

        self.assertEqual(1, report["acceptedTierCCount"])
        self.assertEqual(0, report["remainingHumanReviewCount"])
        self.assertTrue(accepted[0]["task"])
        self.assertEqual("C", accepted[0]["labelQualityTier"])
        self.assertEqual(0.35, accepted[0]["sampleWeight"])
        self.assertEqual([], excluded)
        self.assertEqual([], remaining)

    def test_keeps_disagreement_for_human_review(self):
        report, accepted, excluded, remaining = self._merge(
            first=self._adjudication("one", task="true"),
            second=self._adjudication("one", task="false"),
        )

        self.assertEqual(0, report["acceptedTierCCount"])
        self.assertEqual([], accepted)
        self.assertEqual([], excluded)
        self.assertEqual(
            ["adjudicator-disagreement"],
            remaining[0]["aiAdjudication"]["rejectedFields"]["task"],
        )

    def test_keeps_low_confidence_for_human_review(self):
        first = self._adjudication("one", task="true")
        first["confidence"]["task"] = 0.89
        report, _, _, remaining = self._merge(
            first=first,
            second=self._adjudication("one", task="true"),
        )

        self.assertEqual(1, report["remainingHumanReviewCount"])
        self.assertEqual(
            ["low-confidence"],
            remaining[0]["aiAdjudication"]["rejectedFields"]["task"],
        )

    def test_excludes_matching_high_confidence_device_command(self):
        first = self._adjudication("one", task="true")
        second = self._adjudication("one", task="true")
        for record in (first, second):
            record["recordDisposition"] = "exclude-device-command"

        report, accepted, excluded, remaining = self._merge(first, second)

        self.assertEqual(1, report["excludedDeviceCommandCount"])
        self.assertEqual([], accepted)
        self.assertEqual("exclude-device-command", excluded[0]["disposition"])
        self.assertEqual([], remaining)

    def test_keeps_disposition_disagreement_for_human_review(self):
        first = self._adjudication("one", task="true")
        second = self._adjudication("one", task="true")
        second["recordDisposition"] = "exclude-device-command"

        report, accepted, excluded, remaining = self._merge(first, second)

        self.assertEqual(1, report["remainingHumanReviewCount"])
        self.assertEqual([], accepted)
        self.assertEqual([], excluded)
        self.assertEqual(
            ["adjudicator-disagreement"],
            remaining[0]["aiAdjudication"]["rejectedFields"][
                "recordDisposition"
            ],
        )

    def test_review_sample_is_unique_and_includes_decision_template(self):
        with tempfile.TemporaryDirectory() as raw_directory:
            directory = Path(raw_directory)
            remaining = directory / "remaining.jsonl"
            records = []
            for index, field in enumerate(("task", "recordDisposition", "task")):
                first = self._adjudication(str(index), task="true")
                second = self._adjudication(str(index), task="false")
                records.append(
                    {
                        "id": str(index),
                        "text": "Could you send the report?",
                        "language": "en" if index % 2 else "zh-Hans",
                        "aiAdjudication": {
                            "rejectedFields": {
                                field: ["adjudicator-disagreement"]
                            },
                            "adjudicatorA": first,
                            "adjudicatorB": second,
                        },
                    }
                )
            self._write(remaining, records)
            sample = directory / "sample.jsonl"
            report = adjudication.review_sample(
                SimpleNamespace(
                    remaining=remaining,
                    sample=sample,
                    sample_size=3,
                    report=directory / "report.json",
                )
            )
            output = self._read(sample)

            self.assertEqual(3, report["sampleCount"])
            self.assertEqual(3, len({record["id"] for record in output}))
            self.assertIsNone(output[0]["humanDecision"].popitem()[1])
            disposition = next(
                record
                for record in output
                if "recordDisposition" in record["fieldReviews"]
            )
            self.assertEqual(
                "keep",
                disposition["fieldReviews"]["recordDisposition"][
                    "adjudicatorA"
                ]["value"],
            )

    def _merge(self, first, second):
        with tempfile.TemporaryDirectory() as raw_directory:
            directory = Path(raw_directory)
            conflicts = directory / "conflicts.jsonl"
            queue = directory / "queue.jsonl"
            first_path = directory / "first.jsonl"
            second_path = directory / "second.jsonl"
            self._write(
                conflicts,
                [
                    {
                        "id": "one",
                        "text": "Could you send the report?",
                        "language": "en",
                        "unresolvedFields": ["task"],
                        "modelVotes": {
                            **{
                                label: {"false": 4}
                                for label in adjudication.INTENT_LABELS
                            },
                            "sentiment": {"neutral": 4},
                        },
                    }
                ],
            )
            self._write(
                queue,
                [
                    {
                        "id": "one",
                        "text": "Could you send the report?",
                        "language": "en",
                        "unresolvedFields": ["task"],
                    }
                ],
            )
            self._write(first_path, [first])
            self._write(second_path, [second])
            accepted_path = directory / "accepted.jsonl"
            excluded_path = directory / "excluded.jsonl"
            remaining_path = directory / "remaining.jsonl"
            report = adjudication.merge(
                SimpleNamespace(
                    conflicts=conflicts,
                    queue=queue,
                    adjudicator_a=[first_path],
                    adjudicator_b=[second_path],
                    adjudicator_a_name="first",
                    adjudicator_b_name="second",
                    minimum_confidence=0.9,
                    accepted=accepted_path,
                    excluded=excluded_path,
                    remaining=remaining_path,
                    report=directory / "report.json",
                )
            )
            return (
                report,
                self._read(accepted_path),
                self._read(excluded_path),
                self._read(remaining_path),
            )

    def _adjudication(self, identifier, task):
        return {
            "id": identifier,
            "recordDisposition": "keep",
            "dispositionConfidence": 0.95,
            "dispositionEvidence": "send the report",
            "resolutions": {"task": task},
            "confidence": {"task": 0.95},
            "evidence": {"task": "send the report"},
        }

    def _write(self, path, records):
        path.write_text(
            "\n".join(json.dumps(record) for record in records) + "\n",
            encoding="utf-8",
        )

    def _read(self, path):
        return [
            json.loads(line)
            for line in path.read_text(encoding="utf-8").splitlines()
            if line
        ]


if __name__ == "__main__":
    unittest.main()
