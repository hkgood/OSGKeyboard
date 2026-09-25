import importlib.util
import unittest
from pathlib import Path


SCRIPT_PATH = (
    Path(__file__).resolve().parents[1] / "prepare_apple_nl_hardening_corpus.py"
)
SPEC = importlib.util.spec_from_file_location("prepare_apple_nl_hardening_corpus", SCRIPT_PATH)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(MODULE)


class PrepareAppleNLHardeningCorpusTests(unittest.TestCase):
    def test_prepare_removes_id_and_normalized_text_overlap(self) -> None:
        training = [
            {"id": "train-1", "text": "Keep me", "language": "en", "split": "train"},
            {"id": "shared-id", "text": "Different", "language": "en", "split": "train"},
            {"id": "train-3", "text": "  SAME   TEXT ", "language": "en", "split": "train"},
        ]
        product = [
            {
                "id": "shared-id",
                "text": "Evaluation by id",
                "language": "en",
                "split": "validation",
            },
            {
                "id": "evaluation-2",
                "text": "same text",
                "language": "en",
                "split": "test",
            },
            {
                "id": "ignored-train",
                "text": "Not evaluation",
                "language": "en",
                "split": "train",
            },
        ]

        records, report = MODULE.prepare(training, product)

        self.assertEqual([record["id"] for record in records], [
            "train-1",
            "shared-id",
            "evaluation-2",
        ])
        self.assertEqual(report["filteredTrainingCount"], 1)
        self.assertEqual(report["excludedTrainingOverlapCount"], 2)
        self.assertEqual(report["evaluationOverlapCount"], 0)

    def test_prepare_requires_evaluation_records(self) -> None:
        with self.assertRaisesRegex(ValueError, "no evaluation records"):
            MODULE.prepare(
                [{"id": "train", "text": "x", "language": "en", "split": "train"}],
                [{"id": "product", "text": "y", "language": "en", "split": "train"}],
            )


if __name__ == "__main__":
    unittest.main()
