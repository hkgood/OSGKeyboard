from __future__ import annotations

import importlib.util
import sys
import unittest
from pathlib import Path


SCRIPT_DIRECTORY = Path(__file__).resolve().parent.parent


def load_module(name: str, file_name: str):
    spec = importlib.util.spec_from_file_location(name, SCRIPT_DIRECTORY / file_name)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Unable to load {file_name}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


generator = load_module(
    "generate_blessing_training_corpus",
    "generate_blessing_training_corpus.py",
)
extractor = load_module(
    "extract_lccc_blessing_candidates",
    "extract_lccc_blessing_candidates.py",
)
benchmark_preparer = load_module(
    "prepare_blessing_benchmark",
    "prepare_blessing_benchmark.py",
)
benchmark_finalizer = load_module(
    "finalize_blessing_benchmark",
    "finalize_blessing_benchmark.py",
)


class BlessingCorpusGeneratorTests(unittest.TestCase):
    def test_targets_are_balanced_per_language(self) -> None:
        targets = generator.allocate_targets(generator.ZH_FAMILIES, 10_000)
        positive = sum(
            targets[family.name]
            for family in generator.ZH_FAMILIES
            if family.blessing
        )
        negative = sum(
            targets[family.name]
            for family in generator.ZH_FAMILIES
            if not family.blessing
        )

        self.assertEqual(positive, 5_000)
        self.assertEqual(negative, 5_000)

    def test_generation_is_unique_and_partial_label_only(self) -> None:
        records = generator.generate_language(
            language="zh-Hans",
            common_slots=generator.ZH_COMMON,
            families=generator.ZH_FAMILIES,
            target=1_000,
            seed=generator.SEED,
            reserved=set(),
        )

        self.assertEqual(len(records), 1_000)
        self.assertEqual(
            len({generator.fingerprint(record["text"]) for record in records}),
            1_000,
        )
        self.assertTrue(
            all(record["knownLabels"] == ["blessing"] for record in records)
        )
        self.assertEqual(sum(record["blessing"] for record in records), 500)


class LCCCBlessingCandidateTests(unittest.TestCase):
    def test_direct_wishes_are_positive(self) -> None:
        self.assertEqual(
            extractor.classify("祝你生日快乐，愿新的一岁平安顺利"),
            ("positive", "direct_wish"),
        )
        self.assertEqual(
            extractor.classify("恭喜你顺利毕业"),
            ("positive", "congratulation"),
        )

    def test_boundaries_are_negative(self) -> None:
        self.assertEqual(
            extractor.classify("帮我写一段生日祝福语"),
            ("negative", "meta_request"),
        )
        self.assertEqual(
            extractor.classify("谢谢大家发来的生日祝福"),
            ("negative", "received_thanks"),
        )
        self.assertEqual(
            extractor.classify("我们晚上一起庆祝项目上线"),
            ("negative", "celebration_mention"),
        )
        self.assertEqual(
            extractor.classify("晚上好"),
            ("negative", "plain_greeting"),
        )

    def test_question_is_not_promoted_to_direct_wish(self) -> None:
        self.assertEqual(
            extractor.classify("可以对我说一句生日快乐吗？"),
            ("negative", "meta_request"),
        )


class BlessingBenchmarkTests(unittest.TestCase):
    def test_selection_prioritizes_boundary_before_explicit_marker(self) -> None:
        record = {
            "text": "文档引用了“祝你生日快乐”作为写作示例。",
            "blessing": False,
            "sentiment": "neutral",
        }

        self.assertEqual(
            benchmark_preparer.selection_stratum(record),
            "boundary_candidate",
        )

    def test_selection_includes_implicit_positive_language(self) -> None:
        record = {
            "text": "I hope you continue to know peace and happiness.",
            "blessing": False,
            "sentiment": "positive",
        }

        self.assertEqual(
            benchmark_preparer.selection_stratum(record),
            "explicit_candidate",
        )

    def test_benchmark_split_is_deterministic(self) -> None:
        first = benchmark_finalizer.benchmark_split("blessing-review-00042")
        second = benchmark_finalizer.benchmark_split("blessing-review-00042")

        self.assertEqual(first, second)
        self.assertIn(first, {"calibration", "test"})

    def test_binary_kappa_reports_partial_agreement(self) -> None:
        annotation_a = {
            "1": {"label": True},
            "2": {"label": True},
            "3": {"label": False},
            "4": {"label": False},
        }
        annotation_b = {
            "1": {"label": True},
            "2": {"label": False},
            "3": {"label": False},
            "4": {"label": False},
        }

        agreement, kappa = benchmark_finalizer.binary_cohen_kappa(
            annotation_a,
            annotation_b,
        )

        self.assertEqual(agreement, 0.75)
        self.assertEqual(kappa, 0.5)


if __name__ == "__main__":
    unittest.main()
