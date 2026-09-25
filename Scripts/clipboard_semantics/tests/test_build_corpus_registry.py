import json
import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import build_corpus_registry as registry


class CorpusRegistryTests(unittest.TestCase):
    def test_evaluation_overlap_blocks_training(self):
        report, records, train, _, _ = self._build(
            train_records=[
                self._record("train-1", "Send report 123", "train", task=True)
            ],
            evaluation_records=[
                self._record("eval-1", "Send report 123", "test", task=True)
            ],
        )

        self.assertEqual(1, report["canonicalRecordCount"])
        self.assertEqual("evaluation-only", records[0]["allowedUse"])
        self.assertEqual([], train)
        self.assertEqual(1, report["exactDuplicateCount"])

    def test_unknown_labels_remain_unknown(self):
        report, records, train, pilot, _ = self._build(
            train_records=[
                {
                    **self._record(
                        "open-1",
                        "Could you send the report?",
                        "train",
                        task=True,
                    ),
                    "knownLabels": ["task"],
                }
            ],
            all_intents_known=False,
        )

        self.assertEqual(1, report["trainCandidateCount"])
        self.assertEqual("true", records[0]["labels"]["task"])
        self.assertEqual("unknown", records[0]["labels"]["question"])
        self.assertEqual("unknown", records[0]["labels"]["assistantCommand"])
        self.assertEqual(1, len(train))
        self.assertEqual(1, len(pilot))

    def test_domain_only_record_and_weight_reach_training_output(self):
        report, records, train, _, _ = self._build(
            train_records=[
                {
                    **self._record("domain-1", "Table for five", "train", task=False),
                    "domain": "dining",
                    "knownLabels": ["domain"],
                    "sampleWeight": 0.5,
                }
            ],
            all_intents_known=False,
            source_weight=0.7,
        )

        self.assertEqual(1, report["trainCandidateCount"])
        self.assertEqual("dining", records[0]["domain"])
        self.assertEqual(["domain"], train[0]["knownLabels"])
        self.assertEqual(0.35, train[0]["sampleWeight"])

    def test_conflicting_source_labels_enter_human_review(self):
        _, records, train, _, review = self._build(
            train_records=[
                self._record("one", "Please send it.", "train", task=True),
                self._record("two", "Please send it.", "train", task=False),
            ],
        )

        self.assertEqual(["task"], records[0]["labelConflicts"])
        self.assertEqual([], train)
        self.assertEqual(["task"], review[0]["conflicts"])

    def test_rejects_unsafe_training_license(self):
        report, records, train, pilot, _ = self._build(
            train_records=[
                self._record("unsafe", "Research dialogue", "train", task=True)
            ],
            train_license="research-only",
        )

        self.assertEqual(0, report["canonicalRecordCount"])
        self.assertEqual({"unsafe-license": 1}, report["excludedRecordCounts"])
        self.assertEqual([], records)
        self.assertEqual([], train)
        self.assertEqual([], pilot)

    def test_pilot_uses_unique_clusters(self):
        records = [
            self._record(
                f"record-{index}",
                f"Could you send report {index} before Friday?",
                "train",
                task=True,
            )
            for index in range(4)
        ]
        _, _, _, pilot, _ = self._build(
            train_records=records,
            pilot_count=10,
        )

        self.assertEqual(1, len(pilot))

    def _build(
        self,
        train_records,
        evaluation_records=None,
        all_intents_known=True,
        train_license="MIT",
        pilot_count=10,
        source_weight=1.0,
    ):
        evaluation_records = evaluation_records or []
        with tempfile.TemporaryDirectory() as raw_directory:
            directory = Path(raw_directory)
            train_path = directory / "train.jsonl"
            evaluation_path = directory / "evaluation.jsonl"
            self._write_json_lines(train_path, train_records)
            self._write_json_lines(evaluation_path, evaluation_records)
            manifest_path = directory / "sources.json"
            manifest_path.write_text(
                json.dumps(
                    {
                        "schemaVersion": 1,
                        "sources": [
                            {
                                "id": "train",
                                "path": str(train_path),
                                "license": train_license,
                                "defaultUse": "train",
                                "sourceType": "fixture",
                                "allIntentLabelsKnown": all_intents_known,
                                "sentimentKnown": False,
                                "weight": source_weight,
                                "required": True,
                            },
                            {
                                "id": "evaluation",
                                "path": str(evaluation_path),
                                "license": "evaluation-only",
                                "defaultUse": "evaluation-only",
                                "sourceType": "fixture",
                                "allIntentLabelsKnown": True,
                                "sentimentKnown": False,
                                "required": True,
                            },
                        ],
                        "excludedSources": [],
                    }
                ),
                encoding="utf-8",
            )
            paths = {
                name: directory / f"{name}.jsonl"
                for name in (
                    "registry",
                    "train_candidates",
                    "pilot",
                    "human_review",
                )
            }
            report_path = directory / "report.json"
            report = registry.build(
                SimpleNamespace(
                    repository_root=directory,
                    source_manifest=manifest_path,
                    report=report_path,
                    pilot_count=pilot_count,
                    **paths,
                )
            )
            return (
                report,
                self._read_json_lines(paths["registry"]),
                self._read_json_lines(paths["train_candidates"]),
                self._read_json_lines(paths["pilot"]),
                self._read_json_lines(paths["human_review"]),
            )

    def _record(self, identifier, text, split, task):
        return {
            "id": identifier,
            "text": text,
            "language": "en",
            "family": "fixture",
            "split": split,
            "task": task,
        }

    def _write_json_lines(self, path, records):
        path.write_text(
            "\n".join(json.dumps(record) for record in records)
            + ("\n" if records else ""),
            encoding="utf-8",
        )

    def _read_json_lines(self, path):
        return [
            json.loads(line)
            for line in path.read_text(encoding="utf-8").splitlines()
            if line
        ]


if __name__ == "__main__":
    unittest.main()
