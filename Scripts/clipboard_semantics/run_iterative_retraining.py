#!/usr/bin/env python3
"""Run twenty deterministic weakly supervised clipboard-intent research rounds.

This Linux-compatible harness is a model-selection surrogate. It never replaces
the Apple Create ML artifacts: the selected data policy must be replayed by
`train_models.swift` on macOS before a deployable candidate exists.
"""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
import math
import re
import time
from collections import defaultdict, deque
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any

import numpy as np
from scipy import sparse
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.linear_model import SGDClassifier
from sklearn.pipeline import FeatureUnion

SEED = 20260827
INTENTS = (
    "task",
    "question",
    "invitation",
    "complaint",
    "scheduleNegotiation",
    "confirmationDecision",
    "followUpReminder",
    "blessing",
    "replyableMessage",
    "assistantCommand",
    "informationQuery",
    "systemNotification",
)
LEGACY_IMPLICITLY_KNOWN_INTENTS = frozenset(INTENTS[:9])
OUTPUT_DIRECTORY = Path("ModelTraining/ClipboardSemantics/IterativeResearch")
BASE_CORPUS = Path(
    "ModelTraining/ClipboardSemantics/clipboard_semantic_corpus.jsonl"
)
OPEN_CORPUS = Path("ModelTraining/ClipboardSemantics/open-training-corpus.jsonl")
RANDOM_HOLDOUT = Path(
    "ModelTraining/ClipboardSemantics/random-holdout-corpus.jsonl"
)
TARGETED_HOLDOUT = Path(
    "ModelTraining/ClipboardSemantics/targeted-release-holdout-corpus.jsonl"
)
COMPREHENSIVE_HOLDOUT = Path(
    "ModelTraining/ClipboardSemantics/comprehensive-online-holdout-corpus.jsonl"
)

EXPLICIT_TASK_MARKERS = (
    "请",
    "麻烦",
    "能否",
    "可以请你",
    "由你",
    "交给你",
    "需要你",
    "你负责",
    "下一步",
    "行动项",
    "please ",
    "can you",
    "could you",
    "would you",
    "assigned to you",
    "you are responsible",
    "we need you",
    "would like you",
    "counting on you",
    "take ownership",
    "your task",
    "next action",
    "complete the",
    "finish the",
    "send it to",
    "deliver it to",
)
BLESSING_MARKERS = (
    "生日快乐",
    "新年快乐",
    "春节快乐",
    "节日快乐",
    "圣诞快乐",
    "中秋快乐",
    "恭喜",
    "预祝",
    "祝你",
    "祝您",
    "祝大家",
    "祝他",
    "祝她",
    "愿你",
    "愿您",
    "happy birthday",
    "happy new year",
    "merry christmas",
    "happy holidays",
    "congratulations",
    "congrats",
    "best wishes",
    "good luck",
    "wishing you",
    "wish you",
    "wish him",
    "wish her",
    "wish them",
    "let us wish",
    "let's wish",
    "we wish",
    "may you",
)
BLESSING_EXCLUSIONS = (
    "祝福模板",
    "祝福语模板",
    "文章引用",
    "搜索词",
    "文档里收录",
    "贺卡名单",
    "收集祝福",
    "greeting template",
    "message template",
    "the article quotes",
    "search phrase",
    "document contains",
    "quotes the phrase",
    "如何描述生日快乐",
    "怎么说生日快乐",
    "如何写生日祝福",
    "how would you describe a happy birthday",
    "how do you say happy birthday",
    "what does happy birthday mean",
    "宁愿你",
    "祝你倒闭",
    "祝你去死",
    "祝你倒霉",
    "祝你失败",
    "祝你完蛋",
)
QUESTION_PATTERN = re.compile(
    r"(?:[?？]|^(?:who|what|when|where|why|how|which|do|does|did|can|could|"
    r"would|will|is|are|was|were|have|has|should)\b|"
    r"(?:谁|什么|何时|哪里|为什么|怎么|如何|哪个|哪种|是否|能否|吗|么|呢|几))",
    re.IGNORECASE,
)
INVITATION_PATTERN = re.compile(
    r"(?:\b(?:join us|come (?:to|over)|you(?:'re| are) invited|"
    r"would love (?:you|for you)|invitation|party|dinner together)\b|"
    r"(?:邀请|一起来|一起去|来我家|参加.+(?:聚会|晚餐|活动)|聚个|吃饭吧))",
    re.IGNORECASE,
)
COMPLAINT_PATTERN = re.compile(
    r"(?:\b(?:broken|not working|doesn['’]?t work|failed|failure|crash(?:ed|es)?|"
    r"refund|charged|unacceptable|terrible|worst|frustrat(?:ed|ing)|"
    r"disappoint(?:ed|ing)|still can['’]?t|never received)\b|"
    r"(?:坏了|不能用|无法|失败|崩溃|退款|扣费|太差|糟糕|失望|一直没有|"
    r"仍然没有|延迟|投诉|没人回复|没有回复))",
    re.IGNORECASE,
)
SCHEDULE_PATTERN = re.compile(
    r"(?:\b(?:reschedule|move (?:it|the)|instead|work better|available|"
    r"does .+ work|or .+(?:morning|afternoon|evening|am|pm))\b|"
    r"(?:改到|改成|改期|还是|哪个时间|哪天|方便吗|可以吗|不行.+(?:周|点|号)))",
    re.IGNORECASE,
)
CONFIRMATION_PATTERN = re.compile(
    r"(?:\b(?:approve|approved|confirm|confirmed|accept|accepted|reject|"
    r"rejected|choose|chosen|selected|agreed|proceed with|go with)\b|"
    r"(?:确认|同意|批准|接受|拒绝|选择|采用|就按|决定用|没问题.+执行))",
    re.IGNORECASE,
)
FOLLOW_UP_PATTERN = re.compile(
    r"(?:\b(?:follow up|follow-up|check back|remind me|reminder|circle back|"
    r"after .+(?:ships|arrives|responds)|if .+(?:no response|haven['’]?t heard))\b|"
    r"(?:跟进|提醒我|提醒一下|稍后再|之后再|如果.+(?:没|没有).+再))",
    re.IGNORECASE,
)


@dataclass(frozen=True)
class RoundConfiguration:
    round: int
    char_min: int
    char_max: int
    word_max: int
    min_df: int
    max_char_features: int
    max_word_features: int
    alpha: float
    l1_ratio: float
    hard_example_weight: float
    augmentation: str
    external_weight: float
    pseudo_weight: float


@dataclass
class BinaryCounts:
    true_positive: int = 0
    true_negative: int = 0
    false_positive: int = 0
    false_negative: int = 0

    def update(self, expected: np.ndarray, predicted: np.ndarray) -> None:
        self.true_positive += int(np.sum(expected & predicted))
        self.true_negative += int(np.sum(~expected & ~predicted))
        self.false_positive += int(np.sum(~expected & predicted))
        self.false_negative += int(np.sum(expected & ~predicted))

    def metrics(self) -> dict[str, float | int]:
        predicted_positive = self.true_positive + self.false_positive
        actual_positive = self.true_positive + self.false_negative
        total = predicted_positive + self.true_negative + self.false_negative
        precision = (
            self.true_positive / predicted_positive if predicted_positive else 0
        )
        recall = self.true_positive / actual_positive if actual_positive else 0
        f1 = (
            2 * precision * recall / (precision + recall)
            if precision + recall
            else 0
        )
        return {
            "total": total,
            "truePositive": self.true_positive,
            "trueNegative": self.true_negative,
            "falsePositive": self.false_positive,
            "falseNegative": self.false_negative,
            "predictedPositive": predicted_positive,
            "precision": rounded(precision),
            "recall": rounded(recall),
            "f1": rounded(f1),
            "wilsonPrecisionLower95": wilson_lower(
                self.true_positive, predicted_positive
            ),
        }


def rounded(value: float) -> float:
    if not math.isfinite(value):
        return 0
    return round(float(value), 4)


def wilson_lower(successes: int, total: int) -> float:
    if total == 0:
        return 0
    z = 1.959963984540054
    proportion = successes / total
    denominator = 1 + z * z / total
    center = proportion + z * z / (2 * total)
    adjustment = z * math.sqrt(
        (proportion * (1 - proportion) + z * z / (4 * total)) / total
    )
    return rounded((center - adjustment) / denominator)


def read_json_lines(path: Path) -> list[dict[str, Any]]:
    if not path.is_file():
        return []
    return [
        json.loads(line)
        for line in path.read_text(encoding="utf-8").splitlines()
        if line.strip()
    ]


def stable_value(value: str) -> int:
    return int.from_bytes(hashlib.sha256(value.encode()).digest()[:8], "big")


def record_label(record: dict[str, Any], intent: str) -> bool:
    key = "replyable" if intent == "replyableMessage" else intent
    return bool(record.get(key, False))


def is_known(record: dict[str, Any], intent: str) -> bool:
    known = record.get("knownLabels")
    if known is None:
        return intent in LEGACY_IMPLICITLY_KNOWN_INTENTS
    return intent in known or (
        intent == "replyableMessage" and "replyable" in known
    )


def has_explicit_blessing(text: str) -> bool:
    normalized = text.casefold()
    return not any(value in normalized for value in BLESSING_EXCLUSIONS) and any(
        value in normalized for value in BLESSING_MARKERS
    )


def has_explicit_task(text: str) -> bool:
    normalized = text.casefold()
    return any(value in normalized for value in EXPLICIT_TASK_MARKERS)


def has_explicit_evidence(intent: str, text: str) -> bool:
    if intent == "task":
        return has_explicit_task(text)
    if intent == "question":
        return bool(QUESTION_PATTERN.search(text.strip()))
    if intent == "invitation":
        return bool(INVITATION_PATTERN.search(text))
    if intent == "complaint":
        return bool(COMPLAINT_PATTERN.search(text))
    if intent == "scheduleNegotiation":
        return bool(SCHEDULE_PATTERN.search(text))
    if intent == "confirmationDecision":
        return bool(CONFIRMATION_PATTERN.search(text))
    if intent == "followUpReminder":
        return bool(FOLLOW_UP_PATTERN.search(text))
    if intent == "blessing":
        return has_explicit_blessing(text)
    return True


def configurations() -> list[RoundConfiguration]:
    axes = [
        (2, 5, 2, 2, 45_000, 22_000, 2.0e-5, 0.00, 1.0, "none"),
        (3, 5, 2, 2, 50_000, 25_000, 1.5e-5, 0.00, 1.0, "none"),
        (2, 6, 2, 2, 55_000, 25_000, 1.0e-5, 0.05, 1.2, "none"),
        (3, 6, 3, 2, 60_000, 30_000, 8.0e-6, 0.05, 1.2, "none"),
        (2, 5, 3, 1, 60_000, 32_000, 1.2e-5, 0.10, 1.4, "none"),
        (2, 6, 2, 2, 65_000, 28_000, 8.0e-6, 0.10, 1.5, "punctuation"),
        (3, 6, 3, 2, 65_000, 32_000, 6.0e-6, 0.10, 1.5, "punctuation"),
        (2, 7, 2, 2, 70_000, 28_000, 5.0e-6, 0.15, 1.7, "punctuation"),
        (3, 7, 3, 2, 70_000, 35_000, 4.0e-6, 0.15, 1.7, "punctuation"),
        (2, 6, 3, 1, 75_000, 38_000, 6.0e-6, 0.20, 1.8, "punctuation"),
        (2, 6, 2, 2, 70_000, 30_000, 5.0e-6, 0.10, 1.8, "prefix"),
        (3, 6, 3, 2, 75_000, 35_000, 4.0e-6, 0.15, 2.0, "prefix"),
        (2, 7, 3, 2, 80_000, 38_000, 3.0e-6, 0.15, 2.0, "prefix"),
        (3, 7, 3, 1, 80_000, 40_000, 2.5e-6, 0.20, 2.2, "prefix"),
        (2, 6, 3, 1, 85_000, 42_000, 3.5e-6, 0.20, 2.2, "prefix"),
        (2, 7, 3, 2, 80_000, 38_000, 3.0e-6, 0.15, 2.3, "numeric"),
        (3, 7, 3, 1, 85_000, 42_000, 2.0e-6, 0.20, 2.5, "numeric"),
        (2, 8, 3, 1, 90_000, 45_000, 1.5e-6, 0.20, 2.5, "numeric"),
        (3, 8, 3, 1, 95_000, 45_000, 1.2e-6, 0.25, 2.7, "numeric"),
        (2, 8, 3, 1, 100_000, 50_000, 1.0e-6, 0.25, 3.0, "numeric"),
    ]
    return [
        RoundConfiguration(
            round=index,
            char_min=values[0],
            char_max=values[1],
            word_max=values[2],
            min_df=values[3],
            max_char_features=values[4],
            max_word_features=values[5],
            alpha=values[6],
            l1_ratio=values[7],
            hard_example_weight=values[8],
            augmentation=values[9],
            external_weight=min(1.0, 0.55 + index * 0.02),
            pseudo_weight=min(0.45, 0.15 + index * 0.015),
        )
        for index, values in enumerate(axes, start=1)
    ]


def augmented_text(text: str, mode: str) -> str:
    if mode == "none":
        return text
    if mode == "punctuation":
        return re.sub(r"[!?！？。，、；;:：]+", " ", text).strip()
    if mode == "prefix":
        return re.sub(
            r"^(?:hey|hi|hello|please note that|顺便问下|你好|您好|那个|嗯)[,，:： ]*",
            "",
            text,
            flags=re.IGNORECASE,
        ).strip()
    if mode == "numeric":
        return re.sub(r"\d+(?::\d+)?", "<num>", text).casefold().strip()
    return text


def augmented_records(
    records: list[dict[str, Any]],
    configuration: RoundConfiguration,
) -> list[dict[str, Any]]:
    if configuration.augmentation == "none":
        return []
    result = []
    for record in records:
        if stable_value(
            f"{configuration.round}|augment|{record['id']}"
        ) % 4:
            continue
        transformed = augmented_text(
            record["text"], configuration.augmentation
        )
        if not transformed or transformed == record["text"]:
            continue
        value = copy.copy(record)
        value["id"] = f"round-{configuration.round}-aug-{record['id']}"
        value["text"] = transformed
        value["sourceDataset"] = "deterministic-label-preserving-augmentation"
        value["_augmentation"] = True
        result.append(value)
    return result


def vectorizer(configuration: RoundConfiguration) -> FeatureUnion:
    return FeatureUnion(
        [
            (
                "char",
                TfidfVectorizer(
                    analyzer="char_wb",
                    ngram_range=(
                        configuration.char_min,
                        configuration.char_max,
                    ),
                    min_df=configuration.min_df,
                    max_features=configuration.max_char_features,
                    sublinear_tf=True,
                    lowercase=True,
                    dtype=np.float32,
                ),
            ),
            (
                "word",
                TfidfVectorizer(
                    analyzer="word",
                    ngram_range=(1, configuration.word_max),
                    token_pattern=r"(?u)\b\w+\b",
                    min_df=configuration.min_df,
                    max_features=configuration.max_word_features,
                    sublinear_tf=True,
                    lowercase=True,
                    strip_accents="unicode",
                    dtype=np.float32,
                ),
            ),
        ]
    )


def sample_weight(
    record: dict[str, Any],
    configuration: RoundConfiguration,
) -> float:
    weight = 1.0
    if record.get("knownLabels") is not None:
        weight *= configuration.external_weight
    weight *= float(record.get("sampleWeight", 1.0))
    if record.get("_augmentation"):
        weight *= 0.60
    family = str(record.get("family", "")).casefold()
    positive_count = sum(record_label(record, intent) for intent in INTENTS)
    if "boundary" in family or positive_count > 1:
        weight *= configuration.hard_example_weight
    return weight


def select_threshold(
    expected: np.ndarray,
    probabilities: np.ndarray,
    *,
    minimum_precision: float = 0.95,
    minimum_predictions: int = 10,
) -> dict[str, Any]:
    options = []
    for threshold in np.linspace(0.50, 0.995, 100):
        predicted = probabilities >= threshold
        counts = BinaryCounts()
        counts.update(expected, predicted)
        metrics = counts.metrics()
        if (
            metrics["precision"] >= minimum_precision
            and metrics["predictedPositive"] >= minimum_predictions
        ):
            options.append((metrics["recall"], metrics["precision"], -threshold, metrics))
    if not options:
        return {
            "threshold": 1.0,
            "metrics": BinaryCounts().metrics(),
            "abstained": True,
        }
    recall, _, negative_threshold, metrics = max(options)
    del recall
    return {
        "threshold": rounded(-negative_threshold),
        "metrics": metrics,
        "abstained": False,
    }


def calibrated_thresholds(
    records: list[dict[str, Any]],
    probabilities: dict[str, np.ndarray],
) -> dict[str, dict[str, Any]]:
    languages = np.array([record["language"] for record in records])
    result: dict[str, dict[str, Any]] = {}
    for intent in INTENTS:
        known_mask = np.array(
            [is_known(record, intent) for record in records],
            dtype=bool,
        )
        expected = np.array(
            [record_label(record, intent) for record in records], dtype=bool
        )
        selection = select_threshold(
            expected[known_mask],
            probabilities[intent][known_mask],
        )
        by_language = {}
        for language in sorted(set(languages)):
            mask = (languages == language) & known_mask
            positives = int(np.sum(expected[mask]))
            negatives = int(np.sum(~expected[mask]))
            if positives < 20 or negatives < 20:
                continue
            by_language[language] = select_threshold(
                expected[mask],
                probabilities[intent][mask],
                minimum_predictions=8,
            )
        result[intent] = {
            **selection,
            "byLanguage": by_language,
        }
    return result


def thresholds_for_records(
    records: list[dict[str, Any]],
    intent: str,
    thresholds: dict[str, dict[str, Any]],
) -> np.ndarray:
    global_threshold = thresholds[intent]["threshold"]
    by_language = thresholds[intent]["byLanguage"]
    return np.array(
        [
            by_language.get(record["language"], {}).get(
                "threshold", global_threshold
            )
            for record in records
        ]
    )


def runtime_predictions(
    records: list[dict[str, Any]],
    probabilities: dict[str, np.ndarray],
    thresholds: dict[str, dict[str, Any]],
) -> dict[str, np.ndarray]:
    predicted = {
        intent: probabilities[intent]
        >= thresholds_for_records(records, intent, thresholds)
        for intent in INTENTS
    }
    for intent in INTENTS:
        if intent == "replyableMessage":
            continue
        predicted[intent] &= np.array(
            [
                has_explicit_evidence(intent, record["text"])
                for record in records
            ]
        )
    predicted["task"] &= ~(
        (probabilities["complaint"] >= 0.60)
        & np.array(
            [not has_explicit_task(record["text"]) for record in records]
        )
    )
    return predicted


def metrics_for_records(
    records: list[dict[str, Any]],
    probabilities: dict[str, np.ndarray],
    thresholds: dict[str, dict[str, Any]],
) -> dict[str, Any]:
    predictions = runtime_predictions(records, probabilities, thresholds)
    per_intent = {}
    for intent in INTENTS:
        known_mask = np.array(
            [is_known(record, intent) for record in records],
            dtype=bool,
        )
        expected = np.array(
            [record_label(record, intent) for record in records], dtype=bool
        )
        counts = BinaryCounts()
        counts.update(expected[known_mask], predictions[intent][known_mask])
        per_intent[intent] = counts.metrics()
    return aggregate_metrics(per_intent)


def aggregate_metrics(per_intent: dict[str, dict[str, Any]]) -> dict[str, Any]:
    return {
        "recordCount": next(iter(per_intent.values()))["total"]
        if per_intent
        else 0,
        "macroPrecision": rounded(
            np.mean([value["precision"] for value in per_intent.values()])
        ),
        "macroRecall": rounded(
            np.mean([value["recall"] for value in per_intent.values()])
        ),
        "macroF1": rounded(
            np.mean([value["f1"] for value in per_intent.values()])
        ),
        "minimumPrecision": min(
            (value["precision"] for value in per_intent.values()), default=0
        ),
        "intentsMeeting95Precision": sum(
            value["precision"] >= 0.95
            and value["predictedPositive"] >= 10
            for value in per_intent.values()
        ),
        "perIntent": per_intent,
    }


def prediction_probabilities(
    matrix: sparse.spmatrix,
    models: dict[str, SGDClassifier],
) -> dict[str, np.ndarray]:
    return {
        intent: model.predict_proba(matrix)[:, 1]
        for intent, model in models.items()
    }


def pseudo_labels_from_committee(
    unknown_records: list[dict[str, Any]],
    history: dict[str, deque[tuple[np.ndarray, np.ndarray]]],
    round_number: int,
) -> dict[str, list[tuple[int, bool]]]:
    result: dict[str, list[tuple[int, bool]]] = defaultdict(list)
    for intent in INTENTS:
        if len(history[intent]) < 3:
            continue
        decisions = np.stack(
            [
                probabilities >= thresholds
                for probabilities, thresholds in history[intent]
            ]
        )
        probabilities = np.stack(
            [probabilities for probabilities, _ in history[intent]]
        )
        positive = np.all(decisions, axis=0) & (
            np.min(probabilities, axis=0) >= 0.985
        )
        negative = np.all(~decisions, axis=0) & (
            np.max(probabilities, axis=0) <= 0.015
        )
        if intent == "blessing":
            positive &= np.array(
                [has_explicit_blessing(record["text"]) for record in unknown_records]
            )
        candidates = [
            (index, True)
            for index in np.flatnonzero(positive)
            if not is_known(unknown_records[index], intent)
        ] + [
            (index, False)
            for index in np.flatnonzero(negative)
            if not is_known(unknown_records[index], intent)
        ]
        candidates.sort(
            key=lambda item: stable_value(
                f"{round_number}|pseudo|{intent}|{unknown_records[item[0]]['id']}"
            )
        )
        positive_count = 0
        negative_count = 0
        for item in candidates:
            if item[1] and positive_count >= 250:
                continue
            if not item[1] and negative_count >= 250:
                continue
            result[intent].append(item)
            if item[1]:
                positive_count += 1
            else:
                negative_count += 1
    return result


def train_round(
    configuration: RoundConfiguration,
    base_training: list[dict[str, Any]],
    open_records: list[dict[str, Any]],
    validation: list[dict[str, Any]],
    test: list[dict[str, Any]],
    pseudo: dict[str, list[tuple[int, bool]]],
) -> tuple[
    FeatureUnion,
    dict[str, SGDClassifier],
    dict[str, dict[str, Any]],
    dict[str, Any],
    dict[str, np.ndarray],
]:
    augmentations = augmented_records(base_training, configuration)
    feature_records = base_training + open_records + augmentations
    texts = [record["text"] for record in feature_records]
    fitted_vectorizer = vectorizer(configuration)
    training_matrix = fitted_vectorizer.fit_transform(texts)
    validation_matrix = fitted_vectorizer.transform(
        [record["text"] for record in validation]
    )
    test_matrix = fitted_vectorizer.transform(
        [record["text"] for record in test]
    )

    models: dict[str, SGDClassifier] = {}
    for intent_index, intent in enumerate(INTENTS):
        indices = [
            index
            for index, record in enumerate(feature_records)
            if is_known(record, intent)
        ]
        labels = [
            record_label(feature_records[index], intent) for index in indices
        ]
        weights = [
            sample_weight(feature_records[index], configuration)
            for index in indices
        ]
        pseudo_rows = pseudo.get(intent, [])
        if pseudo_rows:
            open_offset = len(base_training)
            for open_index, label in pseudo_rows:
                indices.append(open_offset + open_index)
                labels.append(label)
                weights.append(configuration.pseudo_weight)
        model = SGDClassifier(
            loss="log_loss",
            penalty="elasticnet",
            alpha=configuration.alpha,
            l1_ratio=configuration.l1_ratio,
            class_weight="balanced",
            max_iter=1_500,
            tol=1e-5,
            random_state=SEED + configuration.round * 31 + intent_index,
            average=True,
        )
        model.fit(
            training_matrix[indices],
            np.array(labels, dtype=np.int8),
            sample_weight=np.array(weights, dtype=np.float32),
        )
        models[intent] = model

    validation_probabilities = prediction_probabilities(
        validation_matrix, models
    )
    thresholds = calibrated_thresholds(
        validation, validation_probabilities
    )
    validation_metrics = metrics_for_records(
        validation, validation_probabilities, thresholds
    )
    test_metrics = metrics_for_records(
        test,
        prediction_probabilities(test_matrix, models),
        thresholds,
    )
    objective = rounded(
        validation_metrics["macroF1"] * 0.55
        + validation_metrics["macroPrecision"] * 0.35
        + validation_metrics["macroRecall"] * 0.10
    )
    report = {
        "round": configuration.round,
        "configuration": asdict(configuration),
        "trainingRecords": len(feature_records),
        "featureCount": int(training_matrix.shape[1]),
        "pseudoLabelCounts": {
            intent: {
                "positive": sum(label for _, label in values),
                "negative": sum(not label for _, label in values),
            }
            for intent, values in pseudo.items()
        },
        "thresholds": thresholds,
        "validation": validation_metrics,
        "syntheticRegression": test_metrics,
        "selectionObjective": objective,
    }
    return (
        fitted_vectorizer,
        models,
        thresholds,
        report,
        validation_probabilities,
    )


def batched_evaluation(
    records: list[dict[str, Any]],
    fitted_vectorizer: FeatureUnion | None,
    models: dict[str, SGDClassifier] | None,
    thresholds: dict[str, dict[str, Any]],
    intent_bundles: dict[
        str, tuple[FeatureUnion, SGDClassifier]
    ] | None = None,
    batch_size: int = 2_000,
) -> dict[str, Any]:
    counts = {intent: BinaryCounts() for intent in INTENTS}
    by_language: dict[str, dict[str, BinaryCounts]] = defaultdict(
        lambda: {intent: BinaryCounts() for intent in INTENTS}
    )
    by_source: dict[str, dict[str, BinaryCounts]] = defaultdict(
        lambda: {intent: BinaryCounts() for intent in INTENTS}
    )
    for offset in range(0, len(records), batch_size):
        batch = records[offset : offset + batch_size]
        texts = [record["text"] for record in batch]
        if intent_bundles is not None:
            probabilities = {
                intent: model.predict_proba(
                    intent_vectorizer.transform(texts)
                )[:, 1]
                for intent, (intent_vectorizer, model) in intent_bundles.items()
            }
        else:
            assert fitted_vectorizer is not None and models is not None
            matrix = fitted_vectorizer.transform(texts)
            probabilities = prediction_probabilities(matrix, models)
        predictions = runtime_predictions(batch, probabilities, thresholds)
        for intent in INTENTS:
            known_mask = np.array(
                [is_known(record, intent) for record in batch],
                dtype=bool,
            )
            expected = np.array(
                [record_label(record, intent) for record in batch], dtype=bool
            )
            counts[intent].update(
                expected[known_mask],
                predictions[intent][known_mask],
            )
            for language in {record["language"] for record in batch}:
                mask = np.array(
                    [record["language"] == language for record in batch]
                ) & known_mask
                by_language[language][intent].update(
                    expected[mask], predictions[intent][mask]
                )
            for source in {
                record.get("sourceDataset") or record.get("family", "unknown")
                for record in batch
            }:
                mask = np.array(
                    [
                        (
                            record.get("sourceDataset")
                            or record.get("family", "unknown")
                        )
                        == source
                        for record in batch
                    ]
                ) & known_mask
                by_source[source][intent].update(
                    expected[mask], predictions[intent][mask]
                )
    per_intent = {
        intent: value.metrics() for intent, value in counts.items()
    }
    return {
        **aggregate_metrics(per_intent),
        "byLanguage": {
            language: aggregate_metrics(
                {
                    intent: value.metrics()
                    for intent, value in intent_counts.items()
                }
            )
            for language, intent_counts in sorted(by_language.items())
        },
        "bySource": {
            source: aggregate_metrics(
                {
                    intent: value.metrics()
                    for intent, value in intent_counts.items()
                }
            )
            for source, intent_counts in sorted(by_source.items())
        },
    }


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--rounds", type=int, default=20)
    parser.add_argument("--base-corpus", type=Path, default=BASE_CORPUS)
    parser.add_argument("--open-corpus", type=Path, default=OPEN_CORPUS)
    parser.add_argument("--output-directory", type=Path, default=OUTPUT_DIRECTORY)
    parser.add_argument("--skip-comprehensive", action="store_true")
    return parser.parse_args()


def write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def main() -> None:
    arguments = parse_arguments()
    all_configurations = configurations()
    if arguments.rounds != 20:
        all_configurations = all_configurations[: arguments.rounds]
    if len(all_configurations) != arguments.rounds:
        raise ValueError("The research matrix defines at most 20 rounds")

    base_records = read_json_lines(arguments.base_corpus)
    open_records = read_json_lines(arguments.open_corpus)
    if not base_records:
        raise ValueError("Base corpus is empty")
    splits = {
        split: [
            record for record in base_records if record.get("split") == split
        ]
        for split in ("train", "validation", "test", "golden")
    }
    if any(not values for values in splits.values()):
        raise ValueError("Base train/validation/test/golden splits are required")

    training_fingerprints = {
        " ".join(record["text"].casefold().split())
        for record in splits["train"] + open_records
    }
    frozen_paths = [RANDOM_HOLDOUT, TARGETED_HOLDOUT, COMPREHENSIVE_HOLDOUT]
    overlap_counts = {}
    for path in frozen_paths:
        records = read_json_lines(path)
        overlap_counts[str(path)] = sum(
            " ".join(record["text"].casefold().split())
            in training_fingerprints
            for record in records
        )
    if any(overlap_counts.values()):
        raise ValueError(f"Training/holdout overlap: {overlap_counts}")

    unknown_matrix_records = open_records
    committee_history: dict[
        str, deque[tuple[np.ndarray, np.ndarray]]
    ] = {
        intent: deque(maxlen=3) for intent in INTENTS
    }
    pseudo: dict[str, list[tuple[int, bool]]] = {}
    round_reports = []
    best: tuple[
        float,
        FeatureUnion,
        dict[str, SGDClassifier],
        dict[str, dict[str, Any]],
        dict[str, Any],
    ] | None = None
    best_per_intent: dict[
        str,
        tuple[
            tuple[bool, float, float],
            FeatureUnion,
            SGDClassifier,
            dict[str, Any],
            RoundConfiguration,
        ],
    ] = {}

    started_at = time.monotonic()
    for configuration in all_configurations:
        (
            fitted_vectorizer,
            models,
            thresholds,
            report,
            _,
        ) = train_round(
            configuration,
            splits["train"],
            open_records,
            splits["validation"],
            splits["test"],
            pseudo,
        )
        round_reports.append(report)
        objective = report["selectionObjective"]
        if best is None or objective > best[0]:
            best = (
                objective,
                fitted_vectorizer,
                models,
                thresholds,
                report,
            )
        for intent in INTENTS:
            metrics = report["validation"]["perIntent"][intent]
            intent_score = (
                metrics["precision"] >= 0.95
                and metrics["predictedPositive"] >= 10,
                metrics["f1"],
                metrics["recall"],
            )
            current = best_per_intent.get(intent)
            if current is None or intent_score > current[0]:
                best_per_intent[intent] = (
                    intent_score,
                    fitted_vectorizer,
                    models[intent],
                    thresholds[intent],
                    configuration,
                )

        if unknown_matrix_records:
            unknown_matrix = fitted_vectorizer.transform(
                [record["text"] for record in unknown_matrix_records]
            )
            unknown_probabilities = prediction_probabilities(
                unknown_matrix, models
            )
            for intent in INTENTS:
                per_record_thresholds = thresholds_for_records(
                    unknown_matrix_records, intent, thresholds
                )
                committee_history[intent].append(
                    (unknown_probabilities[intent], per_record_thresholds)
                )
            pseudo = pseudo_labels_from_committee(
                unknown_matrix_records,
                committee_history,
                configuration.round + 1,
            )
        print(
            "ITERATIVE_ROUND "
            f"round={configuration.round} "
            f"objective={objective:.4f} "
            f"validationPrecision={report['validation']['macroPrecision']:.4f} "
            f"validationF1={report['validation']['macroF1']:.4f} "
            f"testF1={report['syntheticRegression']['macroF1']:.4f}"
        )

    assert best is not None
    _, fitted_vectorizer, models, thresholds, selected_report = best
    composite_bundles = {
        intent: (values[1], values[2])
        for intent, values in best_per_intent.items()
    }
    composite_thresholds = {
        intent: values[3] for intent, values in best_per_intent.items()
    }
    selected_rounds_by_intent = {
        intent: values[4].round for intent, values in best_per_intent.items()
    }
    final_sets = {
        "golden": splits["golden"],
        "randomHoldout": read_json_lines(RANDOM_HOLDOUT),
        "targetedRelease": read_json_lines(TARGETED_HOLDOUT),
    }
    if not arguments.skip_comprehensive:
        final_sets["researchOnlyComprehensive"] = read_json_lines(
            COMPREHENSIVE_HOLDOUT
        )
    final_evaluations = {
        name: batched_evaluation(
            records,
            None,
            None,
            composite_thresholds,
            intent_bundles=composite_bundles,
        )
        for name, records in final_sets.items()
        if records
    }

    release_sets = [
        final_evaluations.get("golden"),
        final_evaluations.get("randomHoldout"),
        final_evaluations.get("targetedRelease"),
    ]
    release_gate = bool(release_sets) and all(
        evaluation
        and evaluation["macroPrecision"] >= 0.95
        and evaluation["intentsMeeting95Precision"] == len(INTENTS)
        for evaluation in release_sets
    )
    report = {
        "schemaVersion": 1,
        "generatedAtUnix": int(time.time()),
        "seed": SEED,
        "roundCount": len(round_reports),
        "trainingPolicy": (
            "No user clipboard data. Official partial labels plus deterministic "
            "label-preserving augmentation and three-round high-confidence "
            "self-training consensus. Frozen holdouts never enter training or "
            "threshold calibration."
        ),
        "platformLimitation": (
            "Linux surrogate research only. Apple Create ML/Core ML artifacts "
            "must be retrained and tested on macOS before deployment."
        ),
        "baseTrainingRecords": len(splits["train"]),
        "openTrainingRecords": len(open_records),
        "overlapChecks": overlap_counts,
        "elapsedSeconds": rounded(time.monotonic() - started_at),
        "selectedRound": selected_report["round"],
        "selectedRoundsByIntent": selected_rounds_by_intent,
        "selectedConfiguration": selected_report["configuration"],
        "selectedThresholds": composite_thresholds,
        "selectionObjective": selected_report["selectionObjective"],
        "finalEvaluations": final_evaluations,
        "releaseGatePassed": release_gate,
        "deploymentDecision": (
            "eligible-for-macos-replay"
            if release_gate
            else "retain-current-deployed-models"
        ),
    }
    replay = {
        "schemaVersion": 1,
        "selectedRound": selected_report["round"],
        "selectedRoundsByIntent": selected_rounds_by_intent,
        "seed": SEED,
        "baseCorpus": str(arguments.base_corpus),
        "openCorpus": str(arguments.open_corpus),
        "configuration": selected_report["configuration"],
        "configurationsByIntent": {
            intent: asdict(values[4])
            for intent, values in best_per_intent.items()
        },
        "thresholds": composite_thresholds,
        "requiredCommands": [
            "python3 Scripts/clipboard_semantics/generate_open_training_corpus.py",
            (
                "xcrun swift Scripts/clipboard_semantics/train_models.swift "
                "--algorithms maxEnt "
                "--corpus ModelTraining/ClipboardSemantics/combined-training-corpus.jsonl"
            ),
            (
                "xcrun swift Scripts/clipboard_semantics/evaluate_random_holdout.swift "
                "--corpus ModelTraining/ClipboardSemantics/random-holdout-corpus.jsonl"
            ),
        ],
        "automaticPromotionAllowed": False,
        "reason": (
            "Surrogate feature weights are not deployable NLModel assets and "
            "cannot bypass the existing macOS acceptance policy."
        ),
    }
    write_json(arguments.output_directory / "rounds.json", round_reports)
    write_json(arguments.output_directory / "final-report.json", report)
    write_json(arguments.output_directory / "macos-replay.json", replay)
    print(
        "ITERATIVE_RETRAINING_DONE "
        f"rounds={len(round_reports)} selected={selected_report['round']} "
        f"releaseGate={str(release_gate).lower()} "
        f"elapsed={report['elapsedSeconds']}"
    )


if __name__ == "__main__":
    main()
