#!/usr/bin/env python3
"""Fine-tune bilingual Tiny Transformer challengers for taxonomy-v6 intents."""

from __future__ import annotations

import argparse
import json
import random
import resource
import time
from dataclasses import dataclass
from pathlib import Path

import numpy as np
import torch
from torch.utils.data import DataLoader, Dataset
from transformers import AutoModelForSequenceClassification, AutoTokenizer


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
LANGUAGE_MODELS = {
    "en": "en",
    "zh-Hans": "zh",
}


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--corpus", type=Path, required=True)
    parser.add_argument("--output-directory", type=Path, required=True)
    parser.add_argument("--english-model", type=Path, required=True)
    parser.add_argument("--chinese-model", type=Path, required=True)
    parser.add_argument("--epochs", type=int, default=3)
    parser.add_argument("--batch-size", type=int, default=128)
    parser.add_argument("--max-length", type=int, default=96)
    parser.add_argument("--learning-rate", type=float, default=3e-4)
    parser.add_argument("--seed", type=int, default=20260828)
    return parser.parse_args()


def set_seed(seed: int) -> None:
    random.seed(seed)
    np.random.seed(seed)
    torch.manual_seed(seed)
    if torch.backends.mps.is_available():
        torch.mps.manual_seed(seed)


def intent_value(record: dict, intent: str) -> bool:
    if intent == "replyableMessage":
        return bool(record.get(intent, record.get("replyable", False)))
    return bool(record.get(intent, False))


def intent_mask(record: dict) -> list[float]:
    known_labels = record.get("knownLabels")
    if known_labels is None:
        return [1.0] * len(INTENTS)
    known = set(known_labels)
    return [float(intent in known) for intent in INTENTS]


def load_records(path: Path) -> dict[str, dict[str, list[dict]]]:
    records = {
        language: {"train": [], "validation": [], "test": [], "golden": []}
        for language in LANGUAGE_MODELS
    }
    with path.open(encoding="utf-8") as stream:
        for line in stream:
            record = json.loads(line)
            language = record.get("language")
            split = record.get("split")
            if language in records and split in records[language]:
                records[language][split].append(record)
    return records


class IntentDataset(Dataset):
    def __init__(
        self,
        records: list[dict],
        tokenizer: AutoTokenizer,
        max_length: int,
    ) -> None:
        encoded = tokenizer(
            [record["text"] for record in records],
            max_length=max_length,
            padding="max_length",
            truncation=True,
            return_tensors="pt",
        )
        self.inputs = dict(encoded)
        self.labels = torch.tensor(
            [
                [float(intent_value(record, intent)) for intent in INTENTS]
                for record in records
            ],
            dtype=torch.float32,
        )
        self.masks = torch.tensor(
            [intent_mask(record) for record in records],
            dtype=torch.float32,
        )
        self.weights = torch.tensor(
            [float(record.get("sampleWeight", 1.0)) for record in records],
            dtype=torch.float32,
        )

    def __len__(self) -> int:
        return self.labels.shape[0]

    def __getitem__(self, index: int) -> dict[str, torch.Tensor]:
        item = {key: value[index] for key, value in self.inputs.items()}
        item["labels"] = self.labels[index]
        item["masks"] = self.masks[index]
        item["weights"] = self.weights[index]
        return item


@dataclass(frozen=True)
class Metrics:
    true_positive: int
    true_negative: int
    false_positive: int
    false_negative: int
    precision: float
    recall: float
    f1: float

    def as_dict(self) -> dict:
        return {
            "truePositive": self.true_positive,
            "trueNegative": self.true_negative,
            "falsePositive": self.false_positive,
            "falseNegative": self.false_negative,
            "precision": round(self.precision, 6),
            "recall": round(self.recall, 6),
            "f1": round(self.f1, 6),
        }


def calculate_metrics(
    expected: np.ndarray,
    predicted: np.ndarray,
    mask: np.ndarray,
) -> Metrics:
    expected = expected[mask.astype(bool)].astype(bool)
    predicted = predicted[mask.astype(bool)].astype(bool)
    true_positive = int(np.sum(expected & predicted))
    true_negative = int(np.sum(~expected & ~predicted))
    false_positive = int(np.sum(~expected & predicted))
    false_negative = int(np.sum(expected & ~predicted))
    precision_denominator = true_positive + false_positive
    recall_denominator = true_positive + false_negative
    precision = (
        true_positive / precision_denominator if precision_denominator else 0.0
    )
    recall = true_positive / recall_denominator if recall_denominator else 0.0
    f1 = (
        2 * precision * recall / (precision + recall)
        if precision + recall
        else 0.0
    )
    return Metrics(
        true_positive,
        true_negative,
        false_positive,
        false_negative,
        precision,
        recall,
        f1,
    )


def predict(
    model: AutoModelForSequenceClassification,
    tokenizer: AutoTokenizer,
    records: list[dict],
    device: torch.device,
    max_length: int,
    batch_size: int,
) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    model.eval()
    probabilities: list[np.ndarray] = []
    expected: list[np.ndarray] = []
    masks: list[np.ndarray] = []
    with torch.inference_mode():
        for start in range(0, len(records), batch_size):
            batch = records[start : start + batch_size]
            encoded = tokenizer(
                [record["text"] for record in batch],
                max_length=max_length,
                padding="max_length",
                truncation=True,
                return_tensors="pt",
            )
            inputs = {key: value.to(device) for key, value in encoded.items()}
            probabilities.append(
                torch.sigmoid(model(**inputs).logits).cpu().numpy()
            )
            expected.append(
                np.array(
                    [
                        [float(intent_value(record, intent)) for intent in INTENTS]
                        for record in batch
                    ],
                    dtype=np.float32,
                )
            )
            masks.append(
                np.array([intent_mask(record) for record in batch], dtype=np.float32)
            )
    return (
        np.concatenate(probabilities),
        np.concatenate(expected),
        np.concatenate(masks),
    )


def choose_thresholds(
    probabilities: np.ndarray,
    expected: np.ndarray,
    masks: np.ndarray,
) -> np.ndarray:
    thresholds: list[float] = []
    for index in range(len(INTENTS)):
        known = masks[:, index].astype(bool)
        labels = expected[known, index]
        if not np.any(labels == 1) or not np.any(labels == 0):
            thresholds.append(0.5)
            continue
        candidates = []
        for threshold in np.linspace(0.05, 0.95, 91):
            metrics = calculate_metrics(
                expected[:, index],
                probabilities[:, index] >= threshold,
                masks[:, index],
            )
            candidates.append((metrics.f1, metrics.precision, metrics.recall, threshold))
        thresholds.append(float(max(candidates)[3]))
    return np.array(thresholds, dtype=np.float32)


def summarize(
    probabilities: np.ndarray,
    expected: np.ndarray,
    masks: np.ndarray,
    thresholds: np.ndarray,
) -> dict:
    per_intent = {}
    supported_metrics = []
    for index, intent in enumerate(INTENTS):
        metrics = calculate_metrics(
            expected[:, index],
            probabilities[:, index] >= thresholds[index],
            masks[:, index],
        )
        known_count = int(np.sum(masks[:, index]))
        positive_count = int(np.sum(expected[:, index] * masks[:, index]))
        per_intent[intent] = {
            "knownCount": known_count,
            "positiveCount": positive_count,
            **metrics.as_dict(),
        }
        if positive_count > 0:
            supported_metrics.append(metrics)
    return {
        "records": int(expected.shape[0]),
        "evaluatedIntentCount": len(supported_metrics),
        "macroPrecision": round(
            float(np.mean([metrics.precision for metrics in supported_metrics])), 6
        ),
        "macroRecall": round(
            float(np.mean([metrics.recall for metrics in supported_metrics])), 6
        ),
        "macroF1": round(
            float(np.mean([metrics.f1 for metrics in supported_metrics])), 6
        ),
        "perIntent": per_intent,
    }


def train_language(
    language: str,
    model_path: Path,
    records: dict[str, list[dict]],
    arguments: argparse.Namespace,
    device: torch.device,
) -> dict:
    set_seed(arguments.seed)
    tokenizer = AutoTokenizer.from_pretrained(model_path, local_files_only=True)
    model = AutoModelForSequenceClassification.from_pretrained(
        model_path,
        local_files_only=True,
        num_labels=len(INTENTS),
        problem_type="multi_label_classification",
        ignore_mismatched_sizes=True,
    ).to(device)
    dataset = IntentDataset(records["train"], tokenizer, arguments.max_length)
    generator = torch.Generator().manual_seed(arguments.seed)
    loader = DataLoader(
        dataset,
        batch_size=arguments.batch_size,
        shuffle=True,
        generator=generator,
    )
    weighted_positive = (dataset.labels * dataset.masks) * dataset.weights[:, None]
    weighted_known = dataset.masks * dataset.weights[:, None]
    positive_counts = weighted_positive.sum(dim=0)
    negative_counts = weighted_known.sum(dim=0) - positive_counts
    positive_weights = torch.clamp(
        negative_counts / torch.clamp(positive_counts, min=1),
        min=1,
        max=20,
    ).to(device)
    criterion = torch.nn.BCEWithLogitsLoss(
        pos_weight=positive_weights,
        reduction="none",
    )
    optimizer = torch.optim.AdamW(
        model.parameters(),
        lr=arguments.learning_rate,
        weight_decay=0.01,
    )

    epoch_losses = []
    training_started = time.perf_counter()
    for epoch in range(arguments.epochs):
        model.train()
        running_loss = 0.0
        for batch in loader:
            labels = batch.pop("labels").to(device)
            masks = batch.pop("masks").to(device)
            weights = batch.pop("weights").to(device).unsqueeze(1)
            inputs = {key: value.to(device) for key, value in batch.items()}
            optimizer.zero_grad(set_to_none=True)
            losses = criterion(model(**inputs).logits, labels)
            weighted_masks = masks * weights
            loss = (losses * weighted_masks).sum() / weighted_masks.sum().clamp(min=1)
            loss.backward()
            torch.nn.utils.clip_grad_norm_(model.parameters(), 1.0)
            optimizer.step()
            running_loss += float(loss.detach().cpu())
        average_loss = running_loss / max(len(loader), 1)
        epoch_losses.append(round(average_loss, 6))
        print(
            f"TRAIN language={language} epoch={epoch + 1}/{arguments.epochs} "
            f"loss={average_loss:.6f}",
            flush=True,
        )

    predictions = {}
    for split in ("validation", "test", "golden"):
        predictions[split] = predict(
            model,
            tokenizer,
            records[split],
            device,
            arguments.max_length,
            arguments.batch_size,
        )
    thresholds = choose_thresholds(*predictions["validation"])
    evaluations = {
        split: summarize(*values, thresholds)
        for split, values in predictions.items()
    }

    sample_text = records["test"][0]["text"]
    encoded = tokenizer(
        sample_text,
        max_length=arguments.max_length,
        padding="max_length",
        truncation=True,
        return_tensors="pt",
    )
    inputs = {key: value.to(device) for key, value in encoded.items()}
    model.eval()
    with torch.inference_mode():
        started = time.perf_counter()
        model(**inputs)
        if device.type == "mps":
            torch.mps.synchronize()
        cold_ms = (time.perf_counter() - started) * 1_000
        warm_samples = []
        for _ in range(100):
            started = time.perf_counter()
            model(**inputs)
            if device.type == "mps":
                torch.mps.synchronize()
            warm_samples.append((time.perf_counter() - started) * 1_000)

    output = arguments.output_directory / LANGUAGE_MODELS[language]
    output.mkdir(parents=True, exist_ok=True)
    model.save_pretrained(output)
    tokenizer.save_pretrained(output)
    model_bytes = sum(path.stat().st_size for path in output.iterdir() if path.is_file())
    return {
        "language": language,
        "baseModel": str(model_path),
        "trainRecords": len(records["train"]),
        "epochLosses": epoch_losses,
        "trainingSeconds": round(time.perf_counter() - training_started, 3),
        "thresholds": {
            intent: round(float(thresholds[index]), 4)
            for index, intent in enumerate(INTENTS)
        },
        "evaluations": evaluations,
        "runtime": {
            "engine": f"PyTorch eager on {device.type}",
            "coldMilliseconds": round(cold_ms, 3),
            "warmMeanMilliseconds": round(float(np.mean(warm_samples)), 3),
            "warmP95Milliseconds": round(float(np.percentile(warm_samples, 95)), 3),
            "processMaximumRSSBytes": int(
                resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
            ),
        },
        "savedModelBytes": model_bytes,
    }


def main() -> None:
    arguments = parse_arguments()
    set_seed(arguments.seed)
    device = torch.device("mps" if torch.backends.mps.is_available() else "cpu")
    records = load_records(arguments.corpus)
    model_paths = {
        "en": arguments.english_model,
        "zh-Hans": arguments.chinese_model,
    }
    language_reports = []
    for language in ("zh-Hans", "en"):
        counts = {
            split: len(split_records)
            for split, split_records in records[language].items()
        }
        print(f"DATA language={language} counts={counts}", flush=True)
        language_reports.append(
            train_language(
                language,
                model_paths[language],
                records[language],
                arguments,
                device,
            )
        )
        if device.type == "mps":
            torch.mps.empty_cache()

    report = {
        "schemaVersion": 1,
        "purpose": "Taxonomy-v6 Tiny Transformer research challenger",
        "corpus": str(arguments.corpus),
        "seed": arguments.seed,
        "intents": list(INTENTS),
        "configuration": {
            "epochs": arguments.epochs,
            "batchSize": arguments.batch_size,
            "maxLength": arguments.max_length,
            "learningRate": arguments.learning_rate,
        },
        "languages": language_reports,
        "limitations": [
            "Thresholds use only the frozen validation split, which has 20 records per language.",
            "PyTorch runtime is not directly comparable with Core ML runtime.",
            "The Chinese UER checkpoint does not declare a model-weight license in its model card.",
        ],
    }
    arguments.output_directory.mkdir(parents=True, exist_ok=True)
    report_path = arguments.output_directory / "training-evaluation-report.json"
    report_path.write_text(
        json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    print(f"REPORT {report_path}", flush=True)


if __name__ == "__main__":
    main()
