import json
import sys
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import generate_open_training_corpus as corpus


class OpenTrainingCorpusTests(unittest.TestCase):
    def test_schema_contains_new_intents_and_single_domain(self):
        record = corpus.make_record(
            record_id="one",
            text="Play some jazz",
            language="en",
            family="fixture",
            source_dataset="fixture",
            source_license="CC0-1.0",
            source_url="https://example.test/train",
            source_revision="deadbeef",
            source_split="train",
            known_labels=corpus.known_labels_for_mapping(
                "assistantCommand",
                "media",
            ),
            labeling_method="fixture",
            assistant_command=True,
            domain="media",
        )

        self.assertEqual(
            {"assistantCommand", "informationQuery", "systemNotification"}
            <= set(corpus.INTENT_LABELS),
            True,
        )
        self.assertEqual("media", record["domain"])
        self.assertEqual(
            [
                "assistantCommand",
                "domain",
                "informationQuery",
                "systemNotification",
            ],
            record["knownLabels"],
        )
        self.assertFalse(record["task"])
        self.assertFalse(record["informationQuery"])

    def test_massive_mapping_is_conservative(self):
        self.assertEqual(
            ("assistantCommand", "calendar"),
            corpus.massive_mapping("alarm_set"),
        )
        self.assertEqual(
            ("informationQuery", "generalKnowledge"),
            corpus.massive_mapping("qa_factoid"),
        )
        self.assertEqual(
            ("task", "travel"),
            corpus.massive_mapping("transport_taxi"),
        )
        self.assertEqual((None, None), corpus.massive_mapping("general_greet"))

    def test_bitod_mapping_supports_official_chinese_intents(self):
        self.assertEqual(
            ("informationQuery", "dining"),
            corpus.bitod_mapping("餐馆查询"),
        )
        self.assertEqual(("task", "travel"), corpus.bitod_mapping("宾馆预订"))
        self.assertEqual(
            ("informationQuery", "travel"),
            corpus.bitod_mapping("香港地铁"),
        )
        self.assertEqual(
            ("informationQuery", "weather"),
            corpus.bitod_mapping("天气查询"),
        )

    def test_new_builders_are_pinned_optional_and_isolated(self):
        builders = corpus.configured_source_builders()
        names = {builder.name for builder in builders}

        self.assertTrue(
            {
                "SNIPS",
                "MInDS-14 zh-CN",
                "BiToD",
                "RESTAURANTS-8K",
                "FormosaNLU Synth v1",
            }
            <= names
        )
        self.assertNotIn("CFPB", names)
        self.assertNotIn("CLINC150", names)
        self.assertNotIn("openclaw-zh-greetings", names)
        self.assertNotIn("WeChat-AutoSendBless", names)
        self.assertTrue(all(builder.optional for builder in builders))
        for revision in (
            corpus.SNIPS_REVISION,
            corpus.MINDS14_REVISION,
            corpus.BITOD_REVISION,
            corpus.RESTAURANT8K_REVISION,
            corpus.FORMOSA_NLU_REVISION,
        ):
            self.assertRegex(revision, r"^[0-9a-f]{40}$")

    def test_optional_builder_failure_is_reported_unavailable(self):
        def unavailable(_seed):
            raise corpus.SourceUnavailable("offline")

        sources, failures = corpus.build_available_sources(
            (corpus.SourceBuilder("fixture", unavailable),),
            seed=7,
            allow_unavailable_sources=False,
        )

        self.assertEqual([], sources)
        self.assertEqual("fixture", failures[0]["dataset"])
        self.assertIn("offline", failures[0]["reason"])

    def test_snips_uses_only_official_train_intents(self):
        def payload(url):
            intent = next(
                value for value in corpus.SNIPS_MAPPING if f"/{value}/" in url
            )
            return json.dumps(
                {
                    intent: [
                        {
                            "data": [
                                {"text": "example "},
                                {"text": intent},
                            ]
                        }
                    ]
                }
            ).encode()

        with mock.patch.object(corpus, "fetch_bytes", side_effect=payload):
            records = corpus.snips_records(seed=3)

        self.assertEqual(6, len(records))
        self.assertTrue(all(record["sourceSplit"] == "train" for record in records))
        self.assertTrue(
            all(record["sourceRevision"] == corpus.SNIPS_REVISION for record in records)
        )
        play = next(record for record in records if "PlayMusic" in record["text"])
        self.assertTrue(play["assistantCommand"])
        self.assertEqual("media", play["domain"])

    def test_formosa_synthetic_records_are_simplified_and_keep_low_weight(self):
        payload = (
            json.dumps(
                {
                    "id": "syn-1",
                    "utt": "播放爵士樂",
                    "intent": "play_music",
                }
            )
            + "\n"
        ).encode()
        with mock.patch.object(corpus, "fetch_bytes", return_value=payload):
            records = corpus.formosa_nlu_records(seed=3)

        self.assertEqual(1, len(records))
        self.assertEqual("播放爵士乐", records[0]["text"])
        self.assertEqual("zh-Hans", records[0]["language"])
        self.assertEqual(0.35, records[0]["sampleWeight"])
        self.assertEqual("train", records[0]["sourceSplit"])


if __name__ == "__main__":
    unittest.main()
