import json
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace

import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import generate_consensus_labels as consensus


class ConsensusLabelTests(unittest.TestCase):
    def test_requires_source_support_for_two_of_three_vote(self):
        report, accepted, conflicts = self._merge(
            source_labels={},
            label_sets=[["task"], ["task"], []],
        )

        self.assertEqual([], accepted)
        self.assertEqual("no-supported-consensus", conflicts[0]["rejectedReason"])
        self.assertEqual(1, report["conflictCount"])

    def test_accepts_two_of_three_when_official_label_supports_vote(self):
        report, accepted, conflicts = self._merge(
            source_labels={"task": True},
            label_sets=[["task"], ["task"], []],
        )

        self.assertEqual([], conflicts)
        self.assertEqual("taskOnly", accepted[0]["actionVerifierLabel"])
        self.assertTrue(accepted[0]["task"])
        self.assertEqual(1, report["acceptedCount"])

    def test_rejects_multi_coordination_consensus(self):
        _, accepted, conflicts = self._merge(
            source_labels={"invitation": True, "scheduleNegotiation": True},
            label_sets=[
                ["invitation", "scheduleNegotiation"],
                ["invitation", "scheduleNegotiation"],
                ["invitation", "scheduleNegotiation"],
            ],
        )

        self.assertEqual([], accepted)
        self.assertEqual(
            "multiple-coordination-labels",
            conflicts[0]["rejectedReason"],
        )

    def test_near_duplicate_slot_variants_share_split(self):
        first = {
            "text": "Could you send report 123 before Friday?",
        }
        second = {
            "text": "Could you send report 456 before Friday?",
        }

        self.assertEqual(
            consensus.split_for(first),
            consensus.split_for(second),
        )

    def _merge(self, source_labels, label_sets):
        with tempfile.TemporaryDirectory() as raw_directory:
            directory = Path(raw_directory)
            queue_path = directory / "queue.jsonl"
            self._write_json_lines(
                queue_path,
                [
                    {
                        "id": "record-1",
                        "text": "Could you send the report?",
                        "language": "en",
                        "sourceDataset": "fixture",
                        "sourceLicense": "MIT",
                        "sourceLabels": source_labels,
                    }
                ],
            )
            labelers = []
            for index, labels in enumerate(label_sets):
                path = directory / f"labeler-{index}.jsonl"
                self._write_json_lines(
                    path,
                    [
                        {
                            "id": "record-1",
                            "labels": labels,
                            "ambiguous": False,
                            "quotedOrMeta": False,
                            "confidence": 0.95,
                        }
                    ],
                )
                labelers.append((f"labeler-{index}", path))
            paths = {
                name: directory / f"{name}.jsonl"
                for name in (
                    "consensus",
                    "conflicts",
                    "train",
                    "calibration",
                    "acceptance",
                )
            }
            report_path = directory / "report.json"
            consensus.merge(
                SimpleNamespace(
                    queue=queue_path,
                    labeler=labelers,
                    report=report_path,
                    **paths,
                )
            )
            return (
                json.loads(report_path.read_text(encoding="utf-8")),
                self._read_json_lines(paths["consensus"]),
                self._read_json_lines(paths["conflicts"]),
            )

    def _write_json_lines(self, path, records):
        path.write_text(
            "\n".join(json.dumps(record) for record in records) + "\n",
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
