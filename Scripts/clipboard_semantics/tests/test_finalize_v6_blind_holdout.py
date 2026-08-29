from __future__ import annotations

import sys
import unittest
from pathlib import Path


sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import finalize_v6_blind_holdout as finalizer


class FinalizeV6BlindHoldoutTests(unittest.TestCase):
    def test_review_accepts_each_high_confidence_field_independently(self):
        primary = self._labelers(
            "primary",
            [
                self._states(task="true", question="true", domain="finance"),
                self._states(task="true", question="true", domain="travel"),
                self._states(task="true", question="false", domain="calendar"),
            ],
        )
        reviewers = self._labelers(
            "reviewer",
            [
                self._states(task="true", question="true", domain="finance"),
                self._states(task="false", question="false", domain="travel"),
            ],
        )

        states = finalizer.resolve_model_states(
            "record-1",
            primary,
            reviewers,
            in_review_queue=True,
        )
        output = finalizer.output_record(
            {"id": "record-1", "text": "Text", "language": "en"},
            states,
            "test",
        )

        self.assertEqual("true", states["task"])
        self.assertEqual("unknown", states["question"])
        self.assertEqual("unknown", states["domain"])
        self.assertTrue(output["task"])
        self.assertIn("task", output["knownLabels"])
        self.assertNotIn("question", output["knownLabels"])
        self.assertNotIn("domain", output["knownLabels"])
        self.assertIsNone(output["domain"])

    def test_human_fields_override_models_but_exclusion_infers_nothing(self):
        model_states = self._states(
            task="false",
            question="false",
            replyableMessage="false",
        )
        overrides = finalizer.apply_human_overrides(
            model_states,
            {
                "recordDisposition": "keep",
                "task": "true",
                "question": "unknown",
                "replyableMessage": "true",
                "ambiguous": "false",
            },
        )

        self.assertEqual(
            ["task", "question", "replyableMessage", "ambiguous"],
            overrides,
        )
        self.assertEqual("true", model_states["task"])
        self.assertEqual("unknown", model_states["question"])
        self.assertEqual("true", model_states["replyableMessage"])

        excluded_states = self._states(task="true")
        excluded_overrides = finalizer.apply_human_overrides(
            excluded_states,
            {"recordDisposition": "exclude-device-command"},
        )
        self.assertEqual([], excluded_overrides)
        self.assertEqual("true", excluded_states["task"])

    def test_split_assigns_twenty_of_each_kind_per_language(self):
        records = [
            {
                "id": f"{language}-{index:03d}",
                "text": f"{language} {index}",
                "language": language,
            }
            for language in ("en", "zh-Hans")
            for index in range(60)
        ]

        assignments = finalizer.assign_splits(records, records_per_split=20)

        for language in ("en", "zh-Hans"):
            counts = {
                split: sum(
                    assignments[f"{language}-{index:03d}"] == split
                    for index in range(60)
                )
                for split in finalizer.SPLITS
            }
            self.assertEqual(
                {"validation": 20, "test": 20, "golden": 20},
                counts,
            )
        self.assertEqual("validation", assignments["en-000"])
        self.assertEqual("test", assignments["en-020"])
        self.assertEqual("golden", assignments["en-040"])

    def test_unknown_fields_are_not_known_or_positive(self):
        states = self._states(
            assistantCommand="unknown",
            sentiment="unknown",
            domain="unknown",
        )
        states["ambiguous"] = "unknown"

        output = finalizer.output_record(
            {"id": "record-1", "text": "unchanged", "language": "en"},
            states,
            "golden",
        )

        self.assertFalse(output["assistantCommand"])
        self.assertEqual("neutral", output["sentiment"])
        self.assertIsNone(output["domain"])
        self.assertIsNone(output["ambiguous"])
        self.assertNotIn("assistantCommand", output["knownLabels"])
        self.assertNotIn("sentiment", output["knownLabels"])
        self.assertNotIn("domain", output["knownLabels"])
        self.assertNotEqual("train", output["split"])
        self.assertEqual("unchanged", output["text"])

    def test_unreviewed_field_requires_unanimous_non_unknown_vote(self):
        primary = self._labelers(
            "primary",
            [
                self._states(blessing="unknown"),
                self._states(blessing="unknown"),
                self._states(blessing="unknown"),
            ],
        )

        states = finalizer.resolve_model_states(
            "record-1",
            primary,
            [],
            in_review_queue=False,
        )

        self.assertEqual("unknown", states["blessing"])
        self.assertEqual("false", states["task"])

    def test_duplicate_ids_are_rejected(self):
        with self.assertRaisesRegex(ValueError, "duplicate id"):
            finalizer.unique_records(
                [{"id": "same"}, {"id": "same"}],
                "test input",
            )

    def _states(self, **overrides):
        states = {field: "false" for field in finalizer.INTENT_LABELS}
        states["sentiment"] = "neutral"
        states["domain"] = "unknown"
        states["ambiguous"] = "false"
        states.update(overrides)
        return states

    def _labelers(self, prefix, states):
        return [
            (f"{prefix}-{index}", {"record-1": state})
            for index, state in enumerate(states)
        ]


if __name__ == "__main__":
    unittest.main()
