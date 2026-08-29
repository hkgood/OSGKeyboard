import json
import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import merge_consensus_labels_v2 as consensus


class ConsensusV2Tests(unittest.TestCase):
    def test_primary_unanimous_becomes_tier_a(self):
        report, tier_a, tier_b, human = self._merge(
            primary_states=[self._states(task="true")] * 3,
            review_states=[],
        )

        self.assertEqual(1, report["tierACount"])
        self.assertEqual(1, len(tier_a))
        self.assertTrue(tier_a[0]["task"])
        self.assertEqual(1.0, tier_a[0]["sampleWeight"])
        self.assertEqual([], tier_b)
        self.assertEqual([], human)

    def test_four_of_five_becomes_tier_b(self):
        report, tier_a, tier_b, human = self._merge(
            primary_states=[
                self._states(task="true"),
                self._states(task="true"),
                self._states(task="false"),
            ],
            review_states=[
                self._states(task="true"),
                self._states(task="true"),
            ],
        )

        self.assertEqual(0, report["tierACount"])
        self.assertEqual(1, report["tierBCount"])
        self.assertEqual([], tier_a)
        self.assertTrue(tier_b[0]["task"])
        self.assertEqual(0.65, tier_b[0]["sampleWeight"])
        self.assertEqual([], human)

    def test_three_two_vote_requires_human_review(self):
        report, _, tier_b, human = self._merge(
            primary_states=[
                self._states(task="true"),
                self._states(task="true"),
                self._states(task="false"),
            ],
            review_states=[
                self._states(task="true"),
                self._states(task="false"),
            ],
        )

        self.assertEqual(1, report["humanReviewCount"])
        self.assertEqual([], tier_b)
        self.assertIn("task", human[0]["unresolvedFields"])

    def test_unknown_primary_state_triggers_review(self):
        with tempfile.TemporaryDirectory() as raw_directory:
            directory = Path(raw_directory)
            queue = directory / "queue.jsonl"
            self._write(
                queue,
                [{"id": "record-1", "text": "Hello", "language": "en"}],
            )
            primary = []
            for index, state in enumerate(
                [
                    self._states(question="unknown"),
                    self._states(question="false"),
                    self._states(question="false"),
                ]
            ):
                path = directory / f"primary-{index}.jsonl"
                self._write(path, [self._label("record-1", state)])
                primary.append((f"primary-{index}", path))
            output = directory / "review.jsonl"
            report_path = directory / "report.json"
            report = consensus.prepare_review(
                SimpleNamespace(
                    queue=queue,
                    primary=primary,
                    output=output,
                    report=report_path,
                )
            )

            self.assertEqual(1, report["reviewCount"])
            self.assertEqual("record-1", self._read(output)[0]["id"])

    def test_quoted_positive_is_sent_to_human(self):
        report, _, _, human = self._merge(
            primary_states=[
                self._states(blessing="true"),
                self._states(blessing="true"),
                self._states(blessing="false"),
            ],
            review_states=[
                self._states(blessing="true"),
                self._states(blessing="true"),
            ],
            review_quoted=[True, True],
        )

        self.assertEqual(1, report["humanReviewCount"])
        self.assertIn("quotedOrMeta", human[0]["unresolvedFields"])

    def test_unanimous_unknown_stays_out_of_known_labels(self):
        _, tier_a, _, _ = self._merge(
            primary_states=[self._states(assistantCommand="unknown")] * 3,
            review_states=[],
        )

        self.assertEqual(1, len(tier_a))
        self.assertNotIn("assistantCommand", tier_a[0]["knownLabels"])
        self.assertFalse(tier_a[0]["assistantCommand"])
        self.assertIsNone(tier_a[0]["domain"])

    def test_split_and_combine_preserve_queue_order(self):
        with tempfile.TemporaryDirectory() as raw_directory:
            directory = Path(raw_directory)
            queue_path = directory / "queue.jsonl"
            queue = [
                {"id": f"record-{index}", "text": str(index), "language": "en"}
                for index in range(5)
            ]
            self._write(queue_path, queue)
            chunks = directory / "chunks"
            split_report = consensus.split_queue(
                SimpleNamespace(
                    queue=queue_path,
                    output_directory=chunks,
                    chunk_size=2,
                    report=directory / "split-report.json",
                )
            )
            self.assertEqual(3, split_report["chunkCount"])
            outputs = []
            for path in sorted(chunks.glob("*.jsonl")):
                output_path = directory / f"labeled-{path.name}"
                self._write(
                    output_path,
                    [
                        self._label(record["id"], self._states())
                        for record in self._read(path)
                    ],
                )
                outputs.append(output_path)
            combined_path = directory / "combined.jsonl"
            report = consensus.combine_labeler(
                SimpleNamespace(
                    queue=queue_path,
                    input=outputs,
                    output=combined_path,
                    report=directory / "combine-report.json",
                )
            )

            self.assertEqual(5, report["outputCount"])
            self.assertEqual(
                [record["id"] for record in queue],
                [record["id"] for record in self._read(combined_path)],
            )

    def _merge(
        self,
        primary_states,
        review_states,
        review_quoted=None,
    ):
        review_quoted = review_quoted or [False] * len(review_states)
        with tempfile.TemporaryDirectory() as raw_directory:
            directory = Path(raw_directory)
            queue_path = directory / "queue.jsonl"
            self._write(
                queue_path,
                [
                    {
                        "id": "record-1",
                        "text": "Could you send the report?",
                        "language": "en",
                    }
                ],
            )
            primary = []
            for index, state in enumerate(primary_states):
                path = directory / f"primary-{index}.jsonl"
                self._write(path, [self._label("record-1", state)])
                primary.append((f"primary-{index}", path))
            review = []
            review_required = (
                len(
                    consensus.primary_review_ids(
                        consensus.load_labelers(
                            primary,
                            {"record-1"},
                            True,
                        ),
                        {"record-1"},
                    )
                )
                == 1
            )
            if review_required:
                for index, state in enumerate(review_states):
                    path = directory / f"review-{index}.jsonl"
                    self._write(
                        path,
                        [
                            self._label(
                                "record-1",
                                state,
                                quoted=review_quoted[index],
                            )
                        ],
                    )
                    review.append((f"review-{index}", path))
            else:
                for index in range(2):
                    path = directory / f"review-{index}.jsonl"
                    self._write(path, [])
                    review.append((f"review-{index}", path))
            outputs = {
                name: directory / f"{name}.jsonl"
                for name in ("tier_a", "tier_b", "accepted", "human_review")
            }
            report_path = directory / "report.json"
            report = consensus.merge(
                SimpleNamespace(
                    queue=queue_path,
                    primary=primary,
                    reviewer=review,
                    report=report_path,
                    **outputs,
                )
            )
            return (
                report,
                self._read(outputs["tier_a"]),
                self._read(outputs["tier_b"]),
                self._read(outputs["human_review"]),
            )

    def _states(self, **overrides):
        values = {label: "false" for label in consensus.INTENT_LABELS}
        values.update(overrides)
        values["sentiment"] = overrides.get("sentiment", "neutral")
        values["domain"] = overrides.get("domain", "unknown")
        return values

    def _label(self, identifier, states, quoted=False):
        return {
            "id": identifier,
            "labels": {
                label: states[label] for label in consensus.INTENT_LABELS
            },
            "sentiment": states["sentiment"],
            "domain": states["domain"],
            "ambiguous": False,
            "quotedOrMeta": quoted,
            "confidence": 0.95,
        }

    def _write(self, path, records):
        path.write_text(
            "\n".join(json.dumps(record) for record in records)
            + ("\n" if records else ""),
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
