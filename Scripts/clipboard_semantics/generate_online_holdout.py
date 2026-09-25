#!/usr/bin/env python3
"""Build a frozen holdout from licensed, human-authored online corpora."""

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
import urllib.parse
import urllib.request
from urllib.error import HTTPError, URLError
from pathlib import Path


SEED = 20260831
ASAP_COMMIT = "975122a60065240124df62cb4d5dbfd19ed9ef2c"
OUTPUT_DIRECTORY = Path("ModelTraining/ClipboardSemantics")
TRAINING_CORPUS_PATH = OUTPUT_DIRECTORY / "clipboard_semantic_corpus.jsonl"
CORPUS_PATH = OUTPUT_DIRECTORY / "online-real-holdout-corpus.jsonl"
SOURCES_PATH = OUTPUT_DIRECTORY / "online-real-holdout-sources.json"
COMPREHENSIVE_CORPUS_PATH = (
    OUTPUT_DIRECTORY / "comprehensive-online-holdout-corpus.jsonl"
)
COMPREHENSIVE_SOURCES_PATH = (
    OUTPUT_DIRECTORY / "comprehensive-online-holdout-sources.json"
)
CACHE_DIRECTORY = Path("/tmp/osg-online-holdout-cache")

HUGGING_FACE_ROWS_URL = "https://datasets-server.huggingface.co/rows"
ASAP_TEST_URL = (
    "https://raw.githubusercontent.com/Meituan-Dianping/asap/"
    f"{ASAP_COMMIT}/data/test.csv"
)
ENRON_POSITIVE_URL = (
    "https://raw.githubusercontent.com/vseledkin/"
    "enron_intent_dataset_verified/master/intent_pos"
)
ENRON_NEGATIVE_URL = (
    "https://raw.githubusercontent.com/vseledkin/"
    "enron_intent_dataset_verified/master/intent_neg"
)
CPED_TEST_URL = (
    "https://raw.githubusercontent.com/qftie/CPED/main/"
    "data/CPED/test_split.csv"
)
GO_EMOTIONS_TEST_URL = (
    "https://raw.githubusercontent.com/google-research/google-research/"
    "master/goemotions/data/test.tsv"
)
MASSIVE_ARCHIVE_URL = (
    "https://amazon-massive-nlu-dataset.s3.amazonaws.com/"
    "amazon-massive-dataset-1.1.tar.gz"
)
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

TASK_INTENTS = {
    15, 21, 30, 33, 47, 48, 50, 52, 53,
}
QUERY_INTENTS = {
    0, 3, 4, 6, 9, 10, 11, 12, 13, 17, 19, 22, 23, 26, 27,
    32, 37, 38, 39, 42, 44, 49, 55, 57, 59,
}
ENGLISH_TASK_MARKERS = (
    "please ",
    "can you",
    "could you",
    "i request",
    "i am requesting",
    "i would like",
    "send me",
    "provide me",
)
CHINESE_TASK_MARKERS = ("请", "麻烦", "要求", "希望你", "能否", "可以帮")
CHINESE_ACTION_MARKERS = (
    "请",
    "提醒",
    "添加",
    "安排",
    "设置",
    "删除",
    "取消",
    "发送",
    "发到",
    "邮件",
    "告诉",
    "记录",
    "创建",
    "清单",
    "列表",
    "发布",
    "回复",
    "帮我",
    "联系",
    "把",
)
SENSITIVE_PATTERN = re.compile(
    r"(?:[\w.+-]+@[\w.-]+\.\w+)|(?:\+?\d[\d ()-]{8,}\d)",
    re.IGNORECASE,
)
CHINESE_PERSONAL_DATA_PATTERN = re.compile(
    r"(?:工牌|姓名|名叫|手机号|电话号码|微信号|身份证|QQ号)"
)
GITHUB_TASK_START_PATTERN = re.compile(
    r"^(?:add|allow|build|change|create|enable|"
    r"expose|extend|implement|improve|introduce|make|move|"
    r"provide|refactor|remove|rename|replace|support|update|upgrade|use)\b",
    re.IGNORECASE,
)
GITHUB_BUG_SIGNAL_PATTERN = re.compile(
    r"\b(?:404|bug|crash|error|fail(?:ed|ing|s|ure)?|incorrect|leak|"
    r"missing|not working|regression)\b",
    re.IGNORECASE,
)
ENGLISH_QUESTION_START_PATTERN = re.compile(
    r"^(?:what|when|where|which|who|why|how|can|could|would|do|does|"
    r"did|has|have|is|are|will|should)\b",
    re.IGNORECASE,
)
ENGLISH_INVITATION_PATTERN = re.compile(
    r"\b(?:join us|would you like to|are you available|we should go|"
    r"come (?:over|along|by|to)|meet us|having you join|"
    r"you(?: are|'re) invited|join (?:the|our) (?:call|meeting|event)|"
    r"(?:we can|could we|would you like to) meet)\b",
    re.IGNORECASE,
)
ENGLISH_SCHEDULE_PATTERN = re.compile(
    r"\b(?:reschedule|what time|which day|does .+ work|"
    r"available (?:on|at)|move (?:the|our) meeting|"
    r"(?:monday|tuesday|wednesday|thursday|friday).{0,20}\bor\b.{0,20}"
    r"(?:monday|tuesday|wednesday|thursday|friday)|"
    r"(?:call|meet|meeting).{0,20}\b(?:at|on)\b.{0,20}\bor\b|"
    r"if it works better|delay .{0,20}\buntil\b)\b",
    re.IGNORECASE,
)
ENGLISH_DECISION_PATTERN = re.compile(
    r"\b(?:i approve|i choose|let['’]?s go with|go ahead|"
    r"proceed with|confirmed|we decided)\b",
    re.IGNORECASE,
)
ENGLISH_FOLLOW_UP_PATTERN = re.compile(
    r"\b(?:remind me|follow up|follow-up|check back|circle back|"
    r"don['’]?t forget|next step)\b",
    re.IGNORECASE,
)
ENGLISH_BLESSING_PATTERN = re.compile(
    r"\b(?:happy birthday|happy new year|merry christmas|happy holidays|"
    r"best wishes|good luck|congratulations|congrats|wishing you|"
    r"wish (?:you|him|her|them|everyone)|may you|"
    r"wonderful and prosperous year)\b",
    re.IGNORECASE,
)
ENGLISH_SURFACE_QUESTION_PATTERN = re.compile(
    r"\?$|^(?:what|when|where|which|who|why|how|can|could|would|"
    r"do|does|did|has|have|is|are|will|should)\b",
    re.IGNORECASE,
)
CHINESE_INVITATION_PATTERN = re.compile(
    r"(?:要不要|愿不愿意|来不来|有空吗|约一下|约你|叫你来|"
    r"你一定要到|请你参加|欢迎来|邀请|"
    r"一起(?:去|吃|喝|看|参加|见|聚))"
)
CHINESE_SCHEDULE_PATTERN = re.compile(
    r"(?:(?:改到|改成|改期|几点|什么时候|哪天|有空|方便).{0,16}"
    r"(?:见面|开会|碰面|约|吃饭|出发)|"
    r"(?:周[一二三四五六日天]|星期[一二三四五六日天]|明天|后天|今晚)"
    r".{0,16}(?:还是|或者|或).{0,16}|时间随你定)"
)
CHINESE_DECISION_PATTERN = re.compile(
    r"(?:我决定|我们决定|决定采用|我选|就按|同意|批准|"
    r"确定用|采取.{0,8}方案|可以开始|就这么定|成交)"
)
CHINESE_FOLLOW_UP_PATTERN = re.compile(
    r"(?:提醒|别忘|记得|回头|跟进|下一步)"
)
CHINESE_BLESSING_PATTERN = re.compile(
    r"(?:生日快乐|新年快乐|节日快乐|恭喜|"
    r"预祝|(?<!庆)祝(?:你|您|大家|我们|他|她))"
)
CHINESE_SURFACE_QUESTION_PATTERN = re.compile(
    r"(?:[吗呢么？]$|^(?:怎么|为什么|哪|谁|什么|是否|能否|"
    r"可以|你能|有没有|是不是))"
)


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--seed", type=int, default=SEED)
    parser.add_argument(
        "--profile",
        choices=("focused", "comprehensive"),
        default="focused",
    )
    parser.add_argument("--output", type=Path)
    parser.add_argument("--sources", type=Path)
    arguments = parser.parse_args()
    if arguments.output is None:
        arguments.output = (
            COMPREHENSIVE_CORPUS_PATH
            if arguments.profile == "comprehensive"
            else CORPUS_PATH
        )
    if arguments.sources is None:
        arguments.sources = (
            COMPREHENSIVE_SOURCES_PATH
            if arguments.profile == "comprehensive"
            else SOURCES_PATH
        )
    return arguments


def fetch_bytes(url: str) -> bytes:
    cache_key = hashlib.sha256(url.encode()).hexdigest()
    cache_path = CACHE_DIRECTORY / cache_key
    if cache_path.is_file():
        return cache_path.read_bytes()

    request = urllib.request.Request(
        url,
        headers={"User-Agent": "OSGKeyboard-online-holdout/1.0"},
    )
    for attempt in range(5):
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                content = response.read()
                CACHE_DIRECTORY.mkdir(parents=True, exist_ok=True)
                cache_path.write_bytes(content)
                time.sleep(0.4)
                return content
        except HTTPError as error:
            if error.code != 429 or attempt == 4:
                raise
            retry_after = int(error.headers.get("Retry-After", "3"))
            time.sleep(max(retry_after, 3 * (attempt + 1)))
        except (URLError, TimeoutError):
            if attempt == 4:
                raise
            time.sleep(2 * (attempt + 1))
    raise RuntimeError(f"Unable to download {url}")


def fetch_hugging_face_rows(
    dataset: str,
    config: str,
    split: str,
    offset: int,
    length: int = 100,
) -> list[dict]:
    query = urllib.parse.urlencode(
        {
            "dataset": dataset,
            "config": config,
            "split": split,
            "offset": offset,
            "length": length,
        }
    )
    payload = json.loads(fetch_bytes(f"{HUGGING_FACE_ROWS_URL}?{query}"))
    return payload["rows"]


def normalized_text(value: str) -> str:
    return " ".join(value.replace("\u0000", " ").split()).strip()


def is_eligible_text(text: str, minimum: int, maximum: int) -> bool:
    return (
        minimum <= len(text) <= maximum
        and not SENSITIVE_PATTERN.search(text)
        and text.count("XXXX") <= 8
    )


def base_record(
    *,
    record_id: str,
    family: str,
    language: str,
    text: str,
    source_dataset: str,
    source_url: str,
    source_license: str,
    task: bool = False,
    question: bool = False,
    invitation: bool = False,
    complaint: bool = False,
    schedule_negotiation: bool = False,
    confirmation_decision: bool = False,
    follow_up_reminder: bool = False,
    blessing: bool = False,
    replyable: bool = True,
    sentiment: str = "neutral",
    split: str = "onlineRealHoldout",
    source_author: str | None = None,
    source_author_url: str | None = None,
) -> dict:
    record = {
        "id": record_id,
        "family": family,
        "language": language,
        "text": text,
        "task": task,
        "question": question,
        "invitation": invitation,
        "complaint": complaint,
        "scheduleNegotiation": schedule_negotiation,
        "confirmationDecision": confirmation_decision,
        "followUpReminder": follow_up_reminder,
        "blessing": blessing,
        "replyable": replyable,
        "sentiment": sentiment,
        "split": split,
        "sourceDataset": source_dataset,
        "sourceURL": source_url,
        "sourceLicense": source_license,
    }
    if source_author:
        record["sourceAuthor"] = source_author
    if source_author_url:
        record["sourceAuthorURL"] = source_author_url
    return record


def complaint_records(
    rng: random.Random,
    count: int = 40,
    offsets: tuple[int, ...] = (1200, 8800, 17500, 29000),
) -> list[dict]:
    rows: list[dict] = []
    for offset in offsets:
        rows.extend(
            fetch_hugging_face_rows(
                "hpe-ai/customer-complaints",
                "default",
                "train",
                offset,
            )
        )

    candidates: list[dict] = []
    seen: set[str] = set()
    for item in rows:
        source = item["row"]
        text = normalized_text(source["Consumer_complaint_narrative"] or "")
        fingerprint = text.casefold()
        if fingerprint in seen or not is_eligible_text(text, 40, 700):
            continue
        seen.add(fingerprint)
        lowered = text.casefold()
        task = any(marker in lowered for marker in ENGLISH_TASK_MARKERS)
        complaint_id = str(source["Complaint_ID"])
        candidates.append(
            base_record(
                record_id=f"online-cfpb-{complaint_id}",
                family="online_cfpb_complaint",
                language="en",
                text=text,
                task=task,
                question="?" in text,
                complaint=True,
                sentiment="negative",
                source_dataset="CFPB via hpe-ai/customer-complaints",
                source_url=(
                    "https://www.consumerfinance.gov/data-research/"
                    f"consumer-complaints/search/detail/{complaint_id}"
                ),
                source_license="CC0-1.0 source / Apache-2.0 mirror",
            )
        )
    if len(candidates) < count:
        raise RuntimeError(f"Only found {len(candidates)} CFPB samples")
    return rng.sample(candidates, count)


def asap_records(
    rng: random.Random,
    count: int = 40,
) -> list[dict]:
    content = fetch_bytes(ASAP_TEST_URL).decode("utf-8-sig")
    candidates: list[dict] = []
    seen: set[str] = set()
    for row in csv.DictReader(io.StringIO(content)):
        text = normalized_text(row["review"])
        fingerprint = text.casefold()
        if fingerprint in seen or not is_eligible_text(text, 20, 260):
            continue
        if float(row["star"]) > 2:
            continue
        if CHINESE_PERSONAL_DATA_PATTERN.search(text):
            continue
        if not any(value == "-1" for value in list(row.values())[3:]):
            continue
        seen.add(fingerprint)
        task = any(marker in text for marker in CHINESE_TASK_MARKERS)
        row_id = row["id"]
        candidates.append(
            base_record(
                record_id=f"online-asap-{row_id}",
                family="online_asap_complaint",
                language="zh-Hans",
                text=text,
                task=task,
                question="？" in text or "?" in text,
                complaint=True,
                sentiment="negative",
                source_dataset="Meituan-Dianping/ASAP test",
                source_url=(
                    "https://github.com/Meituan-Dianping/asap/blob/"
                    f"{ASAP_COMMIT}/data/test.csv#row-{row_id}"
                ),
                source_license="Apache-2.0",
            )
        )
    if len(candidates) < count:
        raise RuntimeError(f"Only found {len(candidates)} ASAP samples")
    return rng.sample(candidates, count)


def massive_records(
    rng: random.Random,
    *,
    config: str,
    language: str,
    task_count: int,
) -> list[dict]:
    rows: list[dict] = []
    for offset in range(0, 2900, 200):
        rows.extend(
            fetch_hugging_face_rows(
                "AmazonScience/massive",
                config,
                "test",
                offset,
            )
        )

    task_candidates: list[dict] = []
    query_candidates: list[dict] = []
    seen: set[str] = set()
    for item in rows:
        source = item["row"]
        text = normalized_text(source["utt"])
        fingerprint = text.casefold()
        if fingerprint in seen or not is_eligible_text(text, 4, 220):
            continue
        seen.add(fingerprint)
        intent = int(source["intent"])
        is_task = intent in TASK_INTENTS
        is_query = intent in QUERY_INTENTS
        if not is_task and not is_query:
            continue
        if is_task and language == "zh-Hans":
            if not any(marker in text for marker in CHINESE_ACTION_MARKERS):
                continue
        family = "online_massive_task" if is_task else "online_massive_query_boundary"
        record = base_record(
            record_id=f"online-massive-{config}-{source['id']}",
            family=family,
            language=language,
            text=text,
            task=is_task,
            question=is_query,
            complaint=False,
            sentiment="neutral",
            source_dataset=f"AmazonScience/MASSIVE {config} test",
            source_url=(
                "https://huggingface.co/datasets/AmazonScience/massive"
                f"?row={item['row_idx']}"
            ),
            source_license="CC-BY-4.0",
        )
        (task_candidates if is_task else query_candidates).append(record)

    if len(task_candidates) < task_count or len(query_candidates) < 20:
        raise RuntimeError(
            f"Insufficient MASSIVE {config} samples: "
            f"task={len(task_candidates)} query={len(query_candidates)}"
        )
    return rng.sample(task_candidates, task_count) + rng.sample(query_candidates, 20)


def github_task_records(rng: random.Random) -> list[dict]:
    rows: list[dict] = []
    for offset in range(0, 4000, 100):
        rows.extend(
            fetch_hugging_face_rows(
                "Sulak2020/github-issues-multirepo-datasets-Sulakshana",
                "default",
                "train",
                offset,
            )
        )

    candidates: list[dict] = []
    seen: set[str] = set()
    for item in rows:
        source = item["row"]
        if source["is_pull_request"]:
            continue
        text = normalized_text(source["title"])
        normalized_title = re.sub(r"^(?:\[[^\]]+\]\s*)+", "", text)
        fingerprint = text.casefold()
        if fingerprint in seen or not is_eligible_text(text, 8, 180):
            continue
        if not GITHUB_TASK_START_PATTERN.search(normalized_title):
            continue
        if GITHUB_BUG_SIGNAL_PATTERN.search(normalized_title):
            continue
        seen.add(fingerprint)
        author = source.get("user") or {}
        candidates.append(
            base_record(
                record_id=f"online-github-{source['id']}",
                family="online_github_task",
                language="en",
                text=text,
                task=True,
                question="?" in text,
                complaint=False,
                sentiment="neutral",
                source_dataset="Sulak2020 GitHub issues multi-repo dataset",
                source_url=source["html_url"],
                source_license="CC-BY-4.0 dataset / attributed source issue",
                source_author=author.get("login"),
                source_author_url=author.get("html_url"),
            )
        )
    if len(candidates) < 40:
        raise RuntimeError(f"Only found {len(candidates)} GitHub task samples")
    return rng.sample(candidates, 40)


def comprehensive_massive_records(
    *,
    config: str,
    language: str,
) -> list[dict]:
    intent_indexes = {
        name: index for index, name in enumerate(MASSIVE_INTENT_NAMES)
    }
    archive_bytes = fetch_bytes(MASSIVE_ARCHIVE_URL)
    archive = tarfile.open(fileobj=io.BytesIO(archive_bytes), mode="r:gz")
    member = next(
        (
            candidate
            for candidate in archive.getmembers()
            if candidate.isfile()
            and candidate.name.endswith(f"/{config}.jsonl")
        ),
        None,
    )
    if member is None:
        raise RuntimeError(f"MASSIVE archive is missing {config}.jsonl")
    extracted = archive.extractfile(member)
    if extracted is None:
        raise RuntimeError(f"Unable to read MASSIVE {config}.jsonl")

    records: list[dict] = []
    seen: set[str] = set()
    row_index = 0
    for raw_line in extracted:
        source = json.loads(raw_line)
        if source["partition"] != "test":
            continue
        text = normalized_text(source["utt"])
        fingerprint = text.casefold()
        if fingerprint in seen or not is_eligible_text(text, 4, 220):
            continue
        seen.add(fingerprint)
        intent = intent_indexes[source["intent"]]
        is_reminder = (
            intent == 48
            or bool(ENGLISH_FOLLOW_UP_PATTERN.search(text))
            if language == "en"
            else intent == 48
            or bool(CHINESE_FOLLOW_UP_PATTERN.search(text))
        )
        is_task = intent in TASK_INTENTS and not is_reminder
        sentiment = (
            "negative"
            if intent == 7
            else "positive"
            if intent == 43
            else "neutral"
        )
        records.append(
            base_record(
                record_id=f"comprehensive-massive-{config}-{source['id']}",
                family=f"online_massive_intent_{intent}",
                language=language,
                text=text,
                task=is_task,
                question=(
                    intent in QUERY_INTENTS
                    or bool(ENGLISH_SURFACE_QUESTION_PATTERN.search(text))
                    if language == "en"
                    else intent in QUERY_INTENTS
                    or bool(CHINESE_SURFACE_QUESTION_PATTERN.search(text))
                ),
                follow_up_reminder=is_reminder,
                sentiment=sentiment,
                source_dataset=f"AmazonScience/MASSIVE {config} test",
                source_url=(
                    "https://huggingface.co/datasets/AmazonScience/massive"
                    f"?row={row_index}"
                ),
                source_license="CC-BY-4.0",
                split="comprehensiveOnlineHoldout",
            )
        )
        row_index += 1
    archive.close()
    return records


def enron_intent_records() -> list[dict]:
    records: list[dict] = []
    for is_actionable, url, source_name in (
        (True, ENRON_POSITIVE_URL, "intent_pos"),
        (False, ENRON_NEGATIVE_URL, "intent_neg"),
    ):
        lines = fetch_bytes(url).decode("utf-8").splitlines()
        for index, raw_text in enumerate(lines, start=1):
            text = normalized_text(raw_text)
            if not is_eligible_text(text, 4, 500):
                continue
            lowered = text.casefold()
            invitation = bool(ENGLISH_INVITATION_PATTERN.search(text))
            schedule = bool(ENGLISH_SCHEDULE_PATTERN.search(text))
            follow_up = bool(ENGLISH_FOLLOW_UP_PATTERN.search(text))
            question = (
                bool(ENGLISH_SURFACE_QUESTION_PATTERN.search(text))
            )
            task = is_actionable and (
                any(marker in lowered for marker in ENGLISH_TASK_MARKERS)
                or bool(GITHUB_TASK_START_PATTERN.search(text))
                or follow_up
            )
            records.append(
                base_record(
                    record_id=f"comprehensive-enron-{source_name}-{index}",
                    family=f"online_enron_{source_name}",
                    language="en",
                    text=text,
                    task=task,
                    question=question,
                    invitation=invitation,
                    schedule_negotiation=schedule,
                    confirmation_decision=bool(
                        ENGLISH_DECISION_PATTERN.search(text)
                    ),
                    follow_up_reminder=follow_up,
                    blessing=bool(ENGLISH_BLESSING_PATTERN.search(text)),
                    replyable=is_actionable,
                    source_dataset="Verified Enron Intent Dataset",
                    source_url=(
                        "https://github.com/vseledkin/"
                        "enron_intent_dataset_verified/blob/master/"
                        f"{source_name}#L{index}"
                    ),
                    source_license="MIT / public Enron source corpus",
                    split="comprehensiveOnlineHoldout",
                )
            )
    return records


def cped_records() -> list[dict]:
    content = fetch_bytes(CPED_TEST_URL).decode("utf-8-sig")
    records: list[dict] = []
    complaint_pattern = re.compile(
        r"(?:怎么|为什么|一直|又|根本|受不了|太差|坏了|错了|"
        r"没用|不行|骗人|故障|问题)"
    )
    replyable_dialogue_acts = {
        "question",
        "command",
        "statement-opinion",
        "statement-non-opinion",
        "apology",
        "agreement/acceptance",
        "disagreement",
        "reject",
        "comfort",
    }
    for index, row in enumerate(csv.DictReader(io.StringIO(content)), start=2):
        text = normalized_text(row.get("Utterance") or "")
        if not is_eligible_text(text, 2, 220):
            continue
        dialogue_act = row["DA"]
        sentiment = row["Sentiment"]
        emotion = row["Emotion"]
        invitation = bool(CHINESE_INVITATION_PATTERN.search(text))
        schedule = bool(CHINESE_SCHEDULE_PATTERN.search(text))
        follow_up = bool(CHINESE_FOLLOW_UP_PATTERN.search(text))
        complaint = (
            sentiment == "negative"
            and emotion in {"angry", "disgusted", "depressed", "worried"}
            and bool(complaint_pattern.search(text))
        )
        records.append(
            base_record(
                record_id=f"comprehensive-cped-{row['Utterance_ID']}",
                family=f"online_cped_{dialogue_act.replace('/', '_')}",
                language="zh-Hans",
                text=text,
                task=dialogue_act == "command",
                question=(
                    dialogue_act == "question"
                    or bool(CHINESE_SURFACE_QUESTION_PATTERN.search(text))
                ),
                invitation=invitation,
                complaint=complaint,
                schedule_negotiation=schedule,
                confirmation_decision=bool(
                    CHINESE_DECISION_PATTERN.search(text)
                ),
                follow_up_reminder=follow_up,
                blessing=bool(CHINESE_BLESSING_PATTERN.search(text)),
                replyable=dialogue_act in replyable_dialogue_acts,
                sentiment=(
                    sentiment
                    if sentiment in {"positive", "neutral", "negative"}
                    else "neutral"
                ),
                source_dataset="CPED test split",
                source_url=(
                    "https://github.com/qftie/CPED/blob/main/"
                    f"data/CPED/test_split.csv#L{index}"
                ),
                source_license="Apache-2.0",
                split="comprehensiveOnlineHoldout",
            )
        )
    return records


def go_emotions_records() -> list[dict]:
    positive_labels = {0, 1, 4, 5, 13, 15, 17, 18, 20, 21, 23}
    negative_labels = {2, 3, 9, 10, 11, 12, 14, 16, 19, 24, 25}
    complaint_pattern = re.compile(
        r"\b(?:problem|issue|fail(?:ed|ing|s|ure)?|broken|"
        r"not working|doesn['’]?t work|terrible service|worst service)\b",
        re.IGNORECASE,
    )
    records: list[dict] = []
    content = fetch_bytes(GO_EMOTIONS_TEST_URL).decode("utf-8")
    for index, line in enumerate(content.splitlines(), start=1):
        columns = line.split("\t")
        if len(columns) != 3:
            continue
        raw_text, raw_labels, source_id = columns
        text = normalized_text(raw_text)
        if not is_eligible_text(text, 3, 500):
            continue
        labels = {int(value) for value in raw_labels.split(",")}
        has_positive = bool(labels & positive_labels)
        has_negative = bool(labels & negative_labels)
        sentiment = (
            "positive"
            if has_positive and not has_negative
            else "negative"
            if has_negative and not has_positive
            else "neutral"
        )
        lowered = text.casefold()
        records.append(
            base_record(
                record_id=f"comprehensive-goemotions-{source_id}",
                family="online_goemotions_reddit",
                language="en",
                text=text,
                task=any(
                    marker in lowered for marker in ENGLISH_TASK_MARKERS
                ),
                question=bool(ENGLISH_SURFACE_QUESTION_PATTERN.search(text)),
                complaint=(
                    has_negative
                    and bool(complaint_pattern.search(text))
                ),
                blessing=bool(ENGLISH_BLESSING_PATTERN.search(text)),
                sentiment=sentiment,
                source_dataset="Google Research GoEmotions test",
                source_url=(
                    "https://github.com/google-research/google-research/"
                    f"blob/master/goemotions/data/test.tsv#L{index}"
                ),
                source_license="Apache-2.0",
                split="comprehensiveOnlineHoldout",
            )
        )
    return records


def comprehensive_github_records() -> list[dict]:
    records: list[dict] = []
    for offset in range(0, 4000, 100):
        for item in fetch_hugging_face_rows(
            "Sulak2020/github-issues-multirepo-datasets-Sulakshana",
            "default",
            "train",
            offset,
        ):
            source = item["row"]
            if source["is_pull_request"]:
                continue
            text = normalized_text(source["title"])
            if not is_eligible_text(text, 5, 220):
                continue
            normalized_title = re.sub(r"^(?:\[[^\]]+\]\s*)+", "", text)
            complaint = bool(GITHUB_BUG_SIGNAL_PATTERN.search(normalized_title))
            author = source.get("user") or {}
            records.append(
                base_record(
                    record_id=f"comprehensive-github-{source['id']}",
                    family="online_github_issue_title",
                    language="en",
                    text=text,
                    task=(
                        bool(GITHUB_TASK_START_PATTERN.search(normalized_title))
                        and not complaint
                    ),
                    question=bool(
                        ENGLISH_SURFACE_QUESTION_PATTERN.search(text)
                    ),
                    complaint=complaint,
                    schedule_negotiation=bool(
                        ENGLISH_SCHEDULE_PATTERN.search(text)
                    ),
                    confirmation_decision=bool(
                        ENGLISH_DECISION_PATTERN.search(text)
                    ),
                    follow_up_reminder=bool(
                        ENGLISH_FOLLOW_UP_PATTERN.search(text)
                    ),
                    blessing=bool(ENGLISH_BLESSING_PATTERN.search(text)),
                    sentiment="negative" if complaint else "neutral",
                    source_dataset=(
                        "Sulak2020 GitHub issues multi-repo dataset"
                    ),
                    source_url=source["html_url"],
                    source_license=(
                        "CC-BY-4.0 dataset / attributed source issue"
                    ),
                    split="comprehensiveOnlineHoldout",
                    source_author=author.get("login"),
                    source_author_url=author.get("html_url"),
                )
            )
            for comment_index, raw_comment in enumerate(
                source.get("comments") or [],
                start=1,
            ):
                comment = normalized_text(raw_comment)
                if not is_eligible_text(comment, 4, 500):
                    continue
                invitation = bool(
                    ENGLISH_INVITATION_PATTERN.search(comment)
                )
                schedule = bool(ENGLISH_SCHEDULE_PATTERN.search(comment))
                decision = bool(ENGLISH_DECISION_PATTERN.search(comment))
                follow_up = bool(ENGLISH_FOLLOW_UP_PATTERN.search(comment))
                blessing = bool(ENGLISH_BLESSING_PATTERN.search(comment))
                if not any(
                    (invitation, schedule, decision, follow_up, blessing)
                ):
                    continue
                records.append(
                    base_record(
                        record_id=(
                            f"comprehensive-github-{source['id']}-"
                            f"comment-{comment_index}"
                        ),
                        family="online_github_issue_comment_intent",
                        language="en",
                        text=comment,
                        task=follow_up,
                        question=bool(
                            ENGLISH_SURFACE_QUESTION_PATTERN.search(comment)
                        ),
                        invitation=invitation,
                        schedule_negotiation=schedule,
                        confirmation_decision=decision,
                        follow_up_reminder=follow_up,
                        blessing=blessing,
                        source_dataset=(
                            "Sulak2020 GitHub issues multi-repo dataset"
                        ),
                        source_url=source["html_url"],
                        source_license=(
                            "CC-BY-4.0 dataset / attributed source issue"
                        ),
                        split="comprehensiveOnlineHoldout",
                    )
                )
    return records


def deduplicated(records: list[dict]) -> list[dict]:
    result: list[dict] = []
    seen: set[str] = set()
    for record in records:
        fingerprint = normalized_text(record["text"]).casefold()
        if fingerprint in seen:
            continue
        seen.add(fingerprint)
        result.append(record)
    return result


def excluding_training_overlaps(records: list[dict]) -> list[dict]:
    if not TRAINING_CORPUS_PATH.is_file():
        return records
    training_texts = {
        normalized_text(json.loads(line)["text"]).casefold()
        for line in TRAINING_CORPUS_PATH.read_text(encoding="utf-8").splitlines()
        if line.strip()
    }
    return [
        record
        for record in records
        if normalized_text(record["text"]).casefold() not in training_texts
    ]


def comprehensive_records(rng: random.Random) -> list[dict]:
    records = (
        complaint_records(
            rng,
            count=250,
            offsets=tuple(range(0, 30000, 3000)),
        )
        + asap_records(rng, count=120)
        + comprehensive_massive_records(config="en-US", language="en")
        + comprehensive_massive_records(config="zh-CN", language="zh-Hans")
        + enron_intent_records()
        + cped_records()
        + go_emotions_records()
        + comprehensive_github_records()
    )
    return excluding_training_overlaps(deduplicated(records))


def record_count(
    records: list[dict],
    source_prefix: str,
) -> int:
    return sum(
        record["sourceDataset"].startswith(source_prefix)
        for record in records
    )


def focused_source_summary(
    records: list[dict],
    serialized: str,
    seed: int,
) -> dict:
    return {
        "containsProjectUserClipboardData": False,
        "corpusSHA256": hashlib.sha256(serialized.encode()).hexdigest(),
        "generatedFromOnlineSources": True,
        "labelDefinition": {
            "complaint": (
                "A user reports a negative experience, failure, or grievance."
            ),
            "task": (
                "An actionable work request suitable for todo extraction; "
                "device-control commands are excluded."
            ),
        },
        "labelCorrection": {
            "reason": (
                "Replaced generic MASSIVE device-control commands with "
                "attributed GitHub work requests."
            ),
            "supersededCorpusSHA256": (
                "2962b6d28fe0ef551ae46f62accbde93c9da7f0fad93451c06c2e226350aad33"
            ),
        },
        "recordCount": len(records),
        "seed": seed,
        "sources": [
            {
                "dataset": "CFPB via hpe-ai/customer-complaints",
                "license": "CC0-1.0 source / Apache-2.0 mirror",
                "records": 40,
                "url": (
                    "https://huggingface.co/datasets/"
                    "hpe-ai/customer-complaints"
                ),
            },
            {
                "dataset": "Meituan-Dianping/ASAP",
                "license": "Apache-2.0",
                "records": 40,
                "revision": ASAP_COMMIT,
                "url": "https://github.com/Meituan-Dianping/asap",
            },
            {
                "dataset": "AmazonScience/MASSIVE",
                "license": "CC-BY-4.0",
                "records": 80,
                "url": (
                    "https://huggingface.co/datasets/"
                    "AmazonScience/massive"
                ),
            },
            {
                "dataset": "Sulak2020 GitHub issues multi-repo dataset",
                "license": "CC-BY-4.0 with per-record attribution",
                "records": 40,
                "url": (
                    "https://huggingface.co/datasets/"
                    "Sulak2020/github-issues-multirepo-datasets-Sulakshana"
                ),
            },
        ],
    }


def comprehensive_source_summary(
    records: list[dict],
    serialized: str,
    seed: int,
) -> dict:
    intents = (
        "task",
        "question",
        "invitation",
        "complaint",
        "scheduleNegotiation",
        "confirmationDecision",
        "followUpReminder",
        "blessing",
        "replyable",
    )
    languages = ("en", "zh-Hans")
    coverage = {
        intent: {
            language: {
                "positive": sum(
                    record["language"] == language
                    and bool(record[intent])
                    for record in records
                ),
                "negative": sum(
                    record["language"] == language
                    and not bool(record[intent])
                    for record in records
                ),
            }
            for language in languages
        }
        for intent in intents
    }
    sentiment_coverage = {
        language: {
            label: sum(
                record["language"] == language
                and record["sentiment"] == label
                for record in records
            )
            for label in ("positive", "neutral", "negative")
        }
        for language in languages
    }
    return {
        "containsProjectUserClipboardData": False,
        "corpusSHA256": hashlib.sha256(serialized.encode()).hexdigest(),
        "generatedFromOnlineSources": True,
        "profile": "comprehensive",
        "recordCount": len(records),
        "seed": seed,
        "coverage": coverage,
        "sentimentCoverage": sentiment_coverage,
        "labelingMethod": (
            "Original dataset labels are retained where available. Product "
            "intents not present in source schemas use conservative lexical "
            "mapping; metrics must therefore be read with per-source results "
            "and label-coverage counts."
        ),
        "labelCorrection": {
            "reason": (
                "An initial prelabel audit found obvious surface questions, "
                "invitations, schedule alternatives, reminders, and wishes "
                "that source intent schemas did not encode. A second audit "
                "removed quoted, sarcastic, and substring-only blessing "
                "matches. Deterministic label rules were corrected before "
                "the frozen evaluation."
            ),
            "supersededCorpusSHA256": [
                "36f736f69e0c9ac42262d2b57640f9889534ffdc6e70da67fda6f41d7211b2f9",
                "baffdfff4b5436810c45d92d28c5885d8ed475b878531220852ae6f2a55011e4",
            ],
        },
        "holdoutPolicy": (
            "Frozen online evaluation only. These records are excluded from "
            "training, model selection, and threshold calibration."
        ),
        "sources": [
            {
                "dataset": "CFPB via hpe-ai/customer-complaints",
                "license": "CC0-1.0 source / Apache-2.0 mirror",
                "records": record_count(records, "CFPB"),
                "url": (
                    "https://huggingface.co/datasets/"
                    "hpe-ai/customer-complaints"
                ),
            },
            {
                "dataset": "Meituan-Dianping/ASAP",
                "license": "Apache-2.0",
                "records": record_count(records, "Meituan-Dianping/ASAP"),
                "revision": ASAP_COMMIT,
                "url": "https://github.com/Meituan-Dianping/asap",
            },
            {
                "dataset": "AmazonScience/MASSIVE",
                "license": "CC-BY-4.0",
                "records": record_count(records, "AmazonScience/MASSIVE"),
                "url": (
                    "https://huggingface.co/datasets/"
                    "AmazonScience/massive"
                ),
            },
            {
                "dataset": "Verified Enron Intent Dataset",
                "license": "MIT / public Enron source corpus",
                "records": record_count(
                    records,
                    "Verified Enron Intent Dataset",
                ),
                "url": (
                    "https://github.com/vseledkin/"
                    "enron_intent_dataset_verified"
                ),
            },
            {
                "dataset": "CPED",
                "license": "Apache-2.0",
                "records": record_count(records, "CPED"),
                "url": "https://github.com/qftie/CPED",
            },
            {
                "dataset": "Google Research GoEmotions",
                "license": "Apache-2.0",
                "records": record_count(
                    records,
                    "Google Research GoEmotions",
                ),
                "url": (
                    "https://huggingface.co/datasets/"
                    "google-research-datasets/go_emotions"
                ),
            },
            {
                "dataset": "Sulak2020 GitHub issues multi-repo dataset",
                "license": "CC-BY-4.0 with per-record attribution",
                "records": record_count(
                    records,
                    "Sulak2020 GitHub issues",
                ),
                "url": (
                    "https://huggingface.co/datasets/"
                    "Sulak2020/github-issues-multirepo-datasets-Sulakshana"
                ),
            },
        ],
    }


def main() -> None:
    arguments = parse_arguments()
    rng = random.Random(arguments.seed)
    if arguments.profile == "comprehensive":
        records = comprehensive_records(rng)
    else:
        records = (
            complaint_records(rng)
            + asap_records(rng)
            + github_task_records(rng)
            + massive_records(rng, config="en-US", language="en", task_count=0)
            + massive_records(
                rng,
                config="zh-CN",
                language="zh-Hans",
                task_count=40,
            )
        )
    rng.shuffle(records)

    arguments.output.parent.mkdir(parents=True, exist_ok=True)
    serialized = "".join(
        json.dumps(record, ensure_ascii=False, sort_keys=True) + "\n"
        for record in records
    )
    arguments.output.write_text(serialized, encoding="utf-8")

    source_summary = (
        comprehensive_source_summary(
            records,
            serialized,
            arguments.seed,
        )
        if arguments.profile == "comprehensive"
        else focused_source_summary(
            records,
            serialized,
            arguments.seed,
        )
    )
    arguments.sources.write_text(
        json.dumps(source_summary, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    print(
        "ONLINE_HOLDOUT_DONE "
        f"records={len(records)} seed={arguments.seed} "
        f"sha256={source_summary['corpusSHA256']}"
    )


if __name__ == "__main__":
    main()
