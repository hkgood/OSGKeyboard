#!/usr/bin/env python3
"""Windows for the in-app feature cards.

Every `start` / `duration` is in real seconds against the CFR copy of the raw
recording, and was read off a frame-by-frame pass over that footage — re-time
after touching any demo timeline.

Windows are chosen so the clip both tells the feature in one glance and lands
close to where it started, which keeps the loop blend invisible.
"""

from __future__ import annotations

from compose_feature_cards import Card

CARDS: dict[str, Card] = {
    # 语音说一句 → 自动润色 → 出结果。
    # 5.5 空闲提示 · 6.5 聆听 · 10 编辑中 · 13 编辑后结果
    "voice-polish": Card(
        slug="voice-polish",
        raw="voice-polish",
        start=5.5,
        duration=10.0,
    ),
    # 润色风格页。静态页面，用极缓的推近-拉回提供动势，天然无缝。
    # 画面落在「生成专属风格」卡片上，下面带出内置风格第一排。
    "personal-style": Card(
        slug="personal-style",
        raw="personal-style",
        start=4.0,
        duration=8.0,
        ping_pong_zoom=1.10,
        # Starts below the page title — a half-cut「润色风格」heading reads as
        # a framing mistake on a card.
        crop_y=470,
    ),
    # 复制一条消息 → 键盘按内容给出技能行 → 点「回复」出一条 → 回到行 →
    # 点「澄清追问」出另一种口吻。技能行由真实的
    # `ClipboardSkillSemanticRanker` 排出（这条消息排出「译为英语 / 回复 /
    # 澄清追问 / 日程」），不是写死的——生产环境在通用「回复」之外最多只放
    # 两个专门回复技能，硬凑一排回复风格会得到一个真实 app 里不存在的键盘。
    # 21 技能行 · 23 思考 · 25 回复 · 27 技能行 · 29 澄清追问 · 30.5 技能行
    # 首尾都停在技能行上，循环点本身就是同一状态。
    "clipboard-agent": Card(
        slug="clipboard-agent",
        raw="clipboard-agent",
        start=20.6,
        duration=9.9,
    ),
    # 长按问 AI：聆听（识别出问题）→ 生成 → 答案落在键盘答案区。
    # 13.5 聆听 · 18 生成中 · 21 答案出现
    "ask-ai": Card(
        slug="ask-ai",
        raw="ask-ai",
        start=13.5,
        duration=10.0,
    ),
}
