import json
import sys
import tempfile
import unittest
from pathlib import Path


sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import assemble_v6_model_corpus as corpus


class AssembleV6ModelCorpusTests(unittest.TestCase):
    def write_jsonl(self, path: Path, records: list[dict]) -> None:
        path.write_text(
            "".join(json.dumps(record) + "\n" for record in records),
            encoding="utf-8",
        )

    def test_assembles_disjoint_train_and_evaluation_splits(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            train = root / "train.jsonl"
            evaluation = root / "evaluation.jsonl"
            self.write_jsonl(
                train,
                [{"id": "train-1", "text": "hello", "split": "train", "language": "en"}],
            )
            self.write_jsonl(
                evaluation,
                [
                    {
                        "id": "test-1",
                        "text": "world",
                        "split": "test",
                        "language": "en",
                    }
                ],
            )

            records, report = corpus.assemble(train, evaluation)

        self.assertEqual(2, len(records))
        self.assertEqual({"test": 1, "train": 1}, report["splitCounts"])
        self.assertEqual(0, report["evaluationOverlapCount"])

    def test_rejects_nfkc_casefold_overlap(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            train = root / "train.jsonl"
            evaluation = root / "evaluation.jsonl"
            self.write_jsonl(
                train,
                [{"id": "train-1", "text": "ＡＢＣ", "split": "train", "language": "en"}],
            )
            self.write_jsonl(
                evaluation,
                [{"id": "test-1", "text": "abc", "split": "test", "language": "en"}],
            )

            with self.assertRaisesRegex(ValueError, "overlap"):
                corpus.assemble(train, evaluation)


if __name__ == "__main__":
    unittest.main()
