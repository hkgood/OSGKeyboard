#!/usr/bin/env python3
"""Build a licensed open-data training supplement without touching holdouts."""

from __future__ import annotations

import argparse
import csv
import hashlib
import io
import json
import random
import re
import tarfile
import time
import unicodedata
import urllib.request
import zipfile
from collections import Counter, defaultdict
from dataclasses import dataclass
from pathlib import Path
from typing import Callable
from urllib.error import HTTPError, URLError

try:
    from opencc import OpenCC
except ImportError:  # Optional research dependency; the source is reported unavailable.
    OpenCC = None


SEED = 20260827
SAMPLE_SCALE = 1
OUTPUT_DIRECTORY = Path("ModelTraining/ClipboardSemantics")
BASE_CORPUS_PATH = OUTPUT_DIRECTORY / "clipboard_semantic_corpus.jsonl"
OPEN_CORPUS_PATH = OUTPUT_DIRECTORY / "open-training-corpus.jsonl"
COMBINED_CORPUS_PATH = OUTPUT_DIRECTORY / "combined-training-corpus.jsonl"
SOURCES_PATH = OUTPUT_DIRECTORY / "open-training-sources.json"
CACHE_DIRECTORY = Path("/tmp/osg-online-holdout-cache")

CPED_REVISION = "1e4b81c28a123f22387e06664f37e5dc9322380f"
CROSSWOZ_REVISION = "df82c9fdff91b9b130f2d6b89110d3870ba6260e"
TASKMASTER_REVISION = "d92cb6af3005f1dc09c39e75e7daf4a04905e00b"
MULTIDOGO_REVISION = "baa30639c4b271f394b81443c842193407cdf26d"
ASAP_REVISION = "975122a60065240124df62cb4d5dbfd19ed9ef2c"
GOEMOTIONS_REVISION = "5d8f4ac97c873bde3a792ba4628f00bb9103d3e6"
TIANJI_REVISION = "8043c8cbdfba10d1cfeb9a52b9eed0e3ea2c231b"
BIRTHDAY_REVISION = "13134d2e67e624b38b9a9b6ce3cbce5011975bea"
CFPB_REVISION = "e5fec64e1f0688e47699b9cf8c26fe4ed350123a"
OPENCLAW_GREETINGS_REVISION = "f4e3c0323d5c44235b62454706e06acd60ebeaae"
WECHAT_BLESSINGS_REVISION = "9ad614ada57aa710ae7f7fa5823d91e0fb57bc8c"
SNIPS_REVISION = "b86ac7f1577868c42158d0dec77db50956046696"
MINDS14_REVISION = "40ce77cb32a384e4d50a568e1ec39ac804019d33"
BITOD_REVISION = "a9bd74de9eecdc3d875cb4ebf6a6beaf9c30c2ff"
RESTAURANT8K_REVISION = "57ec275d8078af65b7731c2a98be812d844a6d6b"
FORMOSA_NLU_REVISION = "03a337b61a200ab690994dca4dc31aa7f209800e"

MASSIVE_ARCHIVE_URL = (
    "https://amazon-massive-nlu-dataset.s3.amazonaws.com/"
    "amazon-massive-dataset-1.1.tar.gz"
)
CLINC_ARCHIVE_URL = "https://archive.ics.uci.edu/static/public/570/clinc150.zip"
POLITENESS_ARCHIVE_URL = (
    "https://www.cs.cornell.edu/~cristian/Politeness_files/"
    "Stanford_politeness_corpus.zip"
)

INTENT_LABELS = (
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
DOMAINS = (
    "finance",
    "travel",
    "calendar",
    "communication",
    "media",
    "smartHome",
    "shopping",
    "dining",
    "health",
    "weather",
    "accountService",
    "generalKnowledge",
)
ALL_LABELS = (*INTENT_LABELS, "sentiment", "domain")

MASSIVE_INTENT_NAMES = (
    "datetime_query",
    "iot_hue_lightchange",
    "transport_ticket",
    "takeaway_query",
    "qa_stock",
    "general_greet",
    "recommendation_events",
    "music_dislikeness",
    "iot_wemo_off",
    "cooking_recipe",
    "qa_currency",
    "transport_traffic",
    "general_quirky",
    "weather_query",
    "audio_volume_up",
    "email_addcontact",
    "takeaway_order",
    "email_querycontact",
    "iot_hue_lightup",
    "recommendation_locations",
    "play_audiobook",
    "lists_createoradd",
    "news_query",
    "alarm_query",
    "iot_wemo_on",
    "general_joke",
    "qa_definition",
    "social_query",
    "music_settings",
    "audio_volume_other",
    "calendar_remove",
    "iot_hue_lightdim",
    "calendar_query",
    "email_sendemail",
    "iot_cleaning",
    "audio_volume_down",
    "play_radio",
    "cooking_query",
    "datetime_convert",
    "qa_maths",
    "iot_hue_lightoff",
    "iot_hue_lighton",
    "transport_query",
    "music_likeness",
    "email_query",
    "play_music",
    "audio_volume_mute",
    "social_post",
    "alarm_set",
    "qa_factoid",
    "calendar_set",
    "play_game",
    "alarm_remove",
    "lists_remove",
    "transport_taxi",
    "recommendation_movies",
    "iot_coffee",
    "music_query",
    "play_podcasts",
    "lists_query",
)
MASSIVE_ASSISTANT_COMMAND_INTENTS = {
    "iot_hue_lightchange",
    "iot_wemo_off",
    "iot_hue_lightup",
    "lists_createoradd",
    "iot_wemo_on",
    "calendar_remove",
    "iot_cleaning",
    "iot_hue_lightdim",
    "audio_volume_up",
    "audio_volume_other",
    "audio_volume_down",
    "iot_hue_lightoff",
    "iot_hue_lighton",
    "play_music",
    "play_radio",
    "play_audiobook",
    "play_game",
    "play_podcasts",
    "audio_volume_mute",
    "social_post",
    "alarm_set",
    "alarm_remove",
    "lists_remove",
    "music_settings",
    "iot_coffee",
}
MASSIVE_SERVICE_TASK_INTENTS = {
    "transport_ticket",
    "takeaway_order",
    "transport_taxi",
}
MASSIVE_INFORMATION_QUERY_INTENTS = {
    name for name in MASSIVE_INTENT_NAMES if name.endswith("_query")
} | {
    name for name in MASSIVE_INTENT_NAMES if name.startswith("qa_")
} | {
    name for name in MASSIVE_INTENT_NAMES if name.startswith("recommendation_")
} | {
    "cooking_recipe",
    "datetime_convert",
    "transport_traffic",
}
MASSIVE_DOMAIN_BY_PREFIX = {
    "weather": "weather",
    "transport": "travel",
    "calendar": "calendar",
    "alarm": "calendar",
    "email": "communication",
    "social": "communication",
    "music": "media",
    "audio": "media",
    "play": "media",
    "iot": "smartHome",
    "takeaway": "dining",
    "cooking": "dining",
    "news": "generalKnowledge",
    "qa": "generalKnowledge",
    "datetime": "generalKnowledge",
}

MINDS14_INTENT_NAMES = (
    "abroad",
    "address",
    "app_error",
    "atm_limit",
    "balance",
    "business_loan",
    "card_issues",
    "cash_deposit",
    "direct_debit",
    "freeze",
    "high_value_payment",
    "joint_account",
    "latest_transactions",
    "pay_bill",
)
MINDS14_INFORMATION_QUERY_INTENTS = {
    "abroad",
    "address",
    "atm_limit",
    "balance",
    "latest_transactions",
}
MINDS14_ASSISTANT_COMMAND_INTENTS = {
    "cash_deposit",
    "direct_debit",
    "freeze",
    "high_value_payment",
    "pay_bill",
}

SNIPS_MAPPING = {
    "PlayMusic": ("assistantCommand", "media"),
    "AddToPlaylist": ("assistantCommand", "media"),
    "GetWeather": ("informationQuery", "weather"),
    "BookRestaurant": ("task", "dining"),
    "SearchScreeningEvent": ("informationQuery", "media"),
    "SearchCreativeWork": ("informationQuery", "media"),
    "RateBook": (None, None),
}

GO_EMOTIONS_POSITIVE = {0, 1, 4, 5, 13, 15, 17, 18, 20, 21, 23}
GO_EMOTIONS_NEGATIVE = {2, 3, 9, 10, 11, 12, 14, 16, 19, 24, 25}

CLINC_TASK_INTENTS = {
    "alarm",
    "book_flight",
    "book_hotel",
    "calendar_update",
    "cancel",
    "cancel_reservation",
    "change_accent",
    "change_ai_name",
    "change_language",
    "change_speed",
    "change_user_name",
    "change_volume",
    "credit_limit_change",
    "find_phone",
    "freeze_account",
    "make_call",
    "new_card",
    "next_song",
    "order",
    "order_checks",
    "pay_bill",
    "pin_change",
    "play_music",
    "pto_request",
    "redeem_rewards",
    "report_fraud",
    "report_lost_card",
    "reset_settings",
    "restaurant_reservation",
    "schedule_maintenance",
    "schedule_meeting",
    "share_location",
    "shopping_list_update",
    "smart_home",
    "sync_device",
    "text",
    "timer",
    "todo_list_update",
    "transfer",
    "uber",
    "update_playlist",
    "whisper_mode",
}
CLINC_QUESTION_INTENTS = {
    "accept_reservations",
    "account_blocked",
    "application_status",
    "apr",
    "are_you_a_bot",
    "balance",
    "bill_balance",
    "bill_due",
    "calculator",
    "calories",
    "card_declined",
    "carry_on",
    "cook_time",
    "credit_limit",
    "credit_score",
    "current_location",
    "damaged_card",
    "date",
    "definition",
    "direct_deposit",
    "directions",
    "distance",
    "do_you_have_pets",
    "exchange_rate",
    "expiration_date",
    "flight_status",
    "food_last",
    "fun_fact",
    "gas",
    "gas_type",
    "how_busy",
    "how_old_are_you",
    "improve_credit_score",
    "income",
    "ingredient_substitution",
    "ingredients_list",
    "insurance",
    "interest_rate",
    "international_fees",
    "international_visa",
    "jump_start",
    "last_maintenance",
    "lost_luggage",
    "meal_suggestion",
    "meaning_of_life",
    "measurement_conversion",
    "meeting_schedule",
    "min_payment",
    "mpg",
    "next_holiday",
    "nutrition_info",
    "oil_change_how",
    "oil_change_when",
    "order_status",
    "payday",
    "plug_type",
    "pto_balance",
    "pto_request_status",
    "pto_used",
    "recipe",
    "replacement_card_duration",
    "restaurant_reviews",
    "restaurant_suggestion",
    "rewards_balance",
    "routing",
    "spelling",
    "spending_history",
    "taxes",
    "time",
    "timezone",
    "tire_change",
    "tire_pressure",
    "todo_list",
    "traffic",
    "transactions",
    "translate",
    "travel_alert",
    "travel_notification",
    "travel_suggestion",
    "user_name",
    "vaccines",
    "w2",
    "weather",
    "what_are_your_hobbies",
    "what_can_i_ask_you",
    "what_is_your_name",
    "what_song",
    "where_are_you_from",
    "who_do_you_work_for",
    "who_made_you",
}

ENGLISH_BLESSING_PATTERN = re.compile(
    r"\b(?:happy birthday|happy new year|merry christmas|happy holidays|"
    r"best wishes|good luck|congratulations|congrats|wishing you|"
    r"wish (?:you|him|her|them|everyone)|may you)\b",
    re.IGNORECASE,
)
CHINESE_BLESSING_PATTERN = re.compile(
    r"(?:生日快乐|新年快乐|春节快乐|节日快乐|圣诞快乐|中秋快乐|"
    r"恭喜|预祝|祝你|祝您|祝大家|愿你|愿您)"
)
ENGLISH_COMPLAINT_PATTERN = re.compile(
    r"\b(?:problem|issue|failed|failure|broken|not working|doesn['’]?t work|"
    r"terrible|worst|unacceptable|frustrat(?:ed|ing)|disappoint(?:ed|ing)|"
    r"charged|refund|complain)\b",
    re.IGNORECASE,
)
SENSITIVE_PATTERN = re.compile(
    r"(?:[\w.+-]+@[\w.-]+\.\w+)|(?:\+?\d[\d ()-]{8,}\d)|"
    r"(?:\b\d{3}-\d{2}-\d{4}\b)",
    re.IGNORECASE,
)
META_BLESSING_PATTERN = re.compile(
    r"(?:祝福语模板|如何写祝福|怎么说生日快乐|greeting template|"
    r"message template|how (?:do you say|to write) happy birthday)",
    re.IGNORECASE,
)


@dataclass(frozen=True)
class SourceBuilder:
    """A pinned, license-reviewed source that can fail independently."""

    name: str
    build: Callable[[int], list[dict]]
    optional: bool = True


class SourceUnavailable(RuntimeError):
    """A source cannot be built in the current environment."""


def massive_mapping(intent: str) -> tuple[str | None, str | None]:
    """Map only official MASSIVE intents with product-policy-safe semantics."""
    if intent in MASSIVE_ASSISTANT_COMMAND_INTENTS:
        label = "assistantCommand"
    elif intent in MASSIVE_INFORMATION_QUERY_INTENTS:
        label = "informationQuery"
    elif intent in MASSIVE_SERVICE_TASK_INTENTS:
        label = "task"
    else:
        label = None
    prefix = intent.split("_", 1)[0]
    return label, MASSIVE_DOMAIN_BY_PREFIX.get(prefix)


def known_labels_for_mapping(
    mapped_label: str | None,
    domain: str | None,
) -> set[str]:
    known = set()
    if mapped_label:
        # These official assistant/service intents are mutually exclusive under
        # the product policy, so their negative evidence is also trustworthy.
        known.update(
            {
                "assistantCommand",
                "informationQuery",
                "systemNotification",
            }
        )
        if mapped_label == "task":
            known.add("task")
    if domain:
        known.add("domain")
    return known


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--seed", type=int, default=SEED)
    parser.add_argument(
        "--sample-scale",
        type=int,
        default=1,
        help="Multiply license-safe source sampling caps while preserving source balance.",
    )
    parser.add_argument("--base-corpus", type=Path, default=BASE_CORPUS_PATH)
    parser.add_argument("--open-output", type=Path, default=OPEN_CORPUS_PATH)
    parser.add_argument("--combined-output", type=Path, default=COMBINED_CORPUS_PATH)
    parser.add_argument("--sources-output", type=Path, default=SOURCES_PATH)
    parser.add_argument(
        "--allow-unavailable-sources",
        action="store_true",
        help="Continue with license-safe sources that are reachable.",
    )
    return parser.parse_args()


def fetch_bytes(url: str) -> bytes:
    CACHE_DIRECTORY.mkdir(parents=True, exist_ok=True)
    cache_path = CACHE_DIRECTORY / hashlib.sha256(url.encode()).hexdigest()
    if cache_path.is_file():
        return cache_path.read_bytes()
    request = urllib.request.Request(
        url,
        headers={"User-Agent": "OSGKeyboard-open-training-corpus/1.0"},
    )
    for attempt in range(5):
        try:
            with urllib.request.urlopen(request, timeout=90) as response:
                payload = response.read()
            cache_path.write_bytes(payload)
            return payload
        except HTTPError as error:
            if error.code != 429 or attempt == 4:
                raise
            retry_after = int(error.headers.get("Retry-After", "0") or "0")
            time.sleep(max(retry_after, 3 * (attempt + 1)))
        except (URLError, TimeoutError, ConnectionError, OSError):
            if attempt == 4:
                raise
            time.sleep(2 * (attempt + 1))
    raise RuntimeError(f"Unable to download {url}")


def normalized_text(value: str) -> str:
    normalized = unicodedata.normalize("NFKC", value.replace("\u0000", " "))
    return " ".join(normalized.split()).strip()


def traditional_to_simplified(value: str) -> str:
    if OpenCC is None:
        raise SourceUnavailable(
            "FormosaNLU conversion requires opencc-python-reimplemented"
        )
    return normalized_text(OpenCC("t2s").convert(value))


def fingerprint(value: str) -> str:
    return normalized_text(value).casefold()


def eligible_text(text: str, minimum: int = 3, maximum: int = 500) -> bool:
    return (
        minimum <= len(text) <= maximum
        and not SENSITIVE_PATTERN.search(text)
        and text.count("XXXX") <= 8
    )


def stable_sample(records: list[dict], limit: int, seed: int, salt: str) -> list[dict]:
    if len(records) <= limit:
        return records
    return sorted(
        records,
        key=lambda record: hashlib.sha256(
            f"{seed}|{salt}|{record['id']}".encode()
        ).digest(),
    )[:limit]


def scaled_limit(value: int) -> int:
    return value * SAMPLE_SCALE


def limited_by_family(
    records: list[dict],
    *,
    per_family: int,
    total: int,
    seed: int,
    salt: str,
) -> list[dict]:
    grouped: dict[str, list[dict]] = defaultdict(list)
    for record_value in records:
        grouped[record_value["family"]].append(record_value)
    selected: list[dict] = []
    for family, values in sorted(grouped.items()):
        selected.extend(
            stable_sample(values, per_family, seed, f"{salt}|{family}")
        )
    return stable_sample(selected, total, seed, salt)


def make_record(
    *,
    record_id: str,
    text: str,
    language: str,
    family: str,
    source_dataset: str,
    source_license: str,
    source_url: str,
    source_revision: str,
    source_split: str,
    known_labels: set[str],
    labeling_method: str,
    task: bool = False,
    question: bool = False,
    invitation: bool = False,
    complaint: bool = False,
    schedule_negotiation: bool = False,
    confirmation_decision: bool = False,
    follow_up_reminder: bool = False,
    blessing: bool = False,
    replyable: bool = False,
    assistant_command: bool = False,
    information_query: bool = False,
    system_notification: bool = False,
    sentiment: str = "neutral",
    domain: str | None = None,
    sample_weight: float = 1.0,
) -> dict | None:
    clean_text = normalized_text(text)
    if not eligible_text(clean_text):
        return None
    invalid_labels = known_labels.difference(ALL_LABELS)
    if invalid_labels:
        raise ValueError(f"Unsupported known labels: {sorted(invalid_labels)}")
    if sentiment not in {"positive", "neutral", "negative"}:
        raise ValueError(f"Unsupported sentiment: {sentiment}")
    if domain is not None and domain not in DOMAINS:
        raise ValueError(f"Unsupported domain: {domain}")
    if "domain" in known_labels and domain is None:
        raise ValueError("Known domain requires a domain value")
    if not 0 < sample_weight <= 1:
        raise ValueError(f"Unsupported sample weight: {sample_weight}")
    return {
        "id": record_id,
        "text": clean_text,
        "language": language,
        "split": "train",
        "family": family,
        "task": task,
        "question": question,
        "invitation": invitation,
        "complaint": complaint,
        "scheduleNegotiation": schedule_negotiation,
        "confirmationDecision": confirmation_decision,
        "followUpReminder": follow_up_reminder,
        "blessing": blessing,
        "sentiment": sentiment,
        "replyable": replyable,
        "assistantCommand": assistant_command,
        "informationQuery": information_query,
        "systemNotification": system_notification,
        "domain": domain,
        "sampleWeight": sample_weight,
        "knownLabels": sorted(known_labels),
        "labelingMethod": labeling_method,
        "sourceDataset": source_dataset,
        "sourceLicense": source_license,
        "sourceURL": source_url,
        "sourceRevision": source_revision,
        "sourceSplit": source_split,
    }


def massive_records(seed: int) -> list[dict]:
    archive = tarfile.open(
        fileobj=io.BytesIO(fetch_bytes(MASSIVE_ARCHIVE_URL)),
        mode="r:gz",
    )
    records: list[dict] = []
    for config, language in (("en-US", "en"), ("zh-CN", "zh-Hans")):
        member = next(
            item
            for item in archive.getmembers()
            if item.isfile() and item.name.endswith(f"/{config}.jsonl")
        )
        stream = archive.extractfile(member)
        if stream is None:
            raise RuntimeError(f"Unable to read MASSIVE {config}")
        for raw_line in stream:
            source = json.loads(raw_line)
            if source["partition"] != "train":
                continue
            intent = source["intent"]
            mapped_label, domain = massive_mapping(intent)
            sentiment_known = intent in {"music_dislikeness", "music_likeness"}
            known = known_labels_for_mapping(mapped_label, domain)
            if intent == "general_greet":
                # A greeting opens a conversation but does not itself express
                # a wish for the recipient.
                known.add("blessing")
            if sentiment_known:
                known.add("sentiment")
            if not known:
                continue
            record_value = make_record(
                record_id=f"open-massive-{config}-{source['id']}",
                text=source["utt"],
                language=language,
                family=f"open_massive_{intent}",
                source_dataset=f"AmazonScience/MASSIVE {config}",
                source_license="CC-BY-4.0",
                source_url="https://huggingface.co/datasets/AmazonScience/massive",
                source_revision="1.1",
                source_split="train",
                known_labels=known,
                labeling_method="official intent mapping",
                task=mapped_label == "task",
                assistant_command=mapped_label == "assistantCommand",
                information_query=mapped_label == "informationQuery",
                sentiment=(
                    "negative"
                    if intent == "music_dislikeness"
                    else "positive"
                    if intent == "music_likeness"
                    else "neutral"
                ),
                domain=domain,
            )
            if record_value:
                records.append(record_value)
    archive.close()
    # MASSIVE is the strongest license-reviewed bilingual source in this
    # pipeline. Keep every official-train record with an audited label mapping;
    # downstream source balancing controls its effective training weight.
    return records


def openclaw_greeting_records(seed: int) -> list[dict]:
    url = (
        "https://huggingface.co/datasets/trytax/openclaw-zh-greetings/"
        f"resolve/{OPENCLAW_GREETINGS_REVISION}/data/greetings.jsonl"
    )
    records: list[dict] = []
    for line in fetch_bytes(url).decode("utf-8").splitlines():
        if not line.strip():
            continue
        source = json.loads(line)
        is_wish = source["label"] == "wish"
        record_value = make_record(
            record_id=f"open-openclaw-greetings-{source['id']}",
            text=source["text"],
            language="zh-Hans",
            family=f"open_openclaw_{source['label']}",
            source_dataset="openclaw-zh-greetings",
            source_license="MIT",
            source_url=(
                "https://huggingface.co/datasets/trytax/openclaw-zh-greetings"
            ),
            source_revision=OPENCLAW_GREETINGS_REVISION,
            source_split="train",
            known_labels={"blessing"},
            labeling_method="official wish versus non-wish label",
            blessing=is_wish,
        )
        if record_value:
            records.append(record_value)
    return stable_sample(records, scaled_limit(100), seed, "openclaw-greetings")


def wechat_blessing_records(seed: int) -> list[dict]:
    url = (
        "https://raw.githubusercontent.com/SWHL/WeChat-AutoSendBless/"
        f"{WECHAT_BLESSINGS_REVISION}/assets/bless.txt"
    )
    records: list[dict] = []
    for index, text in enumerate(
        fetch_bytes(url).decode("utf-8-sig").splitlines(),
        start=1,
    ):
        record_value = make_record(
            record_id=f"open-wechat-blessing-{index}",
            text=text,
            language="zh-Hans",
            family="open_wechat_new_year_blessing",
            source_dataset="SWHL/WeChat-AutoSendBless templates",
            source_license="MIT",
            source_url=(
                "https://github.com/SWHL/WeChat-AutoSendBless/"
                f"blob/{WECHAT_BLESSINGS_REVISION}/assets/bless.txt"
            ),
            source_revision=WECHAT_BLESSINGS_REVISION,
            source_split="templates",
            known_labels={"blessing"},
            labeling_method="repository-authored blessing template",
            blessing=True,
        )
        if record_value:
            records.append(record_value)
    return stable_sample(records, scaled_limit(100), seed, "wechat-blessings")


def cped_records(seed: int) -> list[dict]:
    url = (
        "https://raw.githubusercontent.com/scutcyr/CPED/"
        f"{CPED_REVISION}/data/CPED/train_split.csv"
    )
    content = fetch_bytes(url).decode("utf-8-sig")
    records: list[dict] = []
    for line_number, row in enumerate(
        csv.DictReader(io.StringIO(content)),
        start=2,
    ):
        dialogue_act = row["DA"]
        source_sentiment = row["Sentiment"]
        text = normalized_text(row.get("Utterance") or "")
        blessing = bool(
            CHINESE_BLESSING_PATTERN.search(text)
            and not META_BLESSING_PATTERN.search(text)
        )
        known = {"task", "question", "sentiment"}
        if blessing:
            known.add("blessing")
        record_value = make_record(
            record_id=f"open-cped-{row['Utterance_ID']}",
            text=text,
            language="zh-Hans",
            family=f"open_cped_{dialogue_act.replace('/', '_')}",
            source_dataset="CPED",
            source_license="Apache-2.0",
            source_url=(
                "https://github.com/scutcyr/CPED/blob/"
                f"{CPED_REVISION}/data/CPED/train_split.csv#L{line_number}"
            ),
            source_revision=CPED_REVISION,
            source_split="train",
            known_labels=known,
            labeling_method="official dialogue act and sentiment; explicit blessing marker",
            task=dialogue_act == "command",
            question=dialogue_act == "question",
            blessing=blessing,
            sentiment=(
                source_sentiment
                if source_sentiment in {"positive", "neutral", "negative"}
                else "neutral"
            ),
        )
        if record_value:
            records.append(record_value)
    return limited_by_family(
        records,
        per_family=2_500,
        total=20_000,
        seed=seed,
        salt="cped",
    )


def crosswoz_records(seed: int) -> list[dict]:
    url = (
        "https://raw.githubusercontent.com/thu-coai/CrossWOZ/"
        f"{CROSSWOZ_REVISION}/data/crosswoz/train.json.zip"
    )
    archive = zipfile.ZipFile(io.BytesIO(fetch_bytes(url)))
    dialogues = json.loads(archive.read("train.json"))
    records: list[dict] = []
    for dialogue_id, dialogue in dialogues.items():
        for turn_index, message in enumerate(dialogue["messages"]):
            if message["role"] != "usr":
                continue
            text = normalized_text(message["content"])
            acts = message.get("dialog_act") or []
            intents = {str(act[0]) for act in acts if act}
            general_intents = {
                str(act[1]) for act in acts if len(act) > 1 and act[0] == "General"
            }
            source_domains = {
                str(act[1]).casefold()
                for act in acts
                if len(act) > 1 and act[0] != "General"
            }
            mapped_domains = {
                "dining"
                if value in {"餐厅", "restaurant"}
                else "travel"
                if value in {
                    "酒店",
                    "景点",
                    "地铁",
                    "出租",
                    "hotel",
                    "attraction",
                    "metro",
                    "taxi",
                }
                else None
                for value in source_domains
            }
            mapped_domains.discard(None)
            domain = next(iter(mapped_domains)) if len(mapped_domains) == 1 else None
            information_query = "Request" in intents
            known = known_labels_for_mapping(
                "informationQuery" if information_query else None,
                domain,
            )
            if not known:
                continue
            record_value = make_record(
                record_id=f"open-crosswoz-{dialogue_id}-{turn_index}",
                text=text,
                language="zh-Hans",
                family=(
                    "open_crosswoz_"
                    + "_".join(sorted(intents | general_intents) or ["other"])
                ),
                source_dataset="CrossWOZ",
                source_license="Apache-2.0",
                source_url=(
                    "https://github.com/thu-coai/CrossWOZ/blob/"
                    f"{CROSSWOZ_REVISION}/data/crosswoz/train.json.zip"
                ),
                source_revision=CROSSWOZ_REVISION,
                source_split="train",
                known_labels=known,
                labeling_method="official dialogue-act mapping only",
                information_query=information_query,
                domain=domain,
            )
            if record_value:
                records.append(record_value)
    archive.close()
    return limited_by_family(
        records,
        per_family=scaled_limit(150),
        total=scaled_limit(600),
        seed=seed,
        salt="crosswoz",
    )


def go_emotions_records(seed: int) -> list[dict]:
    url = (
        "https://raw.githubusercontent.com/google-research/google-research/"
        f"{GOEMOTIONS_REVISION}/goemotions/data/train.tsv"
    )
    content = fetch_bytes(url).decode("utf-8")
    records: list[dict] = []
    for line_number, raw_line in enumerate(content.splitlines(), start=1):
        columns = raw_line.split("\t")
        if len(columns) != 3:
            continue
        raw_text, raw_labels, source_id = columns
        labels = {int(value) for value in raw_labels.split(",")}
        positive = bool(labels & GO_EMOTIONS_POSITIVE)
        negative = bool(labels & GO_EMOTIONS_NEGATIVE)
        sentiment = (
            "positive"
            if positive and not negative
            else "negative"
            if negative and not positive
            else "neutral"
        )
        text = normalized_text(raw_text)
        record_value = make_record(
            record_id=f"open-goemotions-{source_id}",
            text=text,
            language="en",
            family=f"open_goemotions_{sentiment}",
            source_dataset="Google Research GoEmotions",
            source_license="Apache-2.0",
            source_url=(
                "https://github.com/google-research/google-research/blob/"
                f"{GOEMOTIONS_REVISION}/goemotions/data/train.tsv#L{line_number}"
            ),
            source_revision=GOEMOTIONS_REVISION,
            source_split="train",
            known_labels={"sentiment"},
            labeling_method="official emotion labels mapped only to sentiment",
            sentiment=sentiment,
        )
        if record_value:
            records.append(record_value)
    return limited_by_family(
        records,
        per_family=400,
        total=1_200,
        seed=seed,
        salt="goemotions",
    )


def multidogo_records(seed: int) -> list[dict]:
    domains = ("airline", "fastfood", "finance", "insurance", "media", "software")
    domain_mapping = {
        "airline": "travel",
        "fastfood": "dining",
        "finance": "finance",
        "insurance": "accountService",
        "media": "media",
        "software": "accountService",
    }
    records: list[dict] = []
    for domain in domains:
        url = (
            "https://raw.githubusercontent.com/awslabs/"
            "multi-domain-goal-oriented-dialogues-dataset/"
            f"{MULTIDOGO_REVISION}/data/paper_splits/"
            "splits_annotated_at_turn_level/"
            f"{domain}/train.tsv"
        )
        content = fetch_bytes(url).decode("utf-8-sig")
        for line_number, row in enumerate(
            csv.DictReader(io.StringIO(content), delimiter="\t"),
            start=2,
        ):
            text = normalized_text(row["utterance"])
            intent = row["intent"].casefold()
            information_query = intent.startswith(("get", "check", "query"))
            task = domain in {"airline", "fastfood"} and intent.startswith(
                ("book", "cancel", "change", "order", "reserve")
            )
            assistant_command = domain in {"media", "software"} and intent.startswith(
                ("activate", "deactivate", "install", "reset", "update")
            )
            mapped_label = (
                "informationQuery"
                if information_query
                else "task"
                if task
                else "assistantCommand"
                if assistant_command
                else None
            )
            known = known_labels_for_mapping(
                mapped_label,
                domain_mapping[domain],
            )
            record_value = make_record(
                record_id=f"open-multidogo-{domain}-{row['utteranceId']}",
                text=text,
                language="en",
                family=f"open_multidogo_{domain}_{intent}",
                source_dataset="MultiDoGO",
                source_license="CDLA-Permissive-1.0",
                source_url=(
                    "https://github.com/awslabs/"
                    "multi-domain-goal-oriented-dialogues-dataset/blob/"
                    f"{MULTIDOGO_REVISION}/data/paper_splits/"
                    "splits_annotated_at_turn_level/"
                    f"{domain}/train.tsv#L{line_number}"
                ),
                source_revision=MULTIDOGO_REVISION,
                source_split="train",
                known_labels=known,
                labeling_method="official customer intent and domain mapping only",
                task=task,
                assistant_command=assistant_command,
                information_query=information_query,
                domain=domain_mapping[domain],
            )
            if record_value:
                records.append(record_value)
    return limited_by_family(
        records,
        per_family=scaled_limit(100),
        total=scaled_limit(600),
        seed=seed,
        salt="multidogo",
    )


def taskmaster_records(seed: int) -> list[dict]:
    base_url = (
        "https://raw.githubusercontent.com/google-research-datasets/"
        f"Taskmaster/{TASKMASTER_REVISION}/TM-1-2019"
    )
    split_content = fetch_bytes(f"{base_url}/train-dev-test/train.csv").decode()
    train_ids = {
        row[0].strip()
        for row in csv.reader(io.StringIO(split_content))
        if row and row[0].strip()
    }
    dialogues: list[dict] = []
    for file_name in ("self-dialogs.json", "woz-dialogs.json"):
        payload = json.loads(fetch_bytes(f"{base_url}/{file_name}"))
        dialogues.extend(payload if isinstance(payload, list) else [payload])
    records: list[dict] = []
    for dialogue in dialogues:
        dialogue_id = dialogue["conversation_id"]
        if dialogue_id not in train_ids:
            continue
        instruction = str(dialogue["instruction_id"]).casefold()
        domain = (
            "dining"
            if any(value in instruction for value in ("pizza", "restaurant", "coffee"))
            else "travel"
            if any(value in instruction for value in ("uber", "auto"))
            else "media"
            if "movie" in instruction
            else None
        )
        if domain is None:
            continue
        for utterance in dialogue["utterances"]:
            if utterance["speaker"] != "USER":
                continue
            text = normalized_text(utterance["text"])
            record_value = make_record(
                record_id=(
                    f"open-taskmaster-{dialogue_id}-{utterance['index']}"
                ),
                text=text,
                language="en",
                family=f"open_taskmaster_{dialogue['instruction_id']}",
                source_dataset="Google Taskmaster-1",
                source_license="CC-BY-4.0",
                source_url=(
                    "https://github.com/google-research-datasets/Taskmaster/"
                    f"tree/{TASKMASTER_REVISION}/TM-1-2019"
                ),
                source_revision=TASKMASTER_REVISION,
                source_split="train",
                known_labels={"domain"},
                labeling_method="official train split and instruction domain only",
                domain=domain,
            )
            if record_value:
                records.append(record_value)
    return limited_by_family(
        records,
        per_family=scaled_limit(100),
        total=scaled_limit(700),
        seed=seed,
        salt="taskmaster",
    )


def clinc_records(seed: int) -> list[dict]:
    archive = zipfile.ZipFile(io.BytesIO(fetch_bytes(CLINC_ARCHIVE_URL)))
    payload = json.loads(archive.read("clinc150_uci/data_full.json"))
    records: list[dict] = []
    for index, (text, intent) in enumerate(payload["train"]):
        reminder = intent in {"reminder", "reminder_update"}
        record_value = make_record(
            record_id=f"open-clinc150-{index}",
            text=text,
            language="en",
            family=f"open_clinc150_{intent}",
            source_dataset="CLINC150 UCI",
            source_license="CC-BY-3.0",
            source_url="https://archive.ics.uci.edu/dataset/570/clinc150",
            source_revision="UCI-570-2020-05-07",
            source_split="train",
            known_labels={
                "task",
                "question",
                "followUpReminder",
            },
            labeling_method="official intent mapping",
            task=intent in CLINC_TASK_INTENTS and not reminder,
            question=intent in CLINC_QUESTION_INTENTS,
            follow_up_reminder=reminder,
        )
        if record_value:
            records.append(record_value)
    archive.close()
    return limited_by_family(
        records,
        per_family=scaled_limit(10),
        total=scaled_limit(500),
        seed=seed,
        salt="clinc150",
    )


def politeness_records(seed: int) -> list[dict]:
    archive = zipfile.ZipFile(io.BytesIO(fetch_bytes(POLITENESS_ARCHIVE_URL)))
    records: list[dict] = []
    for file_name, source_name in (
        (
            "Stanford_politeness_corpus/wikipedia.requests.csv",
            "wikipedia",
        ),
        (
            "Stanford_politeness_corpus/stack-exchange.requests.csv",
            "stackexchange",
        ),
    ):
        stream = io.TextIOWrapper(archive.open(file_name), encoding="utf-8")
        for line_number, row in enumerate(csv.DictReader(stream), start=2):
            record_value = make_record(
                record_id=(
                    f"open-politeness-{source_name}-{row['Id']}-{line_number}"
                ),
                text=row["Request"],
                language="en",
                family=f"open_politeness_{source_name}_request",
                source_dataset="Stanford Politeness Corpus",
                source_license="CC-BY-4.0",
                source_url=(
                    "https://www.convokit.cornell.edu/documentation/"
                    "wiki_politeness.html"
                ),
                source_revision="Stanford-politeness-corpus",
                source_split="requests",
                known_labels={"task"},
                labeling_method="official request corpus",
                task=True,
            )
            if record_value:
                records.append(record_value)
    archive.close()
    return stable_sample(records, 8_000, seed, "politeness")


def tianji_records(seed: int) -> list[dict]:
    url = (
        "https://huggingface.co/datasets/sanbu/tianji-chinese/resolve/"
        f"{TIANJI_REVISION}/tianji-wishes-chinese-v0.2.json"
    )
    payload = json.loads(fetch_bytes(url))
    records: list[dict] = []
    for index, item in enumerate(payload):
        record_value = make_record(
            record_id=f"open-tianji-wishes-{index}",
            text=item["output"],
            language="zh-Hans",
            family="open_tianji_wishes",
            source_dataset="Tianji Wishes Chinese v0.2",
            source_license="Apache-2.0",
            source_url="https://huggingface.co/datasets/sanbu/tianji-chinese",
            source_revision=TIANJI_REVISION,
            source_split="v0.2",
            known_labels={"blessing", "sentiment"},
            labeling_method="dataset blessing-generation target",
            blessing=True,
            sentiment="positive",
        )
        if record_value:
            records.append(record_value)
    return stable_sample(records, 2_500, seed, "tianji")


def birthday_records(seed: int) -> list[dict]:
    url = (
        "https://huggingface.co/datasets/tejasashinde/"
        "birthday_quotes_1_to_100/resolve/"
        f"{BIRTHDAY_REVISION}/birthday_quotes_1_to_100.csv"
    )
    content = fetch_bytes(url).decode("utf-8-sig")
    records: list[dict] = []
    for index, row in enumerate(csv.DictReader(io.StringIO(content))):
        record_value = make_record(
            record_id=f"open-birthday-quotes-{index}",
            text=row["wish_text"],
            language="en",
            family="open_birthday_quotes",
            source_dataset="Birthday Quote 1 to 100",
            source_license="CC-BY-4.0",
            source_url=(
                "https://huggingface.co/datasets/"
                "tejasashinde/birthday_quotes_1_to_100"
            ),
            source_revision=BIRTHDAY_REVISION,
            source_split="train",
            known_labels={"blessing", "sentiment"},
            labeling_method="dataset birthday-message target",
            blessing=True,
            sentiment="positive",
        )
        if record_value:
            records.append(record_value)
    return stable_sample(records, 3_000, seed, "birthday")


def cfpb_records(seed: int) -> list[dict]:
    url = (
        "https://huggingface.co/datasets/hpe-ai/customer-complaints/resolve/"
        f"{CFPB_REVISION}/customer-complaints.csv"
    )
    content = fetch_bytes(url).decode("utf-8-sig")
    candidates: list[dict] = []
    for row in csv.DictReader(io.StringIO(content)):
        text = normalized_text(row["Consumer_complaint_narrative"] or "")
        record_value = make_record(
            record_id=f"open-cfpb-{row['Complaint_ID']}",
            text=text,
            language="en",
            family="open_cfpb_complaint",
            source_dataset="CFPB via hpe-ai/customer-complaints",
            source_license="CC0-1.0 source / Apache-2.0 mirror",
            source_url=(
                "https://www.consumerfinance.gov/data-research/"
                f"consumer-complaints/search/detail/{row['Complaint_ID']}"
            ),
            source_revision=CFPB_REVISION,
            source_split="train",
            known_labels={"complaint", "sentiment"},
            labeling_method="official consumer complaint narrative",
            complaint=True,
            sentiment="negative",
        )
        if record_value and len(record_value["text"]) >= 40:
            candidates.append(record_value)
    return stable_sample(candidates, scaled_limit(1_000), seed, "cfpb")


def asap_records(seed: int) -> list[dict]:
    url = (
        "https://raw.githubusercontent.com/Meituan-Dianping/ASAP/"
        f"{ASAP_REVISION}/data/train.csv"
    )
    content = fetch_bytes(url).decode("utf-8-sig")
    positive: list[dict] = []
    negative: list[dict] = []
    for row in csv.DictReader(io.StringIO(content)):
        text = normalized_text(row["review"])
        values = list(row.values())[3:]
        is_complaint = float(row["star"]) <= 2 and any(
            value == "-1" for value in values
        )
        is_clear_non_complaint = float(row["star"]) >= 4 and not any(
            value == "-1" for value in values
        )
        if not is_complaint and not is_clear_non_complaint:
            continue
        record_value = make_record(
            record_id=f"open-asap-{row['id']}",
            text=text,
            language="zh-Hans",
            family=(
                "open_asap_complaint"
                if is_complaint
                else "open_asap_non_complaint"
            ),
            source_dataset="Meituan-Dianping/ASAP",
            source_license="Apache-2.0",
            source_url=(
                "https://github.com/Meituan-Dianping/ASAP/blob/"
                f"{ASAP_REVISION}/data/train.csv#row-{row['id']}"
            ),
            source_revision=ASAP_REVISION,
            source_split="train",
            known_labels={"complaint", "sentiment", "domain"},
            labeling_method="official star and aspect-sentiment labels",
            complaint=is_complaint,
            sentiment="negative" if is_complaint else "positive",
            domain="dining",
        )
        if record_value:
            (negative if is_complaint else positive).append(record_value)
    return stable_sample(
        negative,
        scaled_limit(500),
        seed,
        "asap-negative",
    ) + stable_sample(
        positive,
        scaled_limit(500),
        seed,
        "asap-positive",
    )


def snips_records(seed: int) -> list[dict]:
    records: list[dict] = []
    for intent, (mapped_label, domain) in SNIPS_MAPPING.items():
        url = (
            "https://raw.githubusercontent.com/sonos/nlu-benchmark/"
            f"{SNIPS_REVISION}/2017-06-custom-intent-engines/{intent}/"
            f"train_{intent}_full.json"
        )
        payload = json.loads(fetch_bytes(url))
        for index, item in enumerate(payload[intent]):
            text = "".join(segment["text"] for segment in item["data"])
            known = known_labels_for_mapping(mapped_label, domain)
            if not known:
                continue
            record_value = make_record(
                record_id=f"open-snips-{intent}-{index}",
                text=text,
                language="en",
                family=f"open_snips_{intent.casefold()}",
                source_dataset="SNIPS NLU Benchmark",
                source_license="CC0-1.0",
                source_url=url,
                source_revision=SNIPS_REVISION,
                source_split="train",
                known_labels=known,
                labeling_method="official intent mapping",
                task=mapped_label == "task",
                assistant_command=mapped_label == "assistantCommand",
                information_query=mapped_label == "informationQuery",
                domain=domain,
            )
            if record_value:
                records.append(record_value)
    return limited_by_family(
        records,
        per_family=scaled_limit(250),
        total=scaled_limit(1_500),
        seed=seed,
        salt="snips",
    )


def minds14_records(seed: int) -> list[dict]:
    url = (
        "https://huggingface.co/datasets/PolyAI/minds14/resolve/"
        f"{MINDS14_REVISION}/zh-CN/train-00000-of-00001.parquet"
    )
    try:
        import pyarrow.parquet as parquet
    except ImportError as error:
        raise SourceUnavailable(
            "MInDS-14 requires optional pyarrow to read its pinned Parquet artifact"
        ) from error
    table = parquet.read_table(
        io.BytesIO(fetch_bytes(url)),
        columns=["transcription", "intent_class"],
    )
    records: list[dict] = []
    for index, source in enumerate(table.to_pylist()):
        raw_intent = source["intent_class"]
        intent = (
            MINDS14_INTENT_NAMES[raw_intent]
            if isinstance(raw_intent, int)
            else str(raw_intent)
        )
        mapped_label = (
            "informationQuery"
            if intent in MINDS14_INFORMATION_QUERY_INTENTS
            else "assistantCommand"
            if intent in MINDS14_ASSISTANT_COMMAND_INTENTS
            else None
        )
        known = known_labels_for_mapping(mapped_label, "finance")
        record_value = make_record(
            record_id=f"open-minds14-zh-CN-{index}",
            text=source["transcription"],
            language="zh-Hans",
            family=f"open_minds14_{intent}",
            source_dataset="PolyAI MInDS-14 zh-CN",
            source_license="CC-BY-4.0",
            source_url=url,
            source_revision=MINDS14_REVISION,
            source_split="train",
            known_labels=known,
            labeling_method="official intent and banking-domain mapping",
            assistant_command=mapped_label == "assistantCommand",
            information_query=mapped_label == "informationQuery",
            domain="finance",
        )
        if record_value:
            records.append(record_value)
    return limited_by_family(
        records,
        per_family=scaled_limit(80),
        total=scaled_limit(600),
        seed=seed,
        salt="minds14-zh-CN",
    )


def bitod_domain(active_intent: str) -> str | None:
    normalized = active_intent.casefold()
    if normalized.startswith("restaurants_") or normalized.startswith("餐馆"):
        return "dining"
    if normalized.startswith(
        ("hotels_", "attractions_", "hkmtr_", "宾馆", "景点", "香港地铁")
    ):
        return "travel"
    if normalized.startswith("weathers_") or normalized.startswith("天气"):
        return "weather"
    return None


def bitod_mapping(active_intent: str) -> tuple[str | None, str | None]:
    normalized = active_intent.casefold()
    domain = bitod_domain(active_intent)
    is_search = (
        normalized.endswith("_search")
        or normalized.endswith("查询")
        or normalized == "香港地铁"
    )
    is_booking = normalized.endswith("_booking") or normalized.endswith("预订")
    label = (
        "informationQuery"
        if is_search
        else "task"
        if is_booking
        else None
    )
    return label, domain


def bitod_records(seed: int) -> list[dict]:
    records: list[dict] = []
    for file_name, language in (
        ("en_train.json", "en"),
        ("zh_train.json", "zh-Hans"),
    ):
        url = (
            "https://raw.githubusercontent.com/HLTCHKUST/BiToD/"
            f"{BITOD_REVISION}/data/{file_name}"
        )
        payload = json.loads(fetch_bytes(url))
        for dialogue_id, dialogue in payload.items():
            for turn_index, turn in enumerate(dialogue["Events"]):
                if turn.get("Agent") != "User":
                    continue
                active_intent = str(turn.get("active_intent") or "")
                mapped_label, domain = bitod_mapping(active_intent)
                known = known_labels_for_mapping(mapped_label, domain)
                if not known:
                    continue
                record_value = make_record(
                    record_id=f"open-bitod-{language}-{dialogue_id}-{turn_index}",
                    text=turn.get("Text") or "",
                    language=language,
                    family=f"open_bitod_{active_intent or 'unknown'}",
                    source_dataset="HLTCHKUST/BiToD",
                    source_license="Apache-2.0",
                    source_url=url,
                    source_revision=BITOD_REVISION,
                    source_split="train",
                    known_labels=known,
                    labeling_method="official active-intent mapping",
                    task=mapped_label == "task",
                    information_query=mapped_label == "informationQuery",
                    domain=domain,
                )
                if record_value:
                    records.append(record_value)
    return limited_by_family(
        records,
        per_family=scaled_limit(120),
        total=scaled_limit(1_500),
        seed=seed,
        salt="bitod",
    )


def restaurant8k_records(seed: int) -> list[dict]:
    url = (
        "https://raw.githubusercontent.com/PolyAI-LDN/task-specific-datasets/"
        f"{RESTAURANT8K_REVISION}/span_extraction/restaurant8k/train_0.json"
    )
    records: list[dict] = []
    for index, source in enumerate(json.loads(fetch_bytes(url))):
        record_value = make_record(
            record_id=f"open-restaurant8k-{index}",
            text=source.get("userInput", {}).get("text") or "",
            language="en",
            family="open_restaurant8k",
            source_dataset="PolyAI RESTAURANTS-8K",
            source_license="CC-BY-4.0",
            source_url=url,
            source_revision=RESTAURANT8K_REVISION,
            source_split="train_0",
            known_labels={"domain"},
            labeling_method="official dataset domain only; slots are not intents",
            domain="dining",
        )
        if record_value:
            records.append(record_value)
    return stable_sample(
        records,
        scaled_limit(1_000),
        seed,
        "restaurant8k",
    )


def formosa_nlu_records(seed: int) -> list[dict]:
    url = (
        "https://huggingface.co/datasets/steven0226/"
        "formosa-nlu-synth-v1/resolve/"
        f"{FORMOSA_NLU_REVISION}/data/train.jsonl"
    )
    records: list[dict] = []
    for source in (
        json.loads(line)
        for line in fetch_bytes(url).decode("utf-8").splitlines()
        if line.strip()
    ):
        intent = source["intent"]
        mapped_label, domain = massive_mapping(intent)
        known = known_labels_for_mapping(mapped_label, domain)
        if not known:
            continue
        record_value = make_record(
            record_id=f"open-formosanlu-{source['id']}",
            text=traditional_to_simplified(source["utt"]),
            language="zh-Hans",
            family=f"open_formosanlu_{intent}",
            source_dataset="FormosaNLU Synth v1",
            source_license="CC-BY-4.0",
            source_url=url,
            source_revision=FORMOSA_NLU_REVISION,
            source_split="train",
            known_labels=known,
            labeling_method=(
                "official synthetic MASSIVE-intent mapping; OpenCC t2s conversion"
            ),
            task=mapped_label == "task",
            assistant_command=mapped_label == "assistantCommand",
            information_query=mapped_label == "informationQuery",
            domain=domain,
            sample_weight=0.35,
        )
        if record_value:
            records.append(record_value)
    return limited_by_family(
        records,
        per_family=scaled_limit(80),
        total=scaled_limit(2_000),
        seed=seed,
        salt="formosa-nlu",
    )


def holdout_fingerprints(directory: Path) -> set[str]:
    fingerprints: set[str] = set()
    for path in sorted(directory.glob("*holdout-corpus.jsonl")):
        for line in path.read_text(encoding="utf-8").splitlines():
            if not line.strip():
                continue
            value = json.loads(line)
            text = value.get("text")
            if isinstance(text, str):
                fingerprints.add(fingerprint(text))
    return fingerprints


def load_base_records(path: Path) -> list[dict]:
    return [
        json.loads(line)
        for line in path.read_text(encoding="utf-8").splitlines()
        if line.strip()
    ]


def source_summary(records: list[dict]) -> list[dict]:
    grouped: dict[str, list[dict]] = defaultdict(list)
    for record_value in records:
        grouped[record_value["sourceDataset"]].append(record_value)
    summaries: list[dict] = []
    for dataset, values in sorted(grouped.items()):
        label_counts = {
            label: sum(
                1
                for value in values
                if label in value["knownLabels"] and (
                    value[
                        "replyable"
                        if label == "replyableMessage"
                        else label
                    ]
                    if label not in {"sentiment", "domain"}
                    else value["sentiment"] != "neutral"
                    if label == "sentiment"
                    else value["domain"] is not None
                )
            )
            for label in ALL_LABELS
        }
        summaries.append(
            {
                "dataset": dataset,
                "license": values[0]["sourceLicense"],
                "revision": values[0]["sourceRevision"],
                "records": len(values),
                "languages": dict(Counter(value["language"] for value in values)),
                "knownLabelCounts": {
                    key: count for key, count in label_counts.items() if count
                },
                "url": values[0]["sourceURL"].split("#", 1)[0],
            }
        )
    return summaries


def validate_records(records: list[dict], holdouts: set[str]) -> None:
    ids: set[str] = set()
    texts: set[str] = set()
    for record_value in records:
        record_id = record_value["id"]
        text_key = fingerprint(record_value["text"])
        if record_id in ids:
            raise ValueError(f"Duplicate open-training id: {record_id}")
        if text_key in texts:
            raise ValueError(f"Duplicate open-training text: {record_id}")
        if text_key in holdouts:
            raise ValueError(f"Holdout leakage: {record_id}")
        if not record_value["knownLabels"]:
            raise ValueError(f"No known labels: {record_id}")
        ids.add(record_id)
        texts.add(text_key)


def configured_source_builders() -> tuple[SourceBuilder, ...]:
    return (
        SourceBuilder("MASSIVE", massive_records),
        SourceBuilder("CrossWOZ", crosswoz_records),
        SourceBuilder("GoEmotions", go_emotions_records),
        SourceBuilder("MultiDoGO", multidogo_records),
        SourceBuilder("Taskmaster-1", taskmaster_records),
        SourceBuilder("ASAP", asap_records),
        SourceBuilder("SNIPS", snips_records),
        SourceBuilder("MInDS-14 zh-CN", minds14_records),
        SourceBuilder("BiToD", bitod_records),
        SourceBuilder("RESTAURANTS-8K", restaurant8k_records),
        SourceBuilder("FormosaNLU Synth v1", formosa_nlu_records),
    )


def build_available_sources(
    builders: tuple[SourceBuilder, ...],
    seed: int,
    allow_unavailable_sources: bool,
) -> tuple[list[list[dict]], list[dict[str, str]]]:
    source_failures = (
        HTTPError,
        URLError,
        TimeoutError,
        ConnectionError,
        OSError,
        KeyError,
        ValueError,
        json.JSONDecodeError,
        tarfile.ReadError,
        zipfile.BadZipFile,
        SourceUnavailable,
    )
    sources: list[list[dict]] = []
    unavailable_sources: list[dict[str, str]] = []
    for builder in builders:
        try:
            sources.append(builder.build(seed))
        except source_failures as error:
            if not (builder.optional or allow_unavailable_sources):
                raise
            unavailable_sources.append(
                {
                    "dataset": builder.name,
                    "reason": f"{type(error).__name__}: {error}",
                }
            )
    return sources, unavailable_sources


def main() -> None:
    global SAMPLE_SCALE

    arguments = parse_arguments()
    if arguments.sample_scale < 1:
        raise ValueError("--sample-scale must be at least 1")
    SAMPLE_SCALE = arguments.sample_scale
    rng = random.Random(arguments.seed)
    source_builders = configured_source_builders()
    sources, unavailable_sources = build_available_sources(
        source_builders,
        arguments.seed,
        arguments.allow_unavailable_sources,
    )
    candidates = [record_value for source in sources for record_value in source]
    rng.shuffle(candidates)

    holdouts = holdout_fingerprints(OUTPUT_DIRECTORY)
    base_records = load_base_records(arguments.base_corpus)
    base_fingerprints = {
        fingerprint(record_value["text"]) for record_value in base_records
    }
    selected: list[dict] = []
    seen: set[str] = set()
    excluded_holdout = 0
    excluded_base = 0
    for record_value in candidates:
        text_key = fingerprint(record_value["text"])
        if text_key in holdouts:
            excluded_holdout += 1
            continue
        if text_key in base_fingerprints:
            excluded_base += 1
            continue
        if text_key in seen:
            continue
        seen.add(text_key)
        selected.append(record_value)

    validate_records(selected, holdouts)
    arguments.open_output.parent.mkdir(parents=True, exist_ok=True)
    serialized = "\n".join(
        json.dumps(value, ensure_ascii=False, sort_keys=True)
        for value in selected
    )
    arguments.open_output.write_text(serialized + "\n", encoding="utf-8")

    combined = base_records + selected
    arguments.combined_output.write_text(
        "\n".join(
            json.dumps(value, ensure_ascii=False, sort_keys=True)
            for value in combined
        )
        + "\n",
        encoding="utf-8",
    )
    combined_sha256 = hashlib.sha256(
        arguments.combined_output.read_bytes()
    ).hexdigest()
    manifest = {
        "schemaVersion": 1,
        "seed": arguments.seed,
        "policy": (
            "Licensed official training splits only. Per-record knownLabels prevent "
            "unannotated intents from becoming false negatives. Exact normalized text "
            "overlap with every local *holdout-corpus.jsonl file is excluded."
        ),
        "excludedSources": [
            {
                "dataset": "MIDAS",
                "reason": (
                    "Upstream deleted da_data in commit "
                    "509eb7e78b6661e54883fe3522ba60aaddcf69f2; "
                    "deleted data is not resurrected for training."
                ),
            },
            {
                "dataset": "DailyDialog / EmpatheticDialogues / Switchboard",
                "reason": "Non-commercial license restriction.",
            },
            {
                "dataset": "NormDial / xLLMs Dialogue Greetings",
                "reason": "No clear standard dataset license.",
            },
            {
                "dataset": "Schema-Guided Dialogue",
                "reason": "CC-BY-SA-4.0 compatibility requires legal review.",
            },
            {
                "dataset": "Stanford Politeness Corpus",
                "reason": (
                    "The downloadable archive does not include an explicit corpus "
                    "license; source comments may carry ShareAlike obligations."
                ),
            },
            {
                "dataset": "CPED",
                "reason": (
                    "The Apache repository license does not establish commercial "
                    "training rights for dialogue transcribed from copyrighted TV shows."
                ),
            },
            {
                "dataset": "Tianji Wishes / Birthday Quotes",
                "reason": (
                    "Dataset-level licenses do not provide a sufficiently clear "
                    "per-record source or synthetic-generation rights chain."
                ),
            },
            {
                "dataset": "Verified Enron Intent / GitHub issue holdout source",
                "reason": "No clean official train split independent from the frozen holdout.",
            },
            {
                "dataset": "CFPB",
                "reason": (
                    "No official train split; the source is already represented in "
                    "frozen evaluation data and contains privacy-sensitive narratives."
                ),
            },
            {
                "dataset": "CLINC150",
                "reason": (
                    "Kept isolated from product training because its assistant intents "
                    "are not aligned with the product-policy taxonomy."
                ),
            },
            {
                "dataset": "openclaw-zh-greetings / WeChat-AutoSendBless",
                "reason": (
                    "Repository licenses do not establish a sufficiently clear, "
                    "versioned rights chain for the underlying message templates."
                ),
            },
        ],
        "unavailableSources": unavailable_sources,
        "baseCorpusRecords": len(base_records),
        "openTrainingRecords": len(selected),
        "combinedRecords": len(combined),
        "excludedHoldoutOverlap": excluded_holdout,
        "excludedBaseOverlap": excluded_base,
        "combinedCorpusSHA256": combined_sha256,
        "sources": source_summary(selected),
    }
    arguments.sources_output.write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    print(
        "OPEN_TRAINING_CORPUS "
        f"records={len(selected)} combined={len(combined)} "
        f"excludedHoldout={excluded_holdout} sha256={combined_sha256}"
    )


if __name__ == "__main__":
    main()
