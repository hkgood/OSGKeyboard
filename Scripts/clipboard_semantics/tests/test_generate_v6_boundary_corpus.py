import hashlib
import json
import sys
import tempfile
import unicodedata
import unittest
from collections import Counter
from pathlib import Path


sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import generate_v6_boundary_corpus as corpus


REQUIRED_FIELDS = {
    "id",
    "text",
    "language",
    "split",
    "family",
    "task",
    "question",
    "invitation",
    "complaint",
    "scheduleNegotiation",
    "confirmationDecision",
    "followUpReminder",
    "blessing",
    "sentiment",
    "replyable",
    "assistantCommand",
    "informationQuery",
    "systemNotification",
    "domain",
    "sampleWeight",
    "knownLabels",
    "labelingMethod",
    "sourceDataset",
    "sourceLicense",
    "sourceURL",
    "sourceRevision",
    "sourceSplit",
    "synthetic",
    "templateFamily",
}


class V6BoundaryCorpusTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.records, cls.target_counts, cls.excluded = corpus.generate_records()
        cls.payload = corpus.serialize_records(cls.records)

    def test_default_generation_is_reproducible(self):
        records, target_counts, excluded = corpus.generate_records()
        payload = corpus.serialize_records(records)

        self.assertEqual(self.payload, payload)
        self.assertEqual(self.target_counts, target_counts)
        self.assertEqual(self.excluded, excluded)
        self.assertEqual(
            hashlib.sha256(self.payload).hexdigest(),
            hashlib.sha256(payload).hexdigest(),
        )

    def test_default_scale_language_intent_and_domain_balance(self):
        self.assertGreaterEqual(len(self.records), 6_000)
        self.assertEqual(
            {"en": 3_600, "zh-Hans": 3_600},
            Counter(record["language"] for record in self.records),
        )
        for language in corpus.LANGUAGES:
            for intent in corpus.NEW_INTENTS:
                self.assertEqual(
                    1_000,
                    self.target_counts[f"{language}|{intent}"],
                )
            for intent in corpus.HARD_NEGATIVE_INTENTS:
                self.assertEqual(
                    200,
                    self.target_counts[f"{language}|{intent}"],
                )
        self.assertEqual(
            {domain: 600 for domain in corpus.DOMAINS},
            Counter(record["domain"] for record in self.records),
        )

    def test_records_have_full_schema_low_weight_and_known_boundaries(self):
        for record in self.records:
            self.assertEqual(REQUIRED_FIELDS, set(record))
            self.assertEqual(0.35, record["sampleWeight"])
            self.assertEqual("train", record["split"])
            self.assertEqual("train", record["sourceSplit"])
            self.assertEqual(corpus.SOURCE_DATASET, record["sourceDataset"])
            self.assertEqual(corpus.SOURCE_LICENSE, record["sourceLicense"])
            self.assertEqual(corpus.SOURCE_REVISION, record["sourceRevision"])
            self.assertTrue(record["synthetic"])
            self.assertEqual(record["family"], record["templateFamily"])
            self.assertEqual(corpus.KNOWN_LABELS, record["knownLabels"])
            self.assertEqual(record["text"], unicodedata.normalize("NFKC", record["text"]))

            routing_count = sum(record[intent] for intent in corpus.NEW_INTENTS)
            if any(record[intent] for intent in corpus.NEW_INTENTS):
                self.assertEqual(1, routing_count)
                self.assertFalse(record["task"])
                self.assertFalse(record["question"])
                self.assertFalse(record["replyable"])
            else:
                self.assertEqual(0, routing_count)
                self.assertTrue(
                    record["task"] or record["question"] or record["replyable"]
                )

    def test_generated_ids_and_normalized_texts_are_unique(self):
        ids = [record["id"] for record in self.records]
        texts = [corpus.fingerprint(record["text"]) for record in self.records]

        self.assertEqual(len(ids), len(set(ids)))
        self.assertEqual(len(texts), len(set(texts)))

    def test_holdout_discovery_and_nfkc_overlap_exclusion(self):
        system_record = next(
            record
            for record in self.records
            if record["language"] == "zh-Hans"
            and record["systemNotification"]
            and ":" in record["text"]
        )
        blind_record = next(
            record
            for record in self.records
            if record["language"] == "en" and record["informationQuery"]
        )
        with tempfile.TemporaryDirectory() as temporary_directory:
            directory = Path(temporary_directory)
            wildcard_holdout = directory / "frozen-holdout-corpus.jsonl"
            blind_holdout = directory / "product-policy-blind-holdout-v1.jsonl"
            wildcard_holdout.write_text(
                json.dumps(
                    {"text": system_record["text"].replace(":", "：")},
                    ensure_ascii=False,
                )
                + "\n",
                encoding="utf-8",
            )
            blind_holdout.write_text(
                json.dumps({"text": blind_record["text"]}) + "\n",
                encoding="utf-8",
            )

            paths = corpus.discover_holdout_paths(directory)
            holdouts = corpus.load_holdout_fingerprints(paths)
            records, _, excluded = corpus.generate_records(
                holdout_fingerprints=holdouts
            )

        generated = {corpus.fingerprint(record["text"]) for record in records}
        self.assertEqual({wildcard_holdout, blind_holdout}, set(paths))
        self.assertNotIn(corpus.fingerprint(system_record["text"]), generated)
        self.assertNotIn(corpus.fingerprint(blind_record["text"]), generated)
        self.assertGreaterEqual(excluded, 2)
        self.assertEqual(len(self.records), len(records))

    def test_summary_counts_and_hash_match_written_jsonl(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            directory = Path(temporary_directory)
            output = directory / "corpus.jsonl"
            summary_path = directory / "summary.json"

            summary = corpus.write_corpus(
                output,
                summary_path,
                positive_per_intent_language=12,
                negative_per_intent_language=12,
            )
            persisted = json.loads(summary_path.read_text(encoding="utf-8"))
            output_sha256 = hashlib.sha256(output.read_bytes()).hexdigest()

        self.assertEqual(summary, persisted)
        self.assertEqual(output_sha256, summary["corpusSHA256"])
        self.assertEqual(144, summary["recordCount"])
        self.assertEqual(
            {"en": 72, "zh-Hans": 72},
            summary["counts"]["byLanguage"],
        )
        self.assertEqual(48, summary["counts"]["byIntent"]["replyableMessage"])
        self.assertEqual(
            12,
            summary["counts"]["byBoundaryTargetAndLanguage"]["en"][
                "replyableMessage"
            ],
        )
        self.assertEqual(set(corpus.DOMAINS), set(summary["counts"]["byDomain"]))
        self.assertTrue(summary["counts"]["byTemplateFamily"])


if __name__ == "__main__":
    unittest.main()
