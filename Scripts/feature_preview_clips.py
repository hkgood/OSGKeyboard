#!/usr/bin/env python3
"""Copy + timing for the four Chinese feature previews.

Caption times are relative to the start of their own `Source` window (i.e.
after `trim_start`), not the finished file — title cards are prepended later.

Kept separate from `compose_feature_previews.py` so the copy can be retimed
without touching the ffmpeg plumbing.

Raw footage comes from `Scripts/record_feature_previews.sh`; every timing below
was read off those recordings, so re-time after changing a demo timeline.
"""

from __future__ import annotations

from compose_feature_previews import Caption, Clip, Source

CLIPS: dict[str, Clip] = {
    # 1 — 语音输入与润色，收在趣味润色风格上
    "voice-polish": Clip(
        slug="voice-polish",
        title=["说一句", "成一段"],
        subtitle="语音输入 · 自动润色",
        sources=[
            # 备忘录 + 真实润色审阅面板：听写 → 润色 → 替换上屏
            Source(
                raw="voice-polish",
                trim_start=3.4,
                trim_duration=17.0,
                captions=[
                    Caption(0.3, 5.2, "开口就说", sub="不用先在脑子里组织措辞"),
                    Caption(5.5, 8.4, "AI 正在润色"),
                    Caption(8.7, 13.4, "口水话变成能直接发出去的话"),
                    Caption(13.7, 16.7, "一键替换，落回原处"),
                ],
            ),
            # 润色风格页：内置风格之外还有一整排趣味人格
            Source(
                raw="personal-style",
                trim_start=0.0,
                trim_duration=6.0,
                freeze_at=4.0,
                ken_burns=1.09,
                ken_burns_focus=(0.5, 0.78),
                captions=[
                    Caption(0.3, 5.7, "换个风格，换种说法",
                            sub="大厂黑话 · 装逼指南 · 帝吧大神 · 小红书"),
                ],
            ),
        ],
    ),
    # 2 — 个性润色风格：从历史听写里学你的表达习惯
    "personal-style": Clip(
        slug="personal-style",
        title=["它会学", "你说话"],
        subtitle="从你的听写里长出专属风格",
        sources=[
            Source(
                raw="personal-style",
                trim_start=0.0,
                trim_duration=15.0,
                freeze_at=4.0,
                # Slow push-in onto the「生成专属风格」card near the top.
                ken_burns=1.16,
                ken_burns_focus=(0.5, 0.24),
                captions=[
                    Caption(0.3, 4.6, "内置风格之外，还有一个你"),
                    Caption(4.9, 9.4, "从历史听写里学你的表达习惯",
                            sub="用词、语气、断句，都是你的"),
                    Caption(9.7, 14.7, "一键生成专属风格",
                            sub="仅在生成时发送，保存前可预览可修改"),
                ],
            ),
        ],
    ),
    # 3 — 剪贴板 AI Agent：复制的内容直接一键回复
    "clipboard-agent": Clip(
        slug="clipboard-agent",
        title=["复制一段", "AI 帮你回"],
        subtitle="剪贴板 AI Agent",
        sources=[
            Source(
                raw="clipboard-agent",
                # Beats in the recording: clipboard panel ~9-13s, suggestion
                # strip to ~19s, AI skill row ~19-26s, reply lands ~33s. The
                # 24s budget cannot hold all of it, so the window opens on the
                # tail of the panel and runs through the payoff.
                trim_start=11.0,
                trim_duration=24.0,
                captions=[
                    Caption(0.3, 3.6, "复制过的内容，键盘直接认得"),
                    Caption(3.9, 7.4, "不用来回切 App 粘来粘去"),
                    # Skill row is on screen for body 7.6-12.6 — keep the super
                    # inside that window or it names a row you cannot see.
                    Caption(7.8, 12.4, "一键回复",
                            sub="俏皮回复 · 译为英语 · 总结网页"),
                    Caption(19.5, 23.7, "点一下，回复就写好了"),
                ],
            ),
        ],
    ),
    # 4 — 长按麦克风直接询问 AI
    "ask-ai": Clip(
        slug="ask-ai",
        title=["轻点听写", "长按问 AI"],
        subtitle="一个麦克风，两件事",
        sources=[
            Source(
                raw="ask-ai",
                trim_start=9.0,
                trim_duration=24.0,
                captions=[
                    Caption(0.3, 5.4, "长按麦克风，直接问 AI",
                            sub="不用退出当前 App"),
                    Caption(5.7, 11.0, "说完就在想答案"),
                    Caption(11.3, 17.4, "答案直接落进输入框"),
                    Caption(17.7, 23.7, "想好了，直接发出去"),
                ],
            ),
        ],
    ),
}
