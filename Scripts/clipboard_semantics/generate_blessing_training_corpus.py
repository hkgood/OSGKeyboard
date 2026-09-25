#!/usr/bin/env python3
"""Generate broad blessing positives and difficult boundary negatives.

The supplement supervises only the blessing label. It does not infer other
clipboard intents from synthetic text, so unrelated classifier heads are not
trained on unknown labels.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import random
import re
import unicodedata
from collections import Counter
from dataclasses import dataclass
from pathlib import Path


SEED = 20260827
OUTPUT_DIRECTORY = Path("ModelTraining/ClipboardSemantics")
BASE_CORPUS_PATH = OUTPUT_DIRECTORY / "combined-training-corpus.jsonl"
SUPPLEMENT_PATH = OUTPUT_DIRECTORY / "blessing-training-supplement.jsonl"
COMBINED_PATH = OUTPUT_DIRECTORY / "combined-training-corpus-with-blessing.jsonl"
SUMMARY_PATH = OUTPUT_DIRECTORY / "blessing-training-summary.json"
DEFAULT_RECORDS_PER_LANGUAGE = 50_000
SOURCE_REVISION = "2026-08-27-v1"

SENSITIVE_PATTERN = re.compile(
    r"(?:[\w.+-]+@[\w.-]+\.\w+)|(?:\+?\d[\d ()-]{8,}\d)|"
    r"(?:\b\d{3}-\d{2}-\d{4}\b)",
    re.IGNORECASE,
)


@dataclass(frozen=True)
class Family:
    name: str
    blessing: bool
    templates: tuple[str, ...]
    slots: dict[str, tuple[str, ...]]


ZH_COMMON = {
    "prefix": (
        "",
        "对了，",
        "刚看到消息，",
        "专门来跟你说一声，",
        "今天这个特别的日子里，",
        "虽然隔着屏幕，",
        "群里冒个泡，",
        "认真说一句，",
        "简单但真心地说，",
        "借这个机会，",
        "微信里单独说一句，",
        "趁现在有空，",
        "想了想还是要说，",
        "不复制群发文案，真心说一句，",
        "冒个泡送句话，",
        "今天第一条消息，",
        "睡前想起这件事，",
        "看到日历才发现，",
        "刚和家里人聊到，",
        "替没到场的大家说一句，",
        "不用回复，收下这句话就好，",
        "隔了好久没联系，",
        "赶在零点之前，",
        "早早来占个位置，",
        "迟到但不会缺席，",
        "不绕弯子，",
        "发条短消息，",
        "想到你就来留言，",
        "今天值得认真记住，",
        "把这份心意放在这里，",
    ),
    "recipient": (
        "你",
        "您",
        "大家",
        "家人们",
        "小伙伴们",
        "老师",
        "师傅",
        "叔叔阿姨",
        "爷爷奶奶",
        "同学们",
        "同事们",
        "项目组",
        "新郎新娘",
        "新手爸妈",
        "毕业班同学",
        "今天的寿星",
    ),
    "tail": (
        "",
        "！",
        "呀！",
        "～",
        "，抱抱！",
        "，一切顺利！",
        "，开心最重要！",
        "，记得照顾好自己。",
        "，等你的好消息。",
        "，未来继续闪闪发光。",
        "，真心的。",
        "，这句不是群发。",
        "，收下我的心意。",
        "，今天也要元气满满。",
        "，我们改天见。",
        "，有空再慢慢聊。",
        "，一定要幸福。",
        "，别忘了给自己放个假。",
        "，愿生活温柔待你。",
        "，家里人也都惦记着你。",
        "，这份开心值得纪念。",
        "，先把好消息记下来。",
        "，接下来的日子加油。",
        "，希望很快见到你。",
    ),
}

EN_COMMON = {
    "prefix": (
        "",
        "Just wanted to say: ",
        "A quick note: ",
        "Thinking of you today—",
        "From across the miles, ",
        "On this special day, ",
        "Dropping in to say ",
        "I mean this sincerely: ",
        "Before the day ends, ",
        "Sending a little note: ",
        "A message just for you: ",
        "No copied group message—",
        "While I have a quiet minute, ",
        "Before midnight, ",
        "A little late, but sincerely: ",
        "Starting the day with this: ",
        "One honest sentence: ",
        "I saw the date and thought of you—",
        "Passing along a note from all of us: ",
        "No need to reply; ",
        "It has been a while, but ",
        "Saving this moment with a message: ",
        "I will keep it simple: ",
        "A small message with a lot of heart: ",
        "I could not let today pass without saying ",
        "From everyone who could not be there, ",
        "One last message before the day ends: ",
        "This is not a formal card, just ",
        "I thought of you and wanted to say ",
        "Leaving this here for you: ",
    ),
    "recipient": (
        "you",
        "all of you",
        "everyone",
        "our family",
        "the whole team",
        "Professor Lee",
        "our teachers",
        "the newlyweds",
        "the new parents",
        "the graduating class",
        "today's birthday star",
        "my dear friend",
        "our colleagues",
        "your family",
    ),
    "tail": (
        "",
        "!",
        "—you deserve it!",
        " Take good care.",
        " Here's to what comes next.",
        " I am cheering for you.",
        " Hope the good news keeps coming.",
        " Wishing you all the best.",
        " Enjoy every moment.",
        " You have got this.",
        " This comes from the heart.",
        " No reply needed.",
        " Keep this little note.",
        " We will celebrate properly soon.",
        " Take a well-earned break.",
        " May life be gentle with you.",
        " Everyone here is thinking of you.",
        " This moment deserves to be remembered.",
        " Keep going at your own pace.",
        " I hope we see each other soon.",
        " Consider this a warm message from afar.",
        " There is more good ahead.",
        " Be kind to yourself today.",
        " Let us catch up soon.",
    ),
}

ZH_NEGATIVE_SURFACE = {
    "prefix": (
        "",
        "备注一下，",
        "文档里写着，",
        "有人问，",
        "群里提到，",
        "记录显示，",
        "顺便说明，",
        "只是在讨论，",
        "从文本分类角度看，",
        "这是一条例句：",
        "搜索结果显示，",
        "材料中提到，",
        "会议上有人说，",
        "聊天记录里出现了这句话：",
        "作为反例，",
        "需要确认的是，",
        "这不是实际发送的消息，",
        "这里只记录事实：",
        "标题写的是，",
        "页面上显示，",
    ),
    "tail": (
        "",
        "。",
        "，仅供参考。",
        "，只是客观记录。",
        "，上下文仍在讨论。",
        "，无需回复。",
        "，后续还要人工确认。",
        "，原文到这里结束。",
        "，没有更多说明。",
        "，这是列表中的一项。",
    ),
}

EN_NEGATIVE_SURFACE = {
    "prefix": (
        "",
        "For the record, ",
        "The document says ",
        "Someone asked whether ",
        "The group mentioned that ",
        "The log shows that ",
        "For classification purposes, ",
        "This is only a discussion: ",
        "Here is a quoted example: ",
        "The search result says ",
        "The meeting notes report that ",
        "As a negative example, ",
        "This was not an actual message: ",
        "The page displays ",
        "The title says ",
        "To clarify the context, ",
        "This line only records that ",
        "The material notes that ",
        "A reviewer noted that ",
        "The transcript contains this phrase: ",
    ),
    "tail": (
        "",
        ".",
        "; this is only a reference.",
        "; this only records what happened.",
        "; the context is still under discussion.",
        "; no reply is required.",
        "; a reviewer still needs to verify it.",
        "; the original line ends here.",
        "; there is no further explanation.",
        "; this is one item in the list.",
    ),
}

ZH_NEGATIVE_CONTEXT = (
    "",
    "这是聊天记录的一部分。",
    "前后还有其他内容。",
    "这里只保留原句。",
    "消息没有继续展开。",
    "记录到这里结束。",
    "这是页面中的一行文字。",
    "原文仍在等待确认。",
    "上下文未显示接收人。",
    "这句话单独出现在列表里。",
)

EN_NEGATIVE_CONTEXT = (
    "",
    "This is part of a longer transcript.",
    "There is more context before and after it.",
    "Only the original line is retained.",
    "The message does not continue.",
    "The record ends here.",
    "This is one line from the page.",
    "The original text still needs confirmation.",
    "The surrounding context names no recipient.",
    "The sentence appears alone in a list.",
)


ZH_FAMILIES = (
    Family(
        "festival",
        True,
        (
            "{prefix}祝{recipient}{occasion}快乐，{wish}{tail}",
            "{prefix}{occasion}到了，愿{recipient}{wish}{tail}",
            "{prefix}{recipient}，{occasion}快乐，愿往后的日子{wish}{tail}",
            "{prefix}给{recipient}拜个节，祝{wish}{tail}",
            "{prefix}这个{occasion}，把最真诚的祝愿送给{recipient}：{wish}{tail}",
        ),
        {
            "occasion": (
                "春节",
                "新年",
                "元旦",
                "元宵节",
                "端午节",
                "中秋节",
                "国庆节",
                "重阳节",
                "教师节",
                "母亲节",
                "父亲节",
                "圣诞节",
            ),
            "wish": (
                "平安喜乐",
                "阖家幸福",
                "万事顺遂",
                "身体健康",
                "好运常在",
                "所求皆如愿",
                "每天都有好心情",
                "日子越过越红火",
                "工作生活都顺心",
                "团团圆圆、幸福安康",
            ),
        },
    ),
    Family(
        "birthday",
        True,
        (
            "{prefix}{recipient}生日快乐，愿新的一岁{wish}{tail}",
            "{prefix}祝今天的{recipient}生日快乐，{wish}{tail}",
            "{prefix}又长大一岁啦，愿{recipient}{wish}{tail}",
            "{prefix}生日这天，把一句{wish}送给{recipient}{tail}",
            "{prefix}Happy birthday，愿{recipient}这一岁{wish}{tail}",
        ),
        {
            "wish": (
                "有爱有梦有期待",
                "健康自在",
                "被温柔和好运包围",
                "做喜欢的事，见想见的人",
                "烦恼少一点，快乐多很多",
                "心想事成",
                "一路有花也有掌声",
                "比去年更勇敢更从容",
                "收获满满的幸福",
                "每天都值得纪念",
            ),
        },
    ),
    Family(
        "congratulation",
        True,
        (
            "{prefix}{congrats}，{achievement}{tail}",
            "{prefix}{achievement}，必须说一句{congrats}{tail}",
            "{prefix}听说{achievement}，真心替{recipient}高兴，{congrats}{tail}",
            "{prefix}{congrats}！愿{recipient}接下来{wish}{tail}",
            "{prefix}可喜可贺，{achievement}，继续加油{tail}",
        ),
        {
            "congrats": (
                "恭喜",
                "恭喜你",
                "恭喜恭喜",
                "祝贺你",
                "太棒了，恭喜",
                "真替你开心",
                "可喜可贺",
                "必须恭喜一下",
            ),
            "achievement": (
                "顺利毕业",
                "成功上岸",
                "拿到心仪的 offer",
                "升职加薪",
                "比赛夺冠",
                "项目顺利上线",
                "论文通过答辩",
                "考试取得好成绩",
                "新店正式开业",
                "搬进新家",
                "领证结婚",
                "宝宝平安出生",
                "通过重要认证",
                "完成第一次马拉松",
                "作品获奖",
            ),
            "wish": (
                "再创佳绩",
                "前程似锦",
                "一路开挂",
                "越来越好",
                "继续闪闪发光",
                "每一步都走得坚定",
                "收获更多好消息",
                "未来皆是坦途",
            ),
        },
    ),
    Family(
        "wedding_family",
        True,
        (
            "{prefix}祝{recipient}{occasion}，{wish}{tail}",
            "{prefix}{occasion}，愿{recipient}{wish}{tail}",
            "{prefix}恭喜{recipient}迎来{occasion}，祝{wish}{tail}",
            "{prefix}把最好的祝福送给{recipient}：{wish}{tail}",
        ),
        {
            "occasion": (
                "新婚快乐",
                "结婚纪念日快乐",
                "喜得贵子",
                "喜迎千金",
                "成为幸福的新手爸妈",
                "家庭新成员平安到来",
            ),
            "wish": (
                "一家人平安幸福",
                "往后的日子温暖有爱",
                "小家越来越温馨",
                "朝朝暮暮皆是欢喜",
                "新阶段顺顺利利",
                "生活充满爱和欢笑",
                "喜乐常伴",
                "每一天都有新的幸福",
            ),
        },
    ),
    Family(
        "health_recovery",
        True,
        (
            "{prefix}祝{recipient}{recovery}{tail}",
            "{prefix}愿{recipient}{recovery}，{wish}{tail}",
            "{prefix}听说身体不舒服，希望{recipient}{recovery}{tail}",
            "{prefix}把健康的祝愿送给{recipient}，愿{wish}{tail}",
            "{prefix}替大家祝愿{recipient}{recovery}{tail}",
        ),
        {
            "recipient": (
                "你",
                "您",
                "妈妈",
                "爸爸",
                "爷爷奶奶",
                "住院的朋友",
                "刚做完手术的他",
                "正在休养的她",
            ),
            "recovery": (
                "早日康复",
                "手术顺利",
                "检查结果一切正常",
                "身体一天比一天好",
                "平安度过恢复期",
                "很快恢复精神",
                "少些疼痛，多些轻松",
                "顺顺利利出院",
            ),
            "wish": (
                "平安健康",
                "安心休养",
                "每天都有新的好转",
                "身心都慢慢恢复",
                "被关心和温暖包围",
                "很快回到喜欢的生活",
            ),
        },
    ),
    Family(
        "travel_safety",
        True,
        (
            "{prefix}祝{recipient}{travel_wish}{tail}",
            "{prefix}出发啦，愿{recipient}{travel_wish}{tail}",
            "{prefix}一路顺风，祝{recipient}{travel_wish}{tail}",
            "{prefix}愿这趟旅程{travel_wish}，玩得开心{tail}",
        ),
        {
            "travel_wish": (
                "一路平安",
                "旅途顺利",
                "一路顺风",
                "平安到达",
                "出入平安",
                "看见好风景也遇见好心情",
                "一路少奔波、多惊喜",
                "行程顺利圆满",
            ),
        },
    ),
    Family(
        "study_career",
        True,
        (
            "{prefix}祝{recipient}{goal}{tail}",
            "{prefix}愿{recipient}{goal}，{wish}{tail}",
            "{prefix}明天就要{event}了，祝{recipient}{goal}{tail}",
            "{prefix}为{recipient}加油，愿{goal}{tail}",
        ),
        {
            "event": (
                "考试",
                "面试",
                "答辩",
                "比赛",
                "演讲",
                "入职",
                "签约",
                "项目发布",
            ),
            "goal": (
                "考试顺利",
                "面试成功",
                "答辩顺利",
                "比赛发挥出色",
                "工作蒸蒸日上",
                "事业更上一层楼",
                "新工作一切顺心",
                "项目顺利上线",
            ),
            "wish": (
                "付出都有回报",
                "实力被看见",
                "从容发挥",
                "拿到满意的结果",
                "未来大有可为",
                "一路成长一路收获",
            ),
        },
    ),
    Family(
        "good_luck_short",
        True,
        (
            "{prefix}{short_wish}{tail}",
            "{prefix}送{recipient}一句：{short_wish}{tail}",
            "{prefix}今天也要{short_wish}{tail}",
            "{prefix}真心希望{recipient}{short_wish}{tail}",
        ),
        {
            "short_wish": (
                "祝你好运",
                "一切顺利",
                "心想事成",
                "万事胜意",
                "诸事顺遂",
                "前程似锦",
                "平安喜乐",
                "得偿所愿",
                "未来可期",
                "好事连连",
                "福气满满",
                "顺顺利利",
                "愿望成真",
                "所行皆坦途",
                "多喜乐，长安宁",
            ),
        },
    ),
    Family(
        "day_night",
        True,
        (
            "{prefix}祝{recipient}{daily_wish}{tail}",
            "{prefix}愿{recipient}{daily_wish}{tail}",
            "{prefix}{daily_wish}，明天见{tail}",
            "{prefix}今天辛苦了，祝{recipient}{daily_wish}{tail}",
        ),
        {
            "daily_wish": (
                "今晚睡个好觉",
                "做个甜甜的好梦",
                "明天心情明朗",
                "今天过得开心",
                "周末轻松愉快",
                "新的一周顺顺利利",
                "每一天都有小惊喜",
                "今晚安心入睡",
            ),
        },
    ),
    Family(
        "third_person_prayer",
        True,
        (
            "{prefix}我衷心祝愿{third_person}{wish}{tail}",
            "{prefix}愿{third_person}{wish}{tail}",
            "{prefix}请替我转告{third_person}，祝{wish}{tail}",
            "{prefix}我们一起为{third_person}祈愿，愿{wish}{tail}",
        ),
        {
            "third_person": (
                "她",
                "他",
                "孩子",
                "新郎新娘",
                "叔叔阿姨",
                "住院的朋友",
                "远方的家人",
                "参加考试的同学",
                "刚入职的伙伴",
                "整个团队",
            ),
            "wish": (
                "早日康复",
                "平安健康",
                "一切顺利",
                "渡过难关",
                "前程似锦",
                "家庭幸福",
                "收获理想的结果",
                "每天多一点轻松和快乐",
                "被好运和善意包围",
                "往后的生活越来越好",
            ),
        },
    ),
    Family(
        "opening_home",
        True,
        (
            "{prefix}恭喜{recipient}{occasion}，祝{wish}{tail}",
            "{prefix}祝贺{occasion}，愿{recipient}{wish}{tail}",
            "{prefix}{occasion}是新的开始，祝{wish}{tail}",
            "{prefix}送上祝福：{occasion}，愿{wish}{tail}",
        ),
        {
            "occasion": (
                "乔迁新居",
                "新店开业",
                "公司成立",
                "工作室开张",
                "新项目启动",
                "搬进新办公室",
            ),
            "wish": (
                "新的开始一切顺利",
                "未来蒸蒸日上",
                "每一步都有好收获",
                "人气旺、好运旺",
                "日子越过越红火",
                "一切都朝着好方向发展",
                "万事顺遂",
                "新的空间带来新的惊喜",
            ),
        },
    ),
    Family(
        "emoji_colloquial",
        True,
        (
            "{prefix}{recipient}，{casual_wish}{emoji}{tail}",
            "{prefix}{casual_wish}，这条好运请收下{emoji}{tail}",
            "{prefix}隔空给{recipient}送祝福：{casual_wish}{emoji}{tail}",
            "{prefix}不说套话，只希望{recipient}{casual_wish}{emoji}{tail}",
        ),
        {
            "casual_wish": (
                "每天都开开心心",
                "好运爆棚",
                "好事正在路上",
                "今年比去年更快乐",
                "想做的事都能做到",
                "吃好睡好没烦恼",
                "钱包鼓鼓、心情美美",
                "一路升级打怪都顺利",
                "快乐加倍、烦恼清零",
                "被爱也被好运围住",
            ),
            "emoji": ("", "🎉", "✨", "❤️", "🌟", "🍀", "🥳", "🎂", "💐", "🙏"),
        },
    ),
    Family(
        "meta_request",
        False,
        (
            "{prefix}帮我写一段给{recipient}的{occasion}祝福语{tail}",
            "{prefix}有没有适合{occasion}发微信的祝福文案{tail}",
            "{prefix}搜索一下“{occasion}祝福语”{tail}",
            "{prefix}这篇文章讲的是怎么写{occasion}祝福{tail}",
            "{prefix}请把{occasion}祝福模板整理到文档里{tail}",
        ),
        {
            "occasion": (
                "生日",
                "春节",
                "婚礼",
                "毕业",
                "升职",
                "乔迁",
                "康复",
                "开业",
                "考试",
                "旅行",
            ),
        },
    ),
    Family(
        "received_thanks",
        False,
        (
            "{prefix}谢谢{recipient}发来的祝福{tail}",
            "{prefix}今天收到了很多{occasion}祝福，统一感谢大家{tail}",
            "{prefix}你的祝福我已经收到啦{tail}",
            "{prefix}群里都在回复大家的{occasion}祝福{tail}",
            "{prefix}感谢所有人记得我的{occasion}{tail}",
        ),
        {
            "occasion": (
                "生日",
                "新年",
                "婚礼",
                "毕业",
                "入职",
                "开业",
                "乔迁",
                "纪念日",
            ),
        },
    ),
    Family(
        "celebration_not_wish",
        False,
        (
            "{prefix}我们应该找个时间好好庆祝一下{tail}",
            "{prefix}{occasion}庆祝活动安排在{time}{tail}",
            "{prefix}他们一定是在庆祝{occasion}{tail}",
            "{prefix}我买了蛋糕和红酒准备庆祝{occasion}{tail}",
            "{prefix}庆祝方式已经由活动组确定{tail}",
        ),
        {
            "occasion": (
                "项目上线",
                "生日",
                "新店开业",
                "毕业",
                "比赛胜利",
                "结婚纪念日",
                "搬家",
                "签约成功",
            ),
            "time": (
                "今晚",
                "周五晚上",
                "下班以后",
                "这个周末",
                "下周聚会时",
            ),
        },
    ),
    Family(
        "quoted_documented",
        False,
        (
            "{prefix}文档里引用了“{quoted_wish}”这句话{tail}",
            "{prefix}示例文本是“{quoted_wish}”{tail}",
            "{prefix}老师让我们分析“{quoted_wish}”的句式{tail}",
            "{prefix}海报上印着“{quoted_wish}”{tail}",
            "{prefix}关键词列表里包含“{quoted_wish}”{tail}",
        ),
        {
            "quoted_wish": (
                "祝你生日快乐",
                "愿你平安顺遂",
                "恭喜发财",
                "早日康复",
                "一路顺风",
                "新婚快乐",
                "前程似锦",
                "万事如意",
            ),
        },
    ),
    Family(
        "ordinary_greeting",
        False,
        (
            "{prefix}{greeting}{tail}",
            "{prefix}{recipient}，{greeting}{tail}",
            "{prefix}群里打个招呼：{greeting}{tail}",
            "{prefix}只是来问候一下，{greeting}{tail}",
        ),
        {
            "greeting": (
                "你好",
                "早上好",
                "下午好",
                "晚上好",
                "最近怎么样",
                "好久不见",
                "吃饭了吗",
                "在忙吗",
                "周末有空吗",
                "看到消息回我一下",
            ),
        },
    ),
    Family(
        "positive_feedback",
        False,
        (
            "{prefix}{recipient}这次做得真不错{tail}",
            "{prefix}必须夸一下，{achievement}太棒了{tail}",
            "{prefix}这个结果让我很满意{tail}",
            "{prefix}{recipient}的表现超出预期{tail}",
            "{prefix}大家都觉得{achievement}完成得很好{tail}",
        ),
        {
            "achievement": (
                "项目上线",
                "活动组织",
                "演讲",
                "设计方案",
                "客户沟通",
                "问题处理",
                "比赛表现",
                "课程展示",
            ),
        },
    ),
    Family(
        "future_intent",
        False,
        (
            "{prefix}等会儿再祝{recipient}{occasion}快乐{tail}",
            "{prefix}我还没想好怎么祝{recipient}{occasion}快乐{tail}",
            "{prefix}到时候记得给{recipient}发祝福{tail}",
            "{prefix}祝福的话留到见面再说{tail}",
            "{prefix}先收集素材，之后再写{occasion}祝福{tail}",
        ),
        {
            "occasion": (
                "生日",
                "新年",
                "婚礼",
                "毕业",
                "升职",
                "乔迁",
            ),
        },
    ),
    Family(
        "sarcastic_conditional",
        False,
        (
            "{prefix}那我可真要“恭喜”{recipient}了{tail}",
            "{prefix}恭喜什么，事情还没定呢{tail}",
            "{prefix}如果通过了再说恭喜也不迟{tail}",
            "{prefix}先别祝我好运，结果还不知道{tail}",
            "{prefix}这句“祝你成功”听起来全是反话{tail}",
        ),
        {},
    ),
    Family(
        "lexical_collision",
        False,
        (
            "{prefix}{term}是这份资料里的专有名词{tail}",
            "{prefix}系统正在搜索{term}相关内容{tail}",
            "{prefix}标题中出现了{term}，正文并没有表达祝愿{tail}",
            "{prefix}请统计{term}这个词出现了多少次{tail}",
        ),
        {
            "term": (
                "祝福",
                "祝愿",
                "恭喜",
                "生日快乐",
                "好运",
                "庆祝",
                "祝融",
                "祈福",
                "新年快乐",
                "一路顺风",
            ),
        },
    ),
    Family(
        "reported_third_party",
        False,
        (
            "{prefix}他说想祝{recipient}{occasion}快乐{tail}",
            "{prefix}会议记录称大家向{recipient}表达了祝福{tail}",
            "{prefix}新闻里提到许多人祝愿活动成功{tail}",
            "{prefix}群公告要求每个人准备一句祝福{tail}",
            "{prefix}她转述了别人对{recipient}的祝愿{tail}",
        ),
        {
            "occasion": ("生日", "新年", "毕业", "婚礼", "升职", "乔迁"),
        },
    ),
    Family(
        "wish_word_not_blessing",
        False,
        (
            "{prefix}我的愿望清单还没写完{tail}",
            "{prefix}这个功能满足了用户的愿望{tail}",
            "{prefix}他希望明天不要下雨{tail}",
            "{prefix}项目组希望预算能够获批{tail}",
            "{prefix}我希望文件今天能传完{tail}",
            "{prefix}愿不愿意参加还要再考虑{tail}",
        ),
        {},
    ),
)


EN_FAMILIES = (
    Family(
        "occasion",
        True,
        (
            "{prefix}happy {occasion}, {recipient}{tail}",
            "{prefix}wishing {recipient} a wonderful {occasion}{tail}",
            "{prefix}may this {occasion} bring {recipient} {wish}{tail}",
            "{prefix}sending warm {occasion} wishes to {recipient}{tail}",
        ),
        {
            "occasion": (
                "birthday",
                "New Year",
                "Christmas",
                "anniversary",
                "graduation",
                "wedding day",
                "retirement",
            ),
            "wish": (
                "good health and happiness",
                "peace and joy",
                "many happy memories",
                "success in everything ahead",
                "love and laughter",
                "a bright new chapter",
                "all the good things you deserve",
            ),
        },
    ),
    Family(
        "congratulation",
        True,
        (
            "{prefix}{congrats} on {achievement}{tail}",
            "{prefix}{achievement}—{congrats}{tail}",
            "{prefix}I am so happy for {recipient}; {congrats} on {achievement}{tail}",
            "{prefix}{congrats}! May what comes next be even better{tail}",
        ),
        {
            "congrats": (
                "congratulations",
                "congrats",
                "huge congratulations",
                "well done and congratulations",
                "so happy for you",
            ),
            "achievement": (
                "the new job",
                "your promotion",
                "graduating",
                "passing the exam",
                "winning the competition",
                "the successful launch",
                "your new home",
                "the wedding",
                "the new baby",
                "finishing the marathon",
                "the award",
                "the accepted paper",
            ),
        },
    ),
    Family(
        "health",
        True,
        (
            "{prefix}wishing {recipient} {recovery}{tail}",
            "{prefix}may {recipient} have {recovery}{tail}",
            "{prefix}I sincerely hope {recipient} has {recovery}{tail}",
            "{prefix}sending healing thoughts and wishing {recipient} {recovery}{tail}",
        ),
        {
            "recipient": (
                "you",
                "your mother",
                "your father",
                "our friend in hospital",
                "the patient",
                "her",
                "him",
                "your family",
            ),
            "recovery": (
                "a speedy recovery",
                "good health",
                "a smooth surgery",
                "steady healing",
                "comfort and strength",
                "better days very soon",
                "a safe return home",
                "rest and renewed energy",
            ),
        },
    ),
    Family(
        "travel",
        True,
        (
            "{prefix}safe travels, {recipient}{tail}",
            "{prefix}wishing {recipient} a safe and smooth journey{tail}",
            "{prefix}have a wonderful trip and arrive safely{tail}",
            "{prefix}may the road ahead be easy and full of good memories{tail}",
        ),
        {},
    ),
    Family(
        "study_career",
        True,
        (
            "{prefix}good luck with {event}{tail}",
            "{prefix}wishing {recipient} every success in {event}{tail}",
            "{prefix}hope {event} goes brilliantly for {recipient}{tail}",
            "{prefix}may all your hard work pay off in {event}{tail}",
        ),
        {
            "event": (
                "the exam",
                "the interview",
                "your presentation",
                "the competition",
                "your first day",
                "the product launch",
                "the final defense",
                "the new role",
                "the performance",
                "the application",
            ),
        },
    ),
    Family(
        "general_short",
        True,
        (
            "{prefix}{short_wish}{tail}",
            "{prefix}wishing {recipient} {short_wish}{tail}",
            "{prefix}sending {recipient} one simple wish: {short_wish}{tail}",
            "{prefix}I truly hope {short_wish} is waiting for {recipient}{tail}",
        ),
        {
            "short_wish": (
                "good luck",
                "all the best",
                "every success",
                "peace and happiness",
                "health and joy",
                "a bright future",
                "wonderful things ahead",
                "everything you hope for",
                "many reasons to smile",
                "a smooth road ahead",
                "good fortune",
                "dreams coming true",
            ),
        },
    ),
    Family(
        "day_night",
        True,
        (
            "{prefix}hope {daily_wish} is waiting for {recipient}{tail}",
            "{prefix}wishing {recipient} {daily_wish}{tail}",
            "{prefix}rest well and have {daily_wish}{tail}",
            "{prefix}you have worked hard today; may you have {daily_wish}{tail}",
        ),
        {
            "daily_wish": (
                "a lovely day",
                "a peaceful night",
                "sweet dreams",
                "a relaxing weekend",
                "a great week ahead",
                "a calm evening",
                "a brighter tomorrow",
                "a restful night",
            ),
        },
    ),
    Family(
        "third_person",
        True,
        (
            "{prefix}I sincerely wish {third_person} {wish}{tail}",
            "{prefix}may {third_person} have {wish}{tail}",
            "{prefix}please pass my best wishes to {third_person} for {wish}{tail}",
            "{prefix}we are all hoping {third_person} has {wish}{tail}",
        ),
        {
            "third_person": (
                "her",
                "him",
                "the child",
                "the newlyweds",
                "the new parents",
                "our friend in hospital",
                "the graduating students",
                "the whole team",
            ),
            "wish": (
                "a speedy recovery",
                "good health",
                "every success",
                "peace and happiness",
                "a wonderful future",
                "the result they hope for",
                "strength through this difficult time",
                "many joyful days ahead",
            ),
        },
    ),
    Family(
        "meta_request",
        False,
        (
            "{prefix}write a {occasion} wish for {recipient}{tail}",
            "{prefix}find me a message template for {occasion}{tail}",
            "{prefix}how should I say happy {occasion} in a text{tail}",
            "{prefix}this article explains how to write {occasion} wishes{tail}",
            "{prefix}add the {occasion} greeting templates to the document{tail}",
        ),
        {
            "occasion": (
                "birthday",
                "New Year",
                "wedding",
                "graduation",
                "promotion",
                "housewarming",
                "recovery",
                "retirement",
            ),
        },
    ),
    Family(
        "received_thanks",
        False,
        (
            "{prefix}thank {recipient} for the kind wishes{tail}",
            "{prefix}I received so many {occasion} wishes today{tail}",
            "{prefix}thanks everyone for remembering my {occasion}{tail}",
            "{prefix}your good wishes arrived safely{tail}",
            "{prefix}the group is replying to all the {occasion} messages{tail}",
        ),
        {
            "occasion": (
                "birthday",
                "New Year",
                "wedding",
                "graduation",
                "promotion",
                "anniversary",
            ),
        },
    ),
    Family(
        "celebration",
        False,
        (
            "{prefix}we should celebrate {event} properly{tail}",
            "{prefix}the celebration for {event} is scheduled for tomorrow{tail}",
            "{prefix}they must be celebrating {event}{tail}",
            "{prefix}I bought cake to celebrate {event}{tail}",
            "{prefix}the events team finalized the celebration plan{tail}",
        ),
        {
            "event": (
                "the launch",
                "the birthday",
                "the opening",
                "graduation",
                "the victory",
                "the anniversary",
                "the move",
                "the signed contract",
            ),
        },
    ),
    Family(
        "quoted",
        False,
        (
            '{prefix}the document quotes "{quoted_wish}" as an example{tail}',
            '{prefix}the sample text reads "{quoted_wish}"{tail}',
            '{prefix}we are analyzing the wording of "{quoted_wish}"{tail}',
            '{prefix}the poster has "{quoted_wish}" printed on it{tail}',
            '{prefix}the keyword list includes "{quoted_wish}"{tail}',
        ),
        {
            "quoted_wish": (
                "happy birthday",
                "wishing you all the best",
                "congratulations",
                "get well soon",
                "safe travels",
                "happy wedding day",
                "good luck",
                "sweet dreams",
            ),
        },
    ),
    Family(
        "greeting",
        False,
        (
            "{prefix}{greeting}{tail}",
            "{prefix}{greeting}, {recipient}{tail}",
            "{prefix}just stopping by to say {greeting}{tail}",
            "{prefix}a simple greeting: {greeting}{tail}",
        ),
        {
            "greeting": (
                "hello",
                "good morning",
                "good afternoon",
                "good evening",
                "how are you",
                "long time no see",
                "are you around",
                "what are you up to",
                "did you see my message",
                "how has your week been",
            ),
        },
    ),
    Family(
        "positive_feedback",
        False,
        (
            "{prefix}{recipient} did a great job on {work}{tail}",
            "{prefix}the result of {work} exceeded expectations{tail}",
            "{prefix}everyone was impressed by {work}{tail}",
            "{prefix}I really liked how {recipient} handled {work}{tail}",
            "{prefix}this is excellent work and deserves recognition{tail}",
        ),
        {
            "work": (
                "the launch",
                "the presentation",
                "the design",
                "the client call",
                "the incident",
                "the event",
                "the report",
                "the performance",
            ),
        },
    ),
    Family(
        "future_intent",
        False,
        (
            "{prefix}I will wish {recipient} a happy {occasion} later{tail}",
            "{prefix}I have not decided what to write in the {occasion} message{tail}",
            "{prefix}remember to send {recipient} a greeting when the time comes{tail}",
            "{prefix}save the congratulations for the in-person meeting{tail}",
            "{prefix}collect examples before drafting the {occasion} wish{tail}",
        ),
        {
            "occasion": (
                "birthday",
                "New Year",
                "wedding",
                "graduation",
                "promotion",
                "anniversary",
            ),
        },
    ),
    Family(
        "sarcasm",
        False,
        (
            "{prefix}well, I suppose I should \"congratulate\" {recipient}{tail}",
            "{prefix}congratulations for what? Nothing is decided{tail}",
            "{prefix}we can say good luck if the plan is approved{tail}",
            "{prefix}do not wish me luck yet; the result is unknown{tail}",
            "{prefix}that \"all the best\" sounded entirely sarcastic{tail}",
        ),
        {},
    ),
    Family(
        "reported",
        False,
        (
            "{prefix}she said she wanted to wish {recipient} a happy {occasion}{tail}",
            "{prefix}the minutes say everyone sent {recipient} good wishes{tail}",
            "{prefix}the article reports that fans congratulated the winner{tail}",
            "{prefix}the announcement asks everyone to prepare a greeting{tail}",
            "{prefix}he repeated someone else's wishes to {recipient}{tail}",
        ),
        {
            "occasion": (
                "birthday",
                "New Year",
                "wedding",
                "graduation",
                "promotion",
                "anniversary",
            ),
        },
    ),
    Family(
        "wish_word",
        False,
        (
            "{prefix}my wish list is not finished yet{tail}",
            "{prefix}this feature satisfies a common user wish{tail}",
            "{prefix}I hope the upload finishes today{tail}",
            "{prefix}the team hopes the budget gets approved{tail}",
            "{prefix}whether you wish to attend is still undecided{tail}",
            "{prefix}the title contains the word congratulations{tail}",
        ),
        {},
    ),
)


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--seed", type=int, default=SEED)
    parser.add_argument(
        "--records-per-language",
        type=int,
        default=DEFAULT_RECORDS_PER_LANGUAGE,
    )
    parser.add_argument("--base-corpus", type=Path, default=BASE_CORPUS_PATH)
    parser.add_argument("--output", type=Path, default=SUPPLEMENT_PATH)
    parser.add_argument("--combined-output", type=Path, default=COMBINED_PATH)
    parser.add_argument("--summary", type=Path, default=SUMMARY_PATH)
    return parser.parse_args()


def normalized_text(value: str) -> str:
    value = unicodedata.normalize("NFKC", value.replace("\u0000", " "))
    return " ".join(value.split()).strip()


def fingerprint(value: str) -> str:
    return normalized_text(value).casefold()


def required_slots(template: str) -> tuple[str, ...]:
    return tuple(sorted(set(re.findall(r"{([^{}]+)}", template))))


def load_records(path: Path) -> list[dict]:
    return [
        json.loads(line)
        for line in path.read_text(encoding="utf-8").splitlines()
        if line.strip()
    ]


def holdout_fingerprints() -> set[str]:
    values: set[str] = set()
    for path in sorted(OUTPUT_DIRECTORY.glob("*holdout-corpus.jsonl")):
        for record_value in load_records(path):
            values.add(fingerprint(record_value["text"]))
    return values


def allocate_targets(families: tuple[Family, ...], total: int) -> dict[str, int]:
    positive = [family for family in families if family.blessing]
    negative = [family for family in families if not family.blessing]
    positive_total = total // 2
    negative_total = total - positive_total

    def distribute(values: list[Family], desired: int) -> dict[str, int]:
        base, remainder = divmod(desired, len(values))
        return {
            family.name: base + int(index < remainder)
            for index, family in enumerate(values)
        }

    return {
        **distribute(positive, positive_total),
        **distribute(negative, negative_total),
    }


def make_record(
    *,
    language: str,
    family: Family,
    index: int,
    text: str,
) -> dict:
    language_id = "zh" if language == "zh-Hans" else "en"
    return {
        "id": f"targeted-blessing-{language_id}-{family.name}-{index:05d}",
        "text": text,
        "language": language,
        "split": "train",
        "family": f"targeted_blessing_{family.name}",
        "task": False,
        "question": False,
        "invitation": False,
        "complaint": False,
        "scheduleNegotiation": False,
        "confirmationDecision": False,
        "followUpReminder": False,
        "blessing": family.blessing,
        "sentiment": "positive" if family.blessing else "neutral",
        "replyable": False,
        "knownLabels": ["blessing"],
        "labelingMethod": (
            "AI-authored template family under blessing-labeling-guidelines.md"
        ),
        "sourceDataset": "OSGKeyboard broad blessing synthetic v1",
        "sourceLicense": "OSGKeyboard project license",
        "sourceURL": (
            "local://ModelTraining/ClipboardSemantics/"
            "blessing-labeling-guidelines.md"
        ),
        "sourceRevision": SOURCE_REVISION,
        "sourceSplit": "train",
    }


def generate_language(
    *,
    language: str,
    common_slots: dict[str, tuple[str, ...]],
    families: tuple[Family, ...],
    target: int,
    seed: int,
    reserved: set[str],
) -> list[dict]:
    targets = allocate_targets(families, target)
    records: list[dict] = []
    for family in families:
        rng_seed = hashlib.sha256(
            f"{seed}|{language}|{family.name}".encode()
        ).digest()
        rng = random.Random(rng_seed)
        produced = 0
        attempts = 0
        desired = targets[family.name]
        maximum_attempts = desired * 500
        slots = {**common_slots, **family.slots}
        if not family.blessing:
            negative_surface = (
                ZH_NEGATIVE_SURFACE
                if language == "zh-Hans"
                else EN_NEGATIVE_SURFACE
            )
            slots.update(negative_surface)
        while produced < desired and attempts < maximum_attempts:
            attempts += 1
            template = rng.choice(family.templates)
            values = {
                key: rng.choice(slots[key])
                for key in required_slots(template)
            }
            text = normalized_text(template.format(**values))
            if not family.blessing:
                context = rng.choice(
                    ZH_NEGATIVE_CONTEXT
                    if language == "zh-Hans"
                    else EN_NEGATIVE_CONTEXT
                )
                text = normalized_text(f"{text} {context}")
            text_key = fingerprint(text)
            if (
                text_key in reserved
                or not 2 <= len(text) <= 500
                or SENSITIVE_PATTERN.search(text)
            ):
                continue
            reserved.add(text_key)
            produced += 1
            records.append(
                make_record(
                    language=language,
                    family=family,
                    index=produced,
                    text=text,
                )
            )
        if produced != desired:
            raise RuntimeError(
                f"Only generated {produced}/{desired} unique records for "
                f"{language} {family.name}"
            )
    return records


def validate(
    supplement: list[dict],
    base_fingerprints: set[str],
    holdouts: set[str],
    target_per_language: int,
) -> None:
    ids = [record_value["id"] for record_value in supplement]
    texts = [fingerprint(record_value["text"]) for record_value in supplement]
    if len(ids) != len(set(ids)):
        raise ValueError("Duplicate blessing supplement IDs")
    if len(texts) != len(set(texts)):
        raise ValueError("Duplicate blessing supplement text")
    if set(texts).intersection(base_fingerprints):
        raise ValueError("Blessing supplement overlaps the base corpus")
    if set(texts).intersection(holdouts):
        raise ValueError("Blessing supplement overlaps a frozen holdout")
    language_counts = Counter(
        record_value["language"] for record_value in supplement
    )
    if language_counts != {
        "en": target_per_language,
        "zh-Hans": target_per_language,
    }:
        raise ValueError(f"Unexpected language counts: {language_counts}")
    for language in ("en", "zh-Hans"):
        values = [
            record_value
            for record_value in supplement
            if record_value["language"] == language
        ]
        positive = sum(record_value["blessing"] for record_value in values)
        if positive * 2 != len(values):
            raise ValueError(f"Unbalanced blessing labels for {language}")


def write_jsonl(path: Path, records: list[dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        "\n".join(
            json.dumps(record_value, ensure_ascii=False, sort_keys=True)
            for record_value in records
        )
        + "\n",
        encoding="utf-8",
    )


def main() -> None:
    arguments = parse_arguments()
    if arguments.records_per_language < 1_000:
        raise ValueError("--records-per-language must be at least 1000")
    if arguments.records_per_language % 2:
        raise ValueError("--records-per-language must be even")

    base_records = load_records(arguments.base_corpus)
    base_fingerprints = {
        fingerprint(record_value["text"]) for record_value in base_records
    }
    holdouts = holdout_fingerprints()
    reserved = set(base_fingerprints) | holdouts
    supplement = generate_language(
        language="zh-Hans",
        common_slots=ZH_COMMON,
        families=ZH_FAMILIES,
        target=arguments.records_per_language,
        seed=arguments.seed,
        reserved=reserved,
    ) + generate_language(
        language="en",
        common_slots=EN_COMMON,
        families=EN_FAMILIES,
        target=arguments.records_per_language,
        seed=arguments.seed,
        reserved=reserved,
    )
    validate(
        supplement,
        base_fingerprints,
        holdouts,
        arguments.records_per_language,
    )
    write_jsonl(arguments.output, supplement)
    combined = base_records + supplement
    write_jsonl(arguments.combined_output, combined)

    family_counts = Counter(
        record_value["family"] for record_value in supplement
    )
    summary = {
        "schemaVersion": 1,
        "seed": arguments.seed,
        "sourceRevision": SOURCE_REVISION,
        "baseRecords": len(base_records),
        "supplementRecords": len(supplement),
        "combinedRecords": len(combined),
        "labels": {
            "positive": sum(record_value["blessing"] for record_value in supplement),
            "negative": sum(
                not record_value["blessing"] for record_value in supplement
            ),
        },
        "languages": dict(
            sorted(
                Counter(
                    record_value["language"] for record_value in supplement
                ).items()
            )
        ),
        "families": dict(sorted(family_counts.items())),
        "validation": {
            "duplicateIDs": 0,
            "duplicateNormalizedTexts": 0,
            "baseCorpusOverlap": 0,
            "frozenHoldoutOverlap": 0,
            "containsUserClipboardData": False,
        },
        "supplementSHA256": hashlib.sha256(
            arguments.output.read_bytes()
        ).hexdigest(),
        "combinedSHA256": hashlib.sha256(
            arguments.combined_output.read_bytes()
        ).hexdigest(),
    }
    arguments.summary.parent.mkdir(parents=True, exist_ok=True)
    arguments.summary.write_text(
        json.dumps(summary, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    print(json.dumps(summary, ensure_ascii=False, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
