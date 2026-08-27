import sys
import unittest
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import run_iterative_retraining as research


class IterativeRetrainingTests(unittest.TestCase):
    def test_defines_exactly_twenty_distinct_rounds(self):
        configurations = research.configurations()

        self.assertEqual(20, len(configurations))
        self.assertEqual(list(range(1, 21)), [value.round for value in configurations])
        self.assertEqual(
            20,
            len(
                {
                    (
                        value.char_min,
                        value.char_max,
                        value.word_max,
                        value.alpha,
                        value.augmentation,
                        value.hard_example_weight,
                    )
                    for value in configurations
                }
            ),
        )

    def test_threshold_selection_prioritizes_precision(self):
        expected = np.array([True, True, False, False], dtype=bool)
        probabilities = np.array([0.99, 0.70, 0.80, 0.10])

        selection = research.select_threshold(
            expected,
            probabilities,
            minimum_predictions=1,
        )

        self.assertGreater(selection["threshold"], 0.80)
        self.assertEqual(1, selection["metrics"]["truePositive"])
        self.assertEqual(0, selection["metrics"]["falsePositive"])

    def test_runtime_requires_explicit_blessing_marker(self):
        records = [
            {"text": "The article quotes best wishes.", "language": "en"},
            {"text": "Best wishes for your new role!", "language": "en"},
        ]
        probabilities = {
            intent: np.array([0.0, 0.0]) for intent in research.INTENTS
        }
        probabilities["blessing"] = np.array([0.99, 0.99])
        thresholds = {
            intent: {"threshold": 0.5, "byLanguage": {}}
            for intent in research.INTENTS
        }

        predicted = research.runtime_predictions(
            records,
            probabilities,
            thresholds,
        )

        self.assertEqual([False, True], predicted["blessing"].tolist())

    def test_runtime_suppresses_implicit_task_when_complaint_is_high(self):
        records = [
            {"text": "This is broken again.", "language": "en"},
            {"text": "This is broken again, please fix it.", "language": "en"},
        ]
        probabilities = {
            intent: np.array([0.0, 0.0]) for intent in research.INTENTS
        }
        probabilities["task"] = np.array([0.99, 0.99])
        probabilities["complaint"] = np.array([0.90, 0.90])
        thresholds = {
            intent: {"threshold": 0.5, "byLanguage": {}}
            for intent in research.INTENTS
        }

        predicted = research.runtime_predictions(
            records,
            probabilities,
            thresholds,
        )

        self.assertEqual([False, True], predicted["task"].tolist())


if __name__ == "__main__":
    unittest.main()
