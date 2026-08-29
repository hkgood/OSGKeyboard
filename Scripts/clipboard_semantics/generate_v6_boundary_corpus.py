#!/usr/bin/env python3
"""Generate a deterministic bilingual supplement for taxonomy-v6 boundaries."""

from __future__ import annotations

import argparse
import hashlib
import itertools
import json
import unicodedata
from collections import Counter
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, Iterator, Sequence


OUTPUT_DIRECTORY = Path("ModelTraining/ClipboardSemantics")
DEFAULT_OUTPUT_PATH = OUTPUT_DIRECTORY / "v6-boundary-training-supplement.jsonl"
DEFAULT_SUMMARY_PATH = OUTPUT_DIRECTORY / "v6-boundary-training-supplement-summary.json"
DEFAULT_POSITIVE_PER_INTENT_LANGUAGE = 1_000
DEFAULT_NEGATIVE_PER_INTENT_LANGUAGE = 200
SOURCE_DATASET = "OSGKeyboard taxonomy-v6 deterministic boundary templates"
SOURCE_LICENSE = "OSGKeyboard project license"
SOURCE_REVISION = "v6-boundary-templates-1"
SOURCE_SPLIT = "train"
SAMPLE_WEIGHT = 0.35

NEW_INTENTS = (
    "assistantCommand",
    "informationQuery",
    "systemNotification",
)
HARD_NEGATIVE_INTENTS = ("task", "question", "replyableMessage")
BOUNDARY_INTENTS = NEW_INTENTS + HARD_NEGATIVE_INTENTS
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
KNOWN_LABELS = sorted((*BOUNDARY_INTENTS, "domain"))
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
LANGUAGES = ("en", "zh-Hans")
CATEGORY_OFFSETS = {
    "assistantCommand": 0,
    "informationQuery": 4,
    "systemNotification": 8,
    "task": 0,
    "question": 4,
    "replyableMessage": 8,
}


@dataclass(frozen=True)
class DomainSlots:
    """Finite, project-authored slots for one product-policy domain."""

    subjects_en: tuple[str, ...]
    subjects_zh: tuple[str, ...]
    facts_en: tuple[str, ...]
    facts_zh: tuple[str, ...]
    services_en: tuple[str, ...]
    services_zh: tuple[str, ...]
    providers_en: tuple[str, ...]
    providers_zh: tuple[str, ...]
    events_en: tuple[str, ...]
    events_zh: tuple[str, ...]


DOMAIN_SLOTS: dict[str, DomainSlots] = {
    "finance": DomainSlots(
        ("savings account", "credit card", "monthly budget", "insurance claim"),
        ("储蓄账户", "信用卡", "月度预算", "保险理赔"),
        ("current balance", "exchange rate", "payment status", "claim progress"),
        ("当前余额", "汇率", "付款状态", "理赔进度"),
        ("transfer funds", "replace the card", "submit the claim", "buy the fund"),
        ("转账", "补办卡片", "提交理赔", "购买基金"),
        ("the bank", "the card issuer", "the insurer", "the broker"),
        ("银行", "发卡行", "保险公司", "券商"),
        ("was approved", "was declined", "is being reviewed", "needs verification"),
        ("已获批准", "已被拒绝", "正在审核", "需要验证"),
    ),
    "travel": DomainSlots(
        ("morning flight", "hotel booking", "train ticket", "airport transfer"),
        ("早班航班", "酒店预订", "火车票", "机场接送"),
        ("departure time", "platform number", "booking status", "delay estimate"),
        ("出发时间", "站台编号", "预订状态", "延误时长"),
        ("book the flight", "reserve the hotel", "change the ticket", "order a taxi"),
        ("预订航班", "预订酒店", "改签车票", "预约出租车"),
        ("the airline", "the hotel", "the railway", "the taxi company"),
        ("航空公司", "酒店", "铁路客服", "出租车公司"),
        ("was confirmed", "was delayed", "changed gates", "was cancelled"),
        ("已确认", "已延误", "已变更登机口", "已取消"),
    ),
    "calendar": DomainSlots(
        ("team meeting", "dentist appointment", "morning alarm", "project reminder"),
        ("团队会议", "牙医预约", "早晨闹钟", "项目提醒"),
        ("start time", "meeting location", "next occurrence", "attendee list"),
        ("开始时间", "会议地点", "下次时间", "参与者名单"),
        ("reserve a meeting room", "reschedule the appointment", "invite the team", "book the venue"),
        ("预订会议室", "改约时间", "邀请团队", "预订场地"),
        ("the office", "the clinic", "the event host", "the venue"),
        ("办公室", "诊所", "活动主办方", "场地方"),
        ("was added", "was moved", "has a conflict", "starts soon"),
        ("已添加", "已改期", "存在冲突", "即将开始"),
    ),
    "communication": DomainSlots(
        ("work inbox", "family group", "video call", "contact list"),
        ("工作收件箱", "家庭群聊", "视频通话", "联系人列表"),
        ("unread count", "call duration", "delivery status", "contact details"),
        ("未读数量", "通话时长", "送达状态", "联系信息"),
        ("send the parcel", "print the invitation", "deliver the letter", "arrange an interpreter"),
        ("寄送包裹", "印刷邀请函", "投递信件", "安排翻译"),
        ("the courier", "the print shop", "the post office", "the agency"),
        ("快递公司", "印刷店", "邮局", "服务机构"),
        ("finished syncing", "lost connection", "was delivered", "needs permission"),
        ("已同步完成", "连接已断开", "已送达", "需要权限"),
    ),
    "media": DomainSlots(
        ("jazz playlist", "evening podcast", "photo album", "news channel"),
        ("爵士歌单", "晚间播客", "照片相册", "新闻频道"),
        ("episode length", "release date", "track title", "download progress"),
        ("单集时长", "发布日期", "曲目名称", "下载进度"),
        ("buy the album", "rent the film", "print the photos", "book the studio"),
        ("购买专辑", "租赁影片", "冲印照片", "预订录音棚"),
        ("the music store", "the cinema service", "the photo lab", "the studio"),
        ("音乐商店", "影视服务商", "照片冲印店", "录音棚"),
        ("finished downloading", "is unavailable", "resumed playing", "was removed"),
        ("已下载完成", "暂不可用", "已继续播放", "已被移除"),
    ),
    "smartHome": DomainSlots(
        ("living-room lights", "front-door lock", "bedroom thermostat", "robot vacuum"),
        ("客厅灯", "前门门锁", "卧室温控器", "扫地机器人"),
        ("power level", "lock status", "room temperature", "cleaning progress"),
        ("电量", "门锁状态", "室温", "清扫进度"),
        ("repair the lock", "install the thermostat", "service the vacuum", "replace the sensor"),
        ("维修门锁", "安装温控器", "保养扫地机", "更换传感器"),
        ("the locksmith", "the installer", "the repair shop", "the electrician"),
        ("锁匠", "安装人员", "维修点", "电工"),
        ("went offline", "is back online", "detected motion", "finished cleaning"),
        ("已离线", "已恢复在线", "检测到移动", "已完成清扫"),
    ),
    "shopping": DomainSlots(
        ("grocery list", "shoe order", "gift basket", "store coupon"),
        ("购物清单", "鞋子订单", "礼品篮", "商店优惠券"),
        ("current price", "stock level", "delivery date", "discount amount"),
        ("当前价格", "库存数量", "送达日期", "折扣金额"),
        ("place the order", "exchange the shoes", "wrap the gift", "schedule delivery"),
        ("下单", "换鞋", "包装礼物", "预约配送"),
        ("the retailer", "the shoe store", "the gift shop", "the courier"),
        ("零售商", "鞋店", "礼品店", "快递公司"),
        ("was shipped", "is out of stock", "was refunded", "is ready for pickup"),
        ("已发货", "已售罄", "已退款", "可到店取货"),
    ),
    "dining": DomainSlots(
        ("dinner booking", "lunch menu", "takeout order", "coffee subscription"),
        ("晚餐预订", "午餐菜单", "外卖订单", "咖啡订购"),
        ("table availability", "waiting time", "order status", "menu price"),
        ("空桌情况", "等位时间", "订单状态", "菜单价格"),
        ("reserve a table", "change the order", "deliver the meal", "cater the event"),
        ("预订餐桌", "修改订单", "配送餐食", "承办餐饮"),
        ("the restaurant", "the takeaway", "the café", "the caterer"),
        ("餐厅", "外卖商家", "咖啡店", "餐饮公司"),
        ("was accepted", "is being prepared", "is ready", "was cancelled"),
        ("已接单", "正在制作", "已备好", "已取消"),
    ),
    "health": DomainSlots(
        ("step record", "sleep report", "prescription", "vaccination record"),
        ("步数记录", "睡眠报告", "处方", "疫苗接种记录"),
        ("daily total", "renewal date", "dosage note", "appointment status"),
        ("当日总数", "续方日期", "剂量说明", "预约状态"),
        ("book an examination", "refill the prescription", "deliver the medicine", "arrange home care"),
        ("预约检查", "续开处方", "配送药品", "安排居家护理"),
        ("the clinic", "the pharmacy", "the hospital", "the care provider"),
        ("诊所", "药房", "医院", "护理机构"),
        ("was updated", "needs review", "is ready to collect", "was received"),
        ("已更新", "需要复核", "可领取", "已收到"),
    ),
    "weather": DomainSlots(
        ("rain forecast", "air-quality report", "storm tracker", "temperature chart"),
        ("降雨预报", "空气质量报告", "风暴追踪", "气温图表"),
        ("rain chance", "air-quality index", "storm path", "high temperature"),
        ("降雨概率", "空气质量指数", "风暴路径", "最高温度"),
        ("inspect the roof", "clear the snow", "deliver sandbags", "repair the drain"),
        ("检查屋顶", "清理积雪", "运送沙袋", "维修排水管"),
        ("the roofer", "the snow service", "the emergency supplier", "the plumber"),
        ("屋顶维修方", "除雪服务商", "应急物资商", "水管工"),
        ("was updated", "issued a warning", "cleared the alert", "changed direction"),
        ("已更新", "已发布预警", "已解除警报", "已改变方向"),
    ),
    "accountService": DomainSlots(
        ("cloud account", "software license", "support ticket", "security setting"),
        ("云端账户", "软件许可证", "支持工单", "安全设置"),
        ("renewal date", "ticket status", "storage usage", "sign-in history"),
        ("续订日期", "工单状态", "存储用量", "登录历史"),
        ("upgrade the plan", "recover the account", "renew the license", "schedule support"),
        ("升级套餐", "恢复账户", "续订许可证", "预约支持"),
        ("the provider", "the support desk", "the software vendor", "the service team"),
        ("服务商", "支持团队", "软件供应商", "客服团队"),
        ("was renewed", "was suspended", "needs verification", "was restored"),
        ("已续订", "已暂停", "需要验证", "已恢复"),
    ),
    "generalKnowledge": DomainSlots(
        ("history article", "science glossary", "language guide", "reference note"),
        ("历史条目", "科学词典", "语言指南", "参考笔记"),
        ("publication date", "short definition", "source citation", "latest revision"),
        ("发布日期", "简短定义", "来源引用", "最新修订"),
        ("translate the manuscript", "verify the archive", "print the encyclopedia", "catalog the collection"),
        ("翻译手稿", "核验档案", "印刷百科全书", "编目藏品"),
        ("the translator", "the archive", "the publisher", "the library"),
        ("翻译机构", "档案馆", "出版社", "图书馆"),
        ("was revised", "is temporarily unavailable", "added a citation", "finished indexing"),
        ("已修订", "暂不可用", "已添加引用", "已完成索引"),
    ),
}

DISPLAY_VALUES = (
    ("compact mode", "紧凑模式"),
    ("the top position", "顶部"),
    ("a blue highlight", "蓝色高亮"),
    ("the favorites section", "收藏区"),
)
APP_SCOPES = (
    ("the dashboard", "仪表盘"),
    ("the quick panel", "快捷面板"),
    ("the saved view", "已存视图"),
    ("the app widget", "应用小组件"),
)
PEOPLE = (
    ("Alex", "小林"),
    ("Morgan", "小周"),
    ("Taylor", "小陈"),
    ("Jordan", "小何"),
)

TEMPLATES: dict[str, dict[str, tuple[str, ...]]] = {
    "en": {
        "assistantCommand": (
            "Set {subject} to {value} in {scope}.",
            "Pin {subject} at {value} on {scope}.",
            "Show {subject} with {value} in {scope}.",
            "Move {subject} to {value} on {scope}.",
        ),
        "informationQuery": (
            "Look up the {fact} for {subject} from {scope}.",
            "What is the {fact} for {subject} in {scope}?",
            "Show me the latest {fact} for {subject} from {scope}.",
            "Find the current {fact} for {subject} in {scope}.",
        ),
        "systemNotification": (
            "System notice: {subject} {event}; details are in {scope}.",
            "Service update: {subject} {event}. Open {scope} for details.",
            "Automatic alert: {subject} {event} in {scope}.",
            "Status update from {scope}: {subject} {event}.",
        ),
        "task": (
            "Please ask {provider} to {service} for {subject}.",
            "Arrange for {provider} to {service} regarding {subject}.",
            "I need {provider} to {service} for {subject}.",
            "Have {provider} {service} for {subject}, with confirmation.",
        ),
        "question": (
            "{person}, do you think {subject} belongs in {scope}?",
            "{person}, would {subject} work better with {value}?",
            "In your opinion, is {subject} suitable for {scope}, {person}?",
            "{person}, which presentation of {subject} would you prefer in {scope}?",
        ),
        "replyableMessage": (
            "{person}, I shared {subject} with you through {scope}; let me know when you see it.",
            "{person}, I left the notes about {subject} in {scope} and would value your reaction.",
            "{person}, the draft for {subject} is in {scope}; please reply when you have reviewed it.",
            "{person}, I updated {subject} in {scope}; tell me whether it works for you.",
        ),
    },
    "zh-Hans": {
        "assistantCommand": (
            "把{subject}在{scope}中设为{value}。",
            "将{subject}以{value}固定到{scope}。",
            "在{scope}中用{value}显示{subject}。",
            "把{subject}移到{scope}的{value}。",
        ),
        "informationQuery": (
            "查询{scope}里{subject}的{fact}。",
            "{scope}中{subject}的{fact}是什么?",
            "显示{scope}里{subject}最新的{fact}。",
            "查找{scope}中{subject}当前的{fact}。",
        ),
        "systemNotification": (
            "系统通知:{subject}{event},详情请查看{scope}。",
            "服务更新:{subject}{event},可在{scope}查看详情。",
            "自动提醒:{scope}中的{subject}{event}。",
            "来自{scope}的状态更新:{subject}{event}。",
        ),
        "task": (
            "请联系{provider}为{subject}{service}。",
            "安排{provider}处理{subject}并{service}。",
            "我需要{provider}针对{subject}{service}。",
            "请让{provider}为{subject}{service},并确认结果。",
        ),
        "question": (
            "{person},你觉得{subject}适合放在{scope}吗?",
            "{person},你认为把{subject}设为{value}会更好吗?",
            "{person},依你看{subject}放进{scope}合适吗?",
            "{person},你更喜欢{subject}在{scope}里怎样展示?",
        ),
        "replyableMessage": (
            "{person},我已经通过{scope}把{subject}分享给你,看到后告诉我一声。",
            "{person},我把{subject}的说明放在{scope}了,想听听你的看法。",
            "{person},关于{subject}的草稿在{scope}里,看完请回复我。",
            "{person},我更新了{scope}里的{subject},请告诉我是否合适。",
        ),
    },
}


def normalize_text(value: str) -> str:
    """Apply the corpus's stable NFKC and whitespace normalization."""

    return " ".join(unicodedata.normalize("NFKC", value).split()).strip()


def fingerprint(value: str) -> str:
    """Return a conservative normalized key for exact-text exclusion."""

    return normalize_text(value).casefold()


def stable_key(*values: object) -> bytes:
    """Create an ordering key independent of Python hash randomization."""

    return hashlib.sha256("|".join(map(str, values)).encode("utf-8")).digest()


def paired_values(values: Sequence[tuple[str, str]], language: str) -> tuple[str, ...]:
    index = 0 if language == "en" else 1
    return tuple(value[index] for value in values)


def slots_for(
    slots: DomainSlots,
    language: str,
    category: str,
) -> tuple[tuple[str, ...], ...]:
    """Return only finite slots that are semantically valid for a category."""

    suffix = "en" if language == "en" else "zh"
    subjects = getattr(slots, f"subjects_{suffix}")
    providers = getattr(slots, f"providers_{suffix}")
    values = paired_values(DISPLAY_VALUES, language)
    scopes = paired_values(APP_SCOPES, language)
    people = paired_values(PEOPLE, language)
    if category == "assistantCommand":
        return subjects, values, scopes
    if category == "informationQuery":
        return subjects, getattr(slots, f"facts_{suffix}"), scopes
    if category == "systemNotification":
        return subjects, getattr(slots, f"events_{suffix}"), scopes
    if category == "task":
        return subjects, getattr(slots, f"services_{suffix}"), providers
    if category == "question":
        return subjects, values, scopes, people
    return subjects, scopes, people


def candidate_texts(
    language: str,
    category: str,
    domain: str,
) -> Iterator[tuple[str, str]]:
    """Yield every deterministic template/slot combination for one cell."""

    templates = TEMPLATES[language][category]
    slot_groups = slots_for(DOMAIN_SLOTS[domain], language, category)
    argument_names = {
        "assistantCommand": ("subject", "value", "scope"),
        "informationQuery": ("subject", "fact", "scope"),
        "systemNotification": ("subject", "event", "scope"),
        "task": ("subject", "service", "provider"),
        "question": ("subject", "value", "scope", "person"),
        "replyableMessage": ("subject", "scope", "person"),
    }[category]
    candidates: list[tuple[str, str]] = []
    for template_index, template in enumerate(templates, start=1):
        family = f"v6_{category}_{language}_template_{template_index}"
        for values in itertools.product(*slot_groups):
            text = normalize_text(template.format(**dict(zip(argument_names, values))))
            candidates.append((text, family))
    yield from sorted(
        candidates,
        key=lambda value: stable_key(language, category, domain, *value),
    )


def quota_by_domain(total: int, offset: int) -> dict[str, int]:
    """Distribute a category total across all domains without randomness."""

    base, remainder = divmod(total, len(DOMAINS))
    quotas = {domain: base for domain in DOMAINS}
    for index in range(remainder):
        quotas[DOMAINS[(offset + index) % len(DOMAINS)]] += 1
    return quotas


def make_record(
    *,
    index: int,
    text: str,
    language: str,
    category: str,
    domain: str,
    template_family: str,
) -> dict:
    """Build the complete current training schema for one known boundary."""

    label_values = {label: False for label in INTENT_LABELS}
    label_values[category] = True
    # An interpersonal question naturally invites a reply; both fields are
    # template-determined while all three routing intents remain false.
    if category == "question":
        label_values["replyableMessage"] = True
    record_id = (
        f"v6-boundary-{language}-{category}-{domain}-"
        f"{index:04d}-{hashlib.sha256(text.encode('utf-8')).hexdigest()[:12]}"
    )
    return {
        "id": record_id,
        "text": text,
        "language": language,
        "split": "train",
        "family": template_family,
        "task": label_values["task"],
        "question": label_values["question"],
        "invitation": label_values["invitation"],
        "complaint": label_values["complaint"],
        "scheduleNegotiation": label_values["scheduleNegotiation"],
        "confirmationDecision": label_values["confirmationDecision"],
        "followUpReminder": label_values["followUpReminder"],
        "blessing": label_values["blessing"],
        "sentiment": "neutral",
        "replyable": label_values["replyableMessage"],
        "assistantCommand": label_values["assistantCommand"],
        "informationQuery": label_values["informationQuery"],
        "systemNotification": label_values["systemNotification"],
        "domain": domain,
        "sampleWeight": SAMPLE_WEIGHT,
        "knownLabels": KNOWN_LABELS,
        "labelingMethod": "deterministic taxonomy-v6 template and finite slots",
        "sourceDataset": SOURCE_DATASET,
        "sourceLicense": SOURCE_LICENSE,
        "sourceURL": "Scripts/clipboard_semantics/generate_v6_boundary_corpus.py",
        "sourceRevision": SOURCE_REVISION,
        "sourceSplit": SOURCE_SPLIT,
        "synthetic": True,
        "templateFamily": template_family,
    }


def discover_holdout_paths(directory: Path) -> list[Path]:
    """Find every frozen holdout name covered by the v6 training policy."""

    paths = set(directory.rglob("*holdout-corpus.jsonl"))
    blind = directory / "product-policy-blind-holdout-v1.jsonl"
    if blind.is_file():
        paths.add(blind)
    return sorted(paths)


def load_holdout_fingerprints(paths: Iterable[Path]) -> set[str]:
    """Load normalized text keys without depending on any holdout schema extras."""

    fingerprints: set[str] = set()
    for path in sorted(set(paths)):
        if not path.is_file():
            continue
        for line in path.read_text(encoding="utf-8").splitlines():
            if not line.strip():
                continue
            value = json.loads(line)
            text = value.get("text")
            if isinstance(text, str) and normalize_text(text):
                fingerprints.add(fingerprint(text))
    return fingerprints


def validate_records(records: Sequence[dict], holdouts: set[str]) -> None:
    """Fail closed on duplicate, leakage, schema, or annotation mistakes."""

    if len({record["id"] for record in records}) != len(records):
        raise ValueError("Duplicate generated IDs")
    text_keys = [fingerprint(record["text"]) for record in records]
    if len(set(text_keys)) != len(records):
        raise ValueError("Duplicate generated texts")
    leaked = set(text_keys) & holdouts
    if leaked:
        raise ValueError(f"Holdout overlap remained after filtering: {len(leaked)}")
    for record in records:
        if record["text"] != normalize_text(record["text"]):
            raise ValueError(f"Non-NFKC record: {record['id']}")
        if record["knownLabels"] != KNOWN_LABELS:
            raise ValueError(f"Unexpected known labels: {record['id']}")
        if record["domain"] not in DOMAINS:
            raise ValueError(f"Unsupported domain: {record['id']}")
        if record["sampleWeight"] != SAMPLE_WEIGHT:
            raise ValueError(f"Unexpected sample weight: {record['id']}")


def generate_records(
    *,
    positive_per_intent_language: int = DEFAULT_POSITIVE_PER_INTENT_LANGUAGE,
    negative_per_intent_language: int = DEFAULT_NEGATIVE_PER_INTENT_LANGUAGE,
    holdout_fingerprints: set[str] | None = None,
) -> tuple[list[dict], Counter[str], int]:
    """Generate balanced records and return target-intent counts plus exclusions."""

    if positive_per_intent_language < 1 or negative_per_intent_language < 1:
        raise ValueError("Per-intent counts must be positive")
    holdouts = holdout_fingerprints or set()
    records: list[dict] = []
    target_counts: Counter[str] = Counter()
    seen: set[str] = set()
    excluded_holdout = 0
    for language in LANGUAGES:
        for category in BOUNDARY_INTENTS:
            category_total = (
                positive_per_intent_language
                if category in NEW_INTENTS
                else negative_per_intent_language
            )
            quotas = quota_by_domain(category_total, CATEGORY_OFFSETS[category])
            for domain in DOMAINS:
                selected = 0
                for text, family in candidate_texts(language, category, domain):
                    text_key = fingerprint(text)
                    if text_key in holdouts:
                        excluded_holdout += 1
                        continue
                    if text_key in seen:
                        continue
                    record = make_record(
                        index=selected + 1,
                        text=text,
                        language=language,
                        category=category,
                        domain=domain,
                        template_family=family,
                    )
                    records.append(record)
                    seen.add(text_key)
                    target_counts[f"{language}|{category}"] += 1
                    selected += 1
                    if selected == quotas[domain]:
                        break
                if selected != quotas[domain]:
                    raise ValueError(
                        f"Insufficient unique candidates for {language}/{category}/"
                        f"{domain}: {selected} < {quotas[domain]}"
                    )
    records.sort(key=lambda record: stable_key(record["id"]))
    validate_records(records, holdouts)
    return records, target_counts, excluded_holdout


def serialize_records(records: Sequence[dict]) -> bytes:
    """Serialize JSONL with stable keys and a final newline."""

    return (
        "\n".join(
            json.dumps(record, ensure_ascii=False, sort_keys=True)
            for record in records
        )
        + "\n"
    ).encode("utf-8")


def nested_counts(counter: Counter[tuple[str, ...]]) -> dict:
    """Turn tuple-key counts into a stable nested JSON object."""

    root: dict = {}
    for keys, count in sorted(counter.items()):
        node = root
        for key in keys[:-1]:
            node = node.setdefault(key, {})
        node[keys[-1]] = count
    return root


def build_summary(
    records: Sequence[dict],
    target_counts: Counter[str],
    excluded_holdout: int,
    payload: bytes,
) -> dict:
    """Summarize all requested dimensions and the exact output artifact."""

    by_language = Counter((record["language"],) for record in records)
    by_boundary_target_language = Counter(
        {
            tuple(key.split("|", 1)): count
            for key, count in target_counts.items()
        }
    )
    by_intent_language = Counter()
    for record in records:
        for intent in BOUNDARY_INTENTS:
            field = "replyable" if intent == "replyableMessage" else intent
            if record[field]:
                by_intent_language[(record["language"], intent)] += 1
    by_intent = Counter()
    for (_, intent), count in by_intent_language.items():
        by_intent[(intent,)] += count
    by_domain = Counter((record["domain"],) for record in records)
    by_family = Counter((record["templateFamily"],) for record in records)
    return {
        "schemaVersion": 1,
        "sourceRevision": SOURCE_REVISION,
        "recordCount": len(records),
        "counts": {
            "byLanguage": nested_counts(by_language),
            "byIntent": nested_counts(by_intent),
            "byIntentAndLanguage": nested_counts(by_intent_language),
            "byBoundaryTargetAndLanguage": nested_counts(
                by_boundary_target_language
            ),
            "byDomain": nested_counts(by_domain),
            "byTemplateFamily": nested_counts(by_family),
        },
        "corpusSHA256": hashlib.sha256(payload).hexdigest(),
        "excludedHoldoutOverlap": excluded_holdout,
    }


def write_corpus(
    output_path: Path,
    summary_path: Path,
    *,
    positive_per_intent_language: int = DEFAULT_POSITIVE_PER_INTENT_LANGUAGE,
    negative_per_intent_language: int = DEFAULT_NEGATIVE_PER_INTENT_LANGUAGE,
    holdout_paths: Iterable[Path] = (),
) -> dict:
    """Generate and write the corpus and summary files."""

    holdouts = load_holdout_fingerprints(holdout_paths)
    records, target_counts, excluded = generate_records(
        positive_per_intent_language=positive_per_intent_language,
        negative_per_intent_language=negative_per_intent_language,
        holdout_fingerprints=holdouts,
    )
    payload = serialize_records(records)
    summary = build_summary(records, target_counts, excluded, payload)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    summary_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_bytes(payload)
    summary_path.write_text(
        json.dumps(summary, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    return summary


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT_PATH)
    parser.add_argument("--summary-output", type=Path, default=DEFAULT_SUMMARY_PATH)
    parser.add_argument(
        "--holdout-directory",
        type=Path,
        default=OUTPUT_DIRECTORY,
    )
    parser.add_argument(
        "--positive-per-intent-language",
        type=int,
        default=DEFAULT_POSITIVE_PER_INTENT_LANGUAGE,
    )
    parser.add_argument(
        "--negative-per-intent-language",
        type=int,
        default=DEFAULT_NEGATIVE_PER_INTENT_LANGUAGE,
    )
    return parser.parse_args()


def main() -> None:
    arguments = parse_arguments()
    holdout_paths = discover_holdout_paths(arguments.holdout_directory)
    summary = write_corpus(
        arguments.output,
        arguments.summary_output,
        positive_per_intent_language=arguments.positive_per_intent_language,
        negative_per_intent_language=arguments.negative_per_intent_language,
        holdout_paths=holdout_paths,
    )
    print(
        "V6_BOUNDARY_CORPUS "
        f"records={summary['recordCount']} "
        f"excludedHoldout={summary['excludedHoldoutOverlap']} "
        f"sha256={summary['corpusSHA256']}"
    )


if __name__ == "__main__":
    main()
