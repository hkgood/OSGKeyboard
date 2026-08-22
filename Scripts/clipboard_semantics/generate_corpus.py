#!/usr/bin/env python3
"""Generate a deterministic multilingual clipboard-intent training corpus.

The corpus is synthetic by design: it contains no user clipboard content.
Template families are split before expansion so paraphrases from one family
cannot leak verbatim across train, validation, and test partitions.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import random
from collections import Counter
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Iterable


SEED = 20260821
TARGETS = {"train": 180, "validation": 45, "test": 45}
FAMILY_TARGETS = {
    "quoted_question": {"train": 100, "validation": 45, "test": 45},
    "negative_news": {"train": 150, "validation": 45, "test": 45},
}


@dataclass(frozen=True)
class Labels:
    task: bool = False
    question: bool = False
    invitation: bool = False
    complaint: bool = False
    sentiment: str = "neutral"


@dataclass(frozen=True)
class Record:
    id: str
    text: str
    language: str
    split: str
    family: str
    task: bool
    question: bool
    invitation: bool
    complaint: bool
    sentiment: str


ZH_SLOTS = {
    "softener": ["麻烦", "请", "方便的话请", "辛苦", "可以帮忙", "请尽快"],
    "action": ["整理", "发送", "确认", "更新", "提交", "核对", "补充", "准备", "预约", "联系"],
    "object": [
        "新版 PRD",
        "会议纪要",
        "项目排期",
        "报价单",
        "合同附件",
        "周报",
        "发票信息",
        "测试结果",
        "客户名单",
        "风险清单",
        "演示文稿",
        "交付计划",
    ],
    "work_item": [
        "整理新版 PRD",
        "发送会议纪要",
        "确认项目排期",
        "更新报价单",
        "提交合同附件",
        "核对发票信息",
        "补充风险清单",
        "准备演示文稿",
        "预约会议室",
        "联系客户",
        "汇总测试结果",
        "分享交付计划",
    ],
    "deadline": [
        "今天下班前",
        "明天上午",
        "周五之前",
        "本周内",
        "下午三点前",
        "下次会议前",
        "月底以前",
        "收到消息后",
    ],
    "recipient": ["我", "产品团队", "客户", "项目群", "财务", "负责人"],
    "context": ["目前", "这次", "在最新版本里", "对新用户来说", "在当前流程中", "按照刚才的消息"],
    "topic": [
        "退款流程",
        "会议安排",
        "项目预算",
        "交付日期",
        "请假制度",
        "付款方式",
        "资料要求",
        "订单状态",
        "活动规则",
        "账户权限",
        "报价变化",
        "行程计划",
    ],
    "event": ["吃饭", "开会", "看电影", "喝咖啡", "项目评审", "客户拜访", "线上沟通", "周末聚会"],
    "time": [
        "今晚七点",
        "明天下午三点",
        "周五上午",
        "下周一中午",
        "这个周末",
        "月底前",
        "下班以后",
        "周三晚上",
    ],
    "place": ["老地方", "五号会议室", "公司楼下", "望京店", "线上会议室", "火车站", "园区咖啡厅", "客户办公室"],
    "issue": [
        "应用一直闪退",
        "订单被重复扣款",
        "文件无法打开",
        "消息始终发不出去",
        "数据同步失败",
        "账号突然被锁定",
        "页面加载特别慢",
        "预约记录消失了",
        "收到的商品有破损",
        "发票信息写错了",
    ],
    "impact": [
        "数据还丢了",
        "已经影响正常工作",
        "我试了很多次都不行",
        "导致今天无法交付",
        "客服一直没有处理",
        "还产生了额外费用",
        "重要记录找不到了",
        "现在完全没法使用",
    ],
    "positive": ["这次更新", "新的语音识别", "客服处理", "键盘体验", "同步速度", "翻译结果", "界面调整", "问题修复"],
    "positive_result": ["非常顺畅", "准确了很多", "比以前方便", "处理得很及时", "效果超出预期", "明显更稳定", "让我很满意", "确实解决了问题"],
    "neutral_subject": ["会议", "订单", "文档", "项目", "航班", "课程", "门店", "系统维护", "快递", "活动"],
    "neutral_fact": ["安排在明天下午", "状态已经更新", "包含三个章节", "将于下周开始", "编号是 A1024", "地点在二楼", "持续大约一小时", "由运营团队负责", "需要现场登记", "目前处于审核阶段"],
    "news_subject": ["行业报告", "新闻文章", "研究材料", "会议记录", "历史资料", "市场分析"],
    "negative_event": ["销量有所下降", "部分地区出现延误", "成本比去年增加", "项目曾经暂停", "结果未达到预期", "天气造成航班取消", "调查发现明显风险", "供应出现短期波动"],
    "quote_speaker": ["文章", "会议纪要", "报告", "客服记录", "培训材料", "新闻"],
}


EN_SLOTS = {
    "softener": ["Please", "Could you", "Would you please", "When you have a moment, please", "Kindly", "Please help"],
    "action": ["prepare", "send", "confirm", "update", "submit", "review", "complete", "check", "schedule", "share"],
    "action_past": ["prepared", "sent", "confirmed", "updated", "submitted", "reviewed", "completed", "checked", "scheduled", "shared"],
    "object": [
        "the revised PRD",
        "the meeting notes",
        "the project timeline",
        "the quotation",
        "the contract attachment",
        "the weekly report",
        "the invoice details",
        "the test results",
        "the client list",
        "the risk register",
        "the presentation deck",
        "the delivery plan",
    ],
    "work_item": [
        "prepare the revised PRD",
        "send the meeting notes",
        "confirm the project timeline",
        "update the quotation",
        "submit the contract attachment",
        "check the invoice details",
        "complete the risk register",
        "prepare the presentation deck",
        "book the meeting room",
        "contact the client",
        "summarize the test results",
        "share the delivery plan",
    ],
    "deadline": [
        "before the end of today",
        "tomorrow morning",
        "by Friday",
        "this week",
        "before 3 PM",
        "before the next meeting",
        "by the end of the month",
        "after you receive this message",
    ],
    "recipient": ["me", "the product team", "the client", "the project channel", "Finance", "the owner"],
    "context": ["currently", "this time", "in the latest version", "for a new user", "in the current process", "based on the latest message"],
    "topic": [
        "the refund process",
        "the meeting schedule",
        "the project budget",
        "the delivery date",
        "the leave policy",
        "the payment method",
        "the required documents",
        "the order status",
        "the event rules",
        "the account permissions",
        "the pricing change",
        "the travel plan",
    ],
    "event": ["have dinner", "join a meeting", "watch a movie", "get coffee", "attend the design review", "visit the client", "have a quick call", "meet this weekend"],
    "time": [
        "at seven tonight",
        "tomorrow at 3 PM",
        "Friday morning",
        "next Monday at noon",
        "this weekend",
        "before the end of the month",
        "after work",
        "Wednesday evening",
    ],
    "place": ["the usual place", "Meeting Room 5", "downstairs from the office", "the Wangjing branch", "the online meeting room", "the station", "the campus cafe", "the client office"],
    "issue": [
        "the app keeps crashing",
        "the order was charged twice",
        "the file will not open",
        "messages never send",
        "data synchronization fails",
        "my account was suddenly locked",
        "the page loads extremely slowly",
        "my reservation disappeared",
        "the item arrived damaged",
        "the invoice information is wrong",
    ],
    "impact": [
        "some data was lost",
        "it is blocking normal work",
        "the issue remains after several attempts",
        "today's delivery is now at risk",
        "support has not resolved it",
        "it caused an extra charge",
        "important records are missing",
        "the service is now unusable",
    ],
    "positive": ["This update", "The new speech recognition", "The support response", "The keyboard experience", "The sync speed", "The translation result", "The interface change", "The latest fix"],
    "positive_result": ["works very smoothly", "is much more accurate", "is easier to use", "was handled promptly", "exceeded my expectations", "is noticeably more stable", "made me very happy", "solved the problem"],
    "neutral_subject": ["The meeting", "The order", "The document", "The project", "The flight", "The course", "The store", "System maintenance", "The delivery", "The event"],
    "neutral_fact": ["is scheduled for tomorrow afternoon", "has an updated status", "contains three sections", "starts next week", "has reference A1024", "is on the second floor", "lasts about one hour", "is owned by Operations", "requires on-site registration", "is currently under review"],
    "news_subject": ["The industry report", "The news article", "The research paper", "The meeting record", "The historical document", "The market analysis"],
    "negative_event": ["reports lower sales", "mentions delays in some regions", "shows higher costs than last year", "describes a project pause", "says the results missed expectations", "covers weather-related flight cancellations", "identifies a material risk", "notes a short-term supply disruption"],
    "quote_speaker": ["The article", "The meeting notes", "The report", "The support transcript", "The training material", "The news story"],
}


FAMILIES = {
    "task_statement": {
        "labels": Labels(task=True),
        "templates": {
            "zh-Hans": {
                "train": [
                    "{softener}{deadline}{work_item}，完成后发给{recipient}。",
                    "这项工作需要{deadline}完成：{work_item}，请同步给{recipient}。",
                    "这件事请你负责：{work_item}，截止时间是{deadline}。",
                    "{deadline}{work_item}，不要遗漏关键信息。",
                ],
                "validation": [
                    "请在{deadline}以前完成这项工作：{work_item}，并通知{recipient}。",
                    "这件事还没处理，麻烦按{deadline}{work_item}。",
                ],
                "test": [
                    "接下来需要你{work_item}，最晚{deadline}给到{recipient}。",
                    "{deadline}是最后期限，请完成：{work_item}。",
                ],
            },
            "en": {
                "train": [
                    "{softener} {work_item} {deadline} and send the result to {recipient}.",
                    "This work needs to be completed {deadline}: {work_item}. Share the result with {recipient}.",
                    "Please own this item: {work_item}, due {deadline}.",
                    "{work_item} {deadline} and include all key details.",
                ],
                "validation": [
                    "Complete this work {deadline}: {work_item}. Then notify {recipient}.",
                    "This item is still pending; please {work_item} {deadline}.",
                ],
                "test": [
                    "Your next action is to {work_item} and deliver the result to {recipient} {deadline}.",
                    "The deadline is {deadline}; make sure you {work_item}.",
                ],
            },
        },
    },
    "task_question": {
        "labels": Labels(task=True, question=True),
        "templates": {
            "zh-Hans": {
                "train": [
                    "你能在{deadline}{work_item}吗？",
                    "可以麻烦你{deadline}{work_item}后把结果发给{recipient}吗？",
                    "方便帮我{work_item}吗？最好{deadline}完成。",
                    "是否可以由你{work_item}，并在{deadline}回复我？",
                ],
                "validation": [
                    "{deadline}之前你能完成这项工作吗：{work_item}？",
                    "这项工作能否请你负责：{work_item}，并同步给{recipient}？",
                ],
                "test": [
                    "我想确认一下，你可以{deadline}{work_item}吗？",
                    "能请你接手这项工作，在{deadline}{work_item}吗？",
                ],
            },
            "en": {
                "train": [
                    "Can you {work_item} {deadline}?",
                    "Could you {work_item} {deadline} and send the result to {recipient}?",
                    "Would you help me {work_item}? It would be best to finish {deadline}.",
                    "Would you be able to {work_item} and reply {deadline}?",
                ],
                "validation": [
                    "Can you complete this item {deadline}: {work_item}?",
                    "Could you take ownership of this item, {work_item}, and update {recipient}?",
                ],
                "test": [
                    "Just checking: are you able to {work_item} {deadline}?",
                    "Could you pick up this item and {work_item} {deadline}?",
                ],
            },
        },
    },
    "information_question": {
        "labels": Labels(question=True),
        "templates": {
            "zh-Hans": {
                "train": [
                    "{context}，{topic}具体是怎么安排的？",
                    "你知道{context}{topic}是什么情况吗？",
                    "关于{topic}，{context}我还需要提供什么信息？",
                    "能告诉我{context}{topic}为什么发生变化吗？",
                ],
                "validation": [
                    "请问{context}哪里可以查到{topic}的详细说明？",
                    "我想了解一下，{context}{topic}最终确定了吗？",
                ],
                "test": [
                    "对于{topic}，{context}有没有明确答案？",
                    "谁能解释一下{context}{topic}接下来怎么处理？",
                ],
            },
            "en": {
                "train": [
                    "How exactly does {topic} work {context}?",
                    "Do you know the status of {topic} {context}?",
                    "What else do I need to provide for {topic} {context}?",
                    "Can you explain why {topic} changed {context}?",
                ],
                "validation": [
                    "Where can I find the detailed policy for {topic} {context}?",
                    "I wanted to check whether {topic} has been finalized {context}.",
                ],
                "test": [
                    "Is there a clear answer regarding {topic} {context}?",
                    "Who can explain what happens next with {topic} {context}?",
                ],
            },
        },
    },
    "invitation_question": {
        "labels": Labels(question=True, invitation=True),
        "templates": {
            "zh-Hans": {
                "train": [
                    "{time}在{place}{event}，你能来吗？",
                    "我们想{time}{event}，地点在{place}，你有空吗？",
                    "要不要{time}一起{event}？可以在{place}见。",
                    "{time}方便参加{event}吗？我们约在{place}。",
                ],
                "validation": [
                    "想邀请你{time}到{place}{event}，可以吗？",
                    "{time}我们准备在{place}{event}，你愿意一起吗？",
                ],
                "test": [
                    "给你留了位置，{time}来{place}{event}怎么样？",
                    "不知道你{time}是否有空，要不要在{place}{event}？",
                ],
            },
            "en": {
                "train": [
                    "We are going to {event} {time} at {place}. Can you come?",
                    "Would you be free to {event} {time} at {place}?",
                    "Do you want to {event} together {time}? We can meet at {place}.",
                    "Can you join us to {event} {time} at {place}?",
                ],
                "validation": [
                    "I would like to invite you to {event} {time} at {place}. Are you available?",
                    "We are planning to {event} at {place} {time}; would you like to join?",
                ],
                "test": [
                    "I saved you a spot to {event} {time} at {place}. How does that sound?",
                    "Not sure if you are free {time}, but would you like to {event} at {place}?",
                ],
            },
        },
    },
    "complaint_statement": {
        "labels": Labels(complaint=True, sentiment="negative"),
        "templates": {
            "zh-Hans": {
                "train": [
                    "{issue}，{impact}，这次体验真的很差。",
                    "从升级以后{issue}，{impact}，我非常失望。",
                    "我要反馈一个严重问题：{issue}，{impact}。",
                    "{issue}已经很久了，{impact}，一直没人解决。",
                ],
                "validation": [
                    "这次服务完全不能接受，{issue}，而且{impact}。",
                    "必须正式反馈：{issue}，目前{impact}。",
                ],
                "test": [
                    "我对处理结果很不满意，{issue}，甚至{impact}。",
                    "{issue}不是第一次发生了，现在{impact}。",
                ],
            },
            "en": {
                "train": [
                    "{issue}, {impact}. This has been a terrible experience.",
                    "Since the update, {issue}, {impact}, and I am very disappointed.",
                    "I need to report a serious problem: {issue}, {impact}.",
                    "{issue} has continued for too long, {impact}, and nobody has fixed it.",
                ],
                "validation": [
                    "This service is unacceptable: {issue}, and {impact}.",
                    "I need to make a formal complaint because {issue}, and {impact}.",
                ],
                "test": [
                    "I am unhappy with the outcome: {issue}, and {impact}.",
                    "This is not the first time that {issue}; now {impact}.",
                ],
            },
        },
    },
    "complaint_request": {
        # A support/repair request is a complaint reply scenario, not a
        # transferable to-do item for the clipboard owner.
        "labels": Labels(question=True, complaint=True, sentiment="negative"),
        "templates": {
            "zh-Hans": {
                "train": [
                    "{issue}，{impact}，你们能尽快处理吗？",
                    "因为{issue}，现在{impact}，可以马上帮我解决吗？",
                    "请问谁能负责处理？{issue}，而且{impact}。",
                    "{issue}已经严重影响使用，能否给出解决方案？",
                ],
                "validation": [
                    "针对{issue}和{impact}，你们什么时候可以修复？",
                    "能请负责人立即跟进吗？{issue}，目前{impact}。",
                ],
                "test": [
                    "{issue}导致{impact}，请告诉我今天能不能处理好？",
                    "我需要明确答复：{issue}，你们准备如何解决？",
                ],
            },
            "en": {
                "train": [
                    "{issue}, {impact}. Can you resolve this as soon as possible?",
                    "Because {issue}, {impact}. Could someone fix it immediately?",
                    "Who is responsible for resolving this? {issue}, and {impact}.",
                    "{issue} is seriously affecting use. Can you provide a solution?",
                ],
                "validation": [
                    "When will you fix the fact that {issue} and {impact}?",
                    "Can the owner follow up immediately? {issue}, and {impact}.",
                ],
                "test": [
                    "{issue}, which means {impact}. Can this be fixed today?",
                    "I need a clear answer: {issue}. How are you going to resolve it?",
                ],
            },
        },
    },
    "self_plan": {
        "labels": Labels(),
        "templates": {
            "zh-Hans": {
                "train": [
                    "我准备{deadline}自己{work_item}。",
                    "这件事我会亲自处理：{work_item}，计划{deadline}开始。",
                    "我的安排是{deadline}{work_item}，暂时不需要别人处理。",
                    "我正在考虑什么时候{work_item}。",
                    "私人备忘：{deadline}{work_item}。",
                    "给自己记一条待办，{deadline}{work_item}。",
                    "这是我的个人计划，不是给别人的任务：{work_item}。",
                ],
                "validation": [
                    "这不是交给你的任务，我打算{deadline}亲自{work_item}。",
                    "这项工作由我自己处理：{work_item}，你不用做任何事情。",
                ],
                "test": [
                    "我只是记录个人计划：{deadline}{work_item}。",
                    "这件事我会自己完成：{work_item}，不是在安排别人。",
                ],
            },
            "en": {
                "train": [
                    "I plan to {work_item} myself {deadline}.",
                    "I will personally {work_item}, starting {deadline}.",
                    "My plan is to {work_item} {deadline}; nobody else needs to handle it.",
                    "I am considering when to {work_item}.",
                    "Private note: {work_item} {deadline}.",
                    "Reminder for myself to {work_item} {deadline}.",
                    "This is my personal plan, not an assignment: {work_item}.",
                ],
                "validation": [
                    "This is not an assignment for you; I will {work_item} myself {deadline}.",
                    "I am going to {work_item}; you do not need to do anything.",
                ],
                "test": [
                    "Personal note only: {work_item} {deadline}.",
                    "I will {work_item} myself, not assign it to someone else.",
                ],
            },
        },
    },
    "event_statement": {
        "labels": Labels(),
        "templates": {
            "zh-Hans": {
                "train": [
                    "{event}已经安排在{time}，地点是{place}。",
                    "通知：{time}将在{place}{event}。",
                    "记录显示他们{time}在{place}{event}。",
                    "{time}的{event}只是一条日程说明，不需要回复。",
                    "行程表写着{time}在{place}{event}，没有邀请收件人参加。",
                    "根据历史记录，他们曾在{time}前往{place}{event}。",
                    "这是公开活动信息：{time}，{place}，{event}。",
                ],
                "validation": [
                    "根据公告，{event}时间为{time}，地点为{place}。",
                    "{event}发生在{time}，参与地点是{place}。",
                ],
                "test": [
                    "文档记载的{event}定于{time}在{place}进行。",
                    "这里仅说明{event}的时间地点：{time}，{place}。",
                ],
            },
            "en": {
                "train": [
                    "The plan says we will {event} {time} at {place}.",
                    "Notice: the group will {event} {time} at {place}.",
                    "The record says they will {event} {time} at {place}.",
                    "The {event} entry for {time} is informational and needs no reply.",
                    "The itinerary lists plans to {event} {time} at {place}; it does not invite the recipient.",
                    "According to the historical record, they went to {event} {time} at {place}.",
                    "This is public event information only: {event}, {time}, {place}.",
                ],
                "validation": [
                    "According to the notice, they will {event} {time} at {place}.",
                    "The scheduled activity is to {event} {time} at {place}.",
                ],
                "test": [
                    "The document records plans to {event} {time} at {place}.",
                    "This line only states the schedule: {event}, {time}, {place}.",
                ],
            },
        },
    },
    "quoted_question": {
        "labels": Labels(),
        "templates": {
            "zh-Hans": {
                "train": [
                    "{quote_speaker}里写着“{topic}是什么情况？”，这里只是在引用原文。",
                    "标题用了问句：{topic}最终确定了吗？正文并不要求读者回复。",
                    "培训材料举例说“你知道{topic}吗？”。",
                    "会议记录保留了问题“{topic}为什么变化？”，但问题已经回答。",
                ],
                "validation": [
                    "{quote_speaker}引用的问题是“哪里可以查到{topic}？”。",
                    "这是文章小标题：关于{topic}，我们知道多少？",
                ],
                "test": [
                    "{quote_speaker}转述了客户的话：“{topic}处理好了吗？”",
                    "文档中的示例问句是“谁负责{topic}？”，不需要当前用户回答。",
                ],
            },
            "en": {
                "train": [
                    "{quote_speaker} says, “What is happening with {topic}?” This is only a quotation.",
                    "The title is a question — Has {topic} been finalized? — but it does not ask the reader to reply.",
                    "The training material uses the example, “Do you know about {topic}?”",
                    "The notes preserve the question “Why did {topic} change?” even though it was answered.",
                ],
                "validation": [
                    "{quote_speaker} quotes the question, “Where can I find {topic}?”",
                    "This is an article heading: What do we know about {topic}?",
                ],
                "test": [
                    "{quote_speaker} retells the customer’s words: “Has {topic} been resolved?”",
                    "The document’s sample question is “Who owns {topic}?” and does not require the current user to answer.",
                ],
            },
        },
    },
    "positive_feedback": {
        "labels": Labels(sentiment="positive"),
        "templates": {
            "zh-Hans": {
                "train": [
                    "{positive}{positive_result}，谢谢你们的努力。",
                    "必须表扬一下，{positive}{positive_result}。",
                    "我很喜欢{positive}，实际使用时{positive_result}。",
                    "{positive_result}，说明{positive}做得很成功。",
                ],
                "validation": [
                    "这次真的值得肯定，{positive}{positive_result}。",
                    "整体体验很好，尤其是{positive}{positive_result}。",
                ],
                "test": [
                    "给个好评：{positive}{positive_result}，继续保持。",
                    "让我惊喜的是{positive}{positive_result}。",
                ],
            },
            "en": {
                "train": [
                    "{positive} {positive_result}. Thank you for the work.",
                    "This deserves praise: {positive} {positive_result}.",
                    "I really like it because {positive} {positive_result}.",
                    "{positive_result}, which shows that {positive} was successful.",
                ],
                "validation": [
                    "This is worth recognizing: {positive} {positive_result}.",
                    "The overall experience is excellent, especially because {positive} {positive_result}.",
                ],
                "test": [
                    "A positive review: {positive} {positive_result}. Keep it up.",
                    "What surprised me is that {positive} {positive_result}.",
                ],
            },
        },
    },
    "neutral_fact": {
        "labels": Labels(),
        "templates": {
            "zh-Hans": {
                "train": [
                    "{neutral_subject}{neutral_fact}。",
                    "资料显示，{neutral_subject}{neutral_fact}。",
                    "这段文字只说明{neutral_subject}{neutral_fact}。",
                    "当前记录：{neutral_subject}{neutral_fact}。",
                ],
                "validation": [
                    "根据现有信息，{neutral_subject}{neutral_fact}。",
                    "备注中提到{neutral_subject}{neutral_fact}。",
                ],
                "test": [
                    "客观事实是{neutral_subject}{neutral_fact}。",
                    "这里只记录一项信息：{neutral_subject}{neutral_fact}。",
                ],
            },
            "en": {
                "train": [
                    "{neutral_subject} {neutral_fact}.",
                    "The available information says {neutral_subject.lower} {neutral_fact}.",
                    "This text only states that {neutral_subject.lower} {neutral_fact}.",
                    "Current record: {neutral_subject} {neutral_fact}.",
                ],
                "validation": [
                    "Based on the available information, {neutral_subject.lower} {neutral_fact}.",
                    "The note mentions that {neutral_subject.lower} {neutral_fact}.",
                ],
                "test": [
                    "The objective fact is that {neutral_subject.lower} {neutral_fact}.",
                    "This records one fact: {neutral_subject} {neutral_fact}.",
                ],
            },
        },
    },
    "negative_news": {
        "labels": Labels(sentiment="negative"),
        "templates": {
            "zh-Hans": {
                "train": [
                    "{news_subject}指出{negative_event}，这是客观描述，不是用户投诉。",
                    "根据{news_subject}，{negative_event}。",
                    "{news_subject}提到{negative_event}，并分析了原因。",
                    "材料记录了一个负面事实：{negative_event}。",
                ],
                "validation": [
                    "{news_subject}显示{negative_event}，没有提出处理要求。",
                    "报道中说{negative_event}，属于第三方事件。",
                ],
                "test": [
                    "历史资料记载{negative_event}，并非当前用户遭遇。",
                    "{news_subject}客观总结：{negative_event}。",
                ],
            },
            "en": {
                "train": [
                    "{news_subject} says it {negative_event}; this is factual reporting, not a user complaint.",
                    "According to {news_subject.lower}, it {negative_event}.",
                    "{news_subject} {negative_event} and analyzes the causes.",
                    "The material records a negative fact: it {negative_event}.",
                ],
                "validation": [
                    "{news_subject} {negative_event} without requesting a resolution.",
                    "The story says it {negative_event}; the event concerns a third party.",
                ],
                "test": [
                    "The historical record {negative_event}; it did not happen to the current user.",
                    "{news_subject} objectively concludes that it {negative_event}.",
                ],
            },
        },
    },
}

GOLDEN_EXAMPLES = [
    # Chinese: manually authored, non-templated holdout for realistic sanity checks.
    ("zh-Hans", "task_statement", "请在周五下班前把新版 PRD 发我，重点补上风险和排期。", Labels(task=True)),
    ("zh-Hans", "task_statement", "小王负责整理会议纪要，今天发到项目群。", Labels(task=True)),
    ("zh-Hans", "task_statement", "记得把发票抬头改好以后重新提交。", Labels(task=True)),
    ("zh-Hans", "task_statement", "下一步先联系客户确认交付地址，再更新订单。", Labels(task=True)),
    ("zh-Hans", "task_question", "你能明天上午把报价单核对一遍吗？", Labels(task=True, question=True)),
    ("zh-Hans", "task_question", "方便帮我约一下周三下午的会议室吗？", Labels(task=True, question=True)),
    ("zh-Hans", "task_question", "这些材料可以在月底前准备好吗？", Labels(task=True, question=True)),
    ("zh-Hans", "information_question", "这个退款流程需要提供哪些材料？", Labels(question=True)),
    ("zh-Hans", "information_question", "订单为什么一直显示审核中？", Labels(question=True)),
    ("zh-Hans", "invitation_question", "今晚七点老地方吃饭，你能来吗？", Labels(question=True, invitation=True)),
    ("zh-Hans", "invitation_question", "周末一起去爬山怎么样？早上九点地铁站见。", Labels(question=True, invitation=True)),
    ("zh-Hans", "invitation_question", "想请你参加下周一的项目启动会，有时间吗？", Labels(question=True, invitation=True)),
    ("zh-Hans", "invitation_question", "下班后要不要一起喝杯咖啡？", Labels(question=True, invitation=True)),
    ("zh-Hans", "complaint_statement", "这个版本升级后一直闪退，数据还丢了，真的很失望。", Labels(complaint=True, sentiment="negative")),
    ("zh-Hans", "complaint_statement", "同一笔订单扣了两次款，到现在都没有退回。", Labels(complaint=True, sentiment="negative")),
    ("zh-Hans", "complaint_statement", "收到的商品外包装破损，里面的杯子也碎了。", Labels(complaint=True, sentiment="negative")),
    ("zh-Hans", "complaint_request", "账号无故被锁了，能请你们今天恢复吗？", Labels(question=True, complaint=True, sentiment="negative")),
    ("zh-Hans", "complaint_request", "消息一直发送失败，请尽快给我一个解决方案。", Labels(complaint=True, sentiment="negative")),
    ("zh-Hans", "complaint_request", "客服已经三天没有回复了，请问什么时候能处理？", Labels(question=True, complaint=True, sentiment="negative")),
    ("zh-Hans", "self_plan", "我打算周五自己整理完这份报告。", Labels()),
    ("zh-Hans", "self_plan", "明天我要去财务核对发票，不用你帮忙。", Labels()),
    ("zh-Hans", "self_plan", "先记一下：月底前我自己联系客户。", Labels()),
    ("zh-Hans", "event_statement", "设计评审定在8月28日下午三点，地点是五号会议室。", Labels()),
    ("zh-Hans", "event_statement", "今晚七点团队在老地方吃饭，这是活动通知。", Labels()),
    ("zh-Hans", "quoted_question", "报告的标题是“人工智能会取代哪些工作？”。", Labels()),
    ("zh-Hans", "quoted_question", "会议纪要保留了客户的问题：“什么时候可以交付？”", Labels()),
    ("zh-Hans", "neutral_fact", "北京市朝阳区望京街10号是公司的账单地址。", Labels()),
    ("zh-Hans", "neutral_fact", "这不是交给你的任务，只是在说明流程。", Labels()),
    ("zh-Hans", "positive_feedback", "这次更新非常稳定，语音识别准确了很多。", Labels(sentiment="positive")),
    ("zh-Hans", "positive_feedback", "客服很快解决了问题，整个过程很专业。", Labels(sentiment="positive")),
    ("zh-Hans", "positive_feedback", "新的键盘布局顺手多了，我很喜欢。", Labels(sentiment="positive")),
    ("zh-Hans", "neutral_fact", "这是一份包含三个章节的行业分析报告。", Labels()),
    ("zh-Hans", "neutral_fact", "门店营业时间是上午九点到晚上十点。", Labels()),
    ("zh-Hans", "neutral_fact", "订单编号为 A1024，目前正在运输中。", Labels()),
    ("zh-Hans", "negative_news", "报告显示本季度销量下降了百分之十二。", Labels(sentiment="negative")),
    ("zh-Hans", "negative_news", "新闻提到暴雨导致多个航班取消。", Labels(sentiment="negative")),
    ("zh-Hans", "negative_news", "研究发现该方案存在明显的供应链风险。", Labels(sentiment="negative")),
    # English: independently phrased holdout rather than translations of templates.
    ("en", "task_statement", "Please send me the revised product brief by Friday, including the risks and timeline.", Labels(task=True)),
    ("en", "task_statement", "Alex owns the meeting notes and should post them in the project channel today.", Labels(task=True)),
    ("en", "task_statement", "Remember to correct the invoice name and submit it again.", Labels(task=True)),
    ("en", "task_statement", "First confirm the delivery address with the client, then update the order.", Labels(task=True)),
    ("en", "task_question", "Can you double-check the quotation tomorrow morning?", Labels(task=True, question=True)),
    ("en", "task_question", "Would you book a meeting room for Wednesday afternoon?", Labels(task=True, question=True)),
    ("en", "task_question", "Could these documents be ready by the end of the month?", Labels(task=True, question=True)),
    ("en", "information_question", "Which documents are required for this refund?", Labels(question=True)),
    ("en", "information_question", "Why is the order still marked as under review?", Labels(question=True)),
    ("en", "invitation_question", "Can you join us for dinner at the usual place at seven tonight?", Labels(question=True, invitation=True)),
    ("en", "invitation_question", "How about hiking together this weekend? Let's meet at the station at nine.", Labels(question=True, invitation=True)),
    ("en", "invitation_question", "I'd like to invite you to Monday's project kickoff. Are you available?", Labels(question=True, invitation=True)),
    ("en", "invitation_question", "Would you like to get coffee after work?", Labels(question=True, invitation=True)),
    ("en", "complaint_statement", "The app has crashed constantly since the update, and I lost important data.", Labels(complaint=True, sentiment="negative")),
    ("en", "complaint_statement", "I was charged twice for the same order and still have not received a refund.", Labels(complaint=True, sentiment="negative")),
    ("en", "complaint_statement", "The package arrived damaged and the cup inside was broken.", Labels(complaint=True, sentiment="negative")),
    ("en", "complaint_request", "My account was locked for no reason. Can you restore it today?", Labels(question=True, complaint=True, sentiment="negative")),
    ("en", "complaint_request", "Messages keep failing to send. Please provide a solution as soon as possible.", Labels(complaint=True, sentiment="negative")),
    ("en", "complaint_request", "Support has not replied for three days. When will this be handled?", Labels(question=True, complaint=True, sentiment="negative")),
    ("en", "self_plan", "I plan to finish organizing this report myself on Friday.", Labels()),
    ("en", "self_plan", "Tomorrow I will check the invoice with Finance; you do not need to help.", Labels()),
    ("en", "self_plan", "Personal reminder: I will contact the client before month-end.", Labels()),
    ("en", "event_statement", "The design review is scheduled for August 28 at 3 PM in Meeting Room 5.", Labels()),
    ("en", "event_statement", "The team dinner is at the usual place at seven tonight; this is an event notice.", Labels()),
    ("en", "quoted_question", "The report is titled “Which jobs will artificial intelligence replace?”", Labels()),
    ("en", "quoted_question", "The meeting notes preserve the client's question: “When can you deliver?”", Labels()),
    ("en", "neutral_fact", "1 Apple Park Way is the company's billing address.", Labels()),
    ("en", "neutral_fact", "This is not an assignment; it only describes the process.", Labels()),
    ("en", "positive_feedback", "This update is remarkably stable and speech recognition is much more accurate.", Labels(sentiment="positive")),
    ("en", "positive_feedback", "Support resolved the issue quickly and handled everything professionally.", Labels(sentiment="positive")),
    ("en", "positive_feedback", "The new keyboard layout feels much better and I really like it.", Labels(sentiment="positive")),
    ("en", "neutral_fact", "This industry report contains three chapters.", Labels()),
    ("en", "neutral_fact", "The store is open from nine in the morning until ten at night.", Labels()),
    ("en", "neutral_fact", "Order A1024 is currently in transit.", Labels()),
    ("en", "negative_news", "The report shows that quarterly sales fell by twelve percent.", Labels(sentiment="negative")),
    ("en", "negative_news", "The news says heavy rain caused several flight cancellations.", Labels(sentiment="negative")),
    ("en", "negative_news", "The study identifies a significant supply-chain risk.", Labels(sentiment="negative")),
]


def render(template: str, values: dict[str, str]) -> str:
    expanded = dict(values)
    expanded.update({f"{key}.lower": value.lower() for key, value in values.items()})
    # str.format cannot resolve dictionary keys containing dots as literals.
    for key, value in values.items():
        template = template.replace("{" + key + ".lower}", value.lower())
    return template.format(**expanded).strip()


def generate_family(
    *,
    family: str,
    language: str,
    split: str,
    templates: list[str],
    slots: dict[str, list[str]],
    labels: Labels,
    target: int,
    seen: set[str],
) -> Iterable[Record]:
    seed_material = f"{SEED}|{family}|{language}|{split}".encode()
    family_seed = int(hashlib.sha256(seed_material).hexdigest()[:16], 16)
    rng = random.Random(family_seed)
    produced = 0
    attempts = 0
    maximum_attempts = target * 200
    keys = sorted(slots)

    while produced < target and attempts < maximum_attempts:
        attempts += 1
        template = rng.choice(templates)
        values = {key: rng.choice(slots[key]) for key in keys}
        text = render(template, values)
        normalized = " ".join(text.split()).casefold()
        if normalized in seen:
            continue
        seen.add(normalized)
        produced += 1
        record_id = f"{split}-{language}-{family}-{produced:04d}"
        yield Record(
            id=record_id,
            text=text,
            language=language,
            split=split,
            family=family,
            task=labels.task,
            question=labels.question,
            invitation=labels.invitation,
            complaint=labels.complaint,
            sentiment=labels.sentiment,
        )

    if produced != target:
        raise RuntimeError(
            f"Only generated {produced}/{target} unique records for "
            f"{family} {language} {split}"
        )


def generate_records() -> list[Record]:
    records: list[Record] = []
    seen: set[str] = set()

    for family, definition in FAMILIES.items():
        labels = definition["labels"]
        for language, slots in (("zh-Hans", ZH_SLOTS), ("en", EN_SLOTS)):
            split_templates = definition["templates"][language]
            family_targets = FAMILY_TARGETS.get(family, TARGETS)
            for split, target in family_targets.items():
                records.extend(
                    generate_family(
                        family=family,
                        language=language,
                        split=split,
                        templates=split_templates[split],
                        slots=slots,
                        labels=labels,
                        target=target,
                        seen=seen,
                    )
                )

    for index, (language, family, text, labels) in enumerate(GOLDEN_EXAMPLES, start=1):
        normalized = " ".join(text.split()).casefold()
        if normalized in seen:
            raise RuntimeError(f"Golden example duplicates generated corpus: {text}")
        seen.add(normalized)
        records.append(
            Record(
                id=f"golden-{language}-{index:04d}",
                text=text,
                language=language,
                split="golden",
                family=family,
                task=labels.task,
                question=labels.question,
                invitation=labels.invitation,
                complaint=labels.complaint,
                sentiment=labels.sentiment,
            )
        )

    records.sort(key=lambda item: item.id)
    return records


def validate(records: list[Record]) -> None:
    if not records:
        raise RuntimeError("Generated corpus is empty")
    texts = [" ".join(record.text.split()).casefold() for record in records]
    if len(texts) != len(set(texts)):
        raise RuntimeError("Corpus contains duplicate normalized text")
    valid_sentiments = {"positive", "neutral", "negative"}
    if any(record.sentiment not in valid_sentiments for record in records):
        raise RuntimeError("Corpus contains an unsupported sentiment label")
    for split in TARGETS:
        if not any(record.split == split for record in records):
            raise RuntimeError(f"Corpus has no {split} records")


def summary(records: list[Record]) -> dict[str, object]:
    split_counts = Counter(record.split for record in records)
    language_counts = Counter(record.language for record in records)
    family_counts = Counter(record.family for record in records)
    intent_counts = {
        intent: sum(bool(getattr(record, intent)) for record in records)
        for intent in ("task", "question", "invitation", "complaint")
    }
    sentiment_counts = Counter(record.sentiment for record in records)
    return {
        "seed": SEED,
        "total": len(records),
        "splits": dict(sorted(split_counts.items())),
        "languages": dict(sorted(language_counts.items())),
        "families": dict(sorted(family_counts.items())),
        "positiveIntentLabels": intent_counts,
        "sentiments": dict(sorted(sentiment_counts.items())),
        "containsUserClipboardData": False,
    }


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("ModelTraining/ClipboardSemantics/clipboard_semantic_corpus.jsonl"),
    )
    parser.add_argument(
        "--summary",
        type=Path,
        default=Path("ModelTraining/ClipboardSemantics/corpus-summary.json"),
    )
    return parser.parse_args()


def main() -> None:
    arguments = parse_arguments()
    records = generate_records()
    validate(records)

    arguments.output.parent.mkdir(parents=True, exist_ok=True)
    with arguments.output.open("w", encoding="utf-8") as output:
        for record in records:
            output.write(json.dumps(asdict(record), ensure_ascii=False, sort_keys=True))
            output.write("\n")

    corpus_summary = summary(records)
    arguments.summary.parent.mkdir(parents=True, exist_ok=True)
    arguments.summary.write_text(
        json.dumps(corpus_summary, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    print(json.dumps(corpus_summary, ensure_ascii=False, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
