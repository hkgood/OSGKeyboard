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
import re
import sys
from collections import Counter
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Iterable


SEED = 20260821
TRAIN_SAMPLE_SCALE = 1
TARGETS = {"train": 180, "validation": 45, "test": 45}
FAMILY_TARGETS = {
    "quoted_question": {"train": 100, "validation": 45, "test": 45},
    "negative_news": {"train": 150, "validation": 45, "test": 45},
    "acknowledgment": {"train": 100, "validation": 45, "test": 45},
}
NEW_INTENTS = (
    "scheduleNegotiation",
    "confirmationDecision",
    "followUpReminder",
    "blessing",
)
SUPPORTED_LANGUAGES = ("en", "zh-Hans")
GOLDEN_MINIMUM_TOTAL = 200
GOLDEN_MINIMUM_PER_LANGUAGE_AND_POLARITY = 10
DISCOURSE_PREFIXES = {
    "zh-Hans": ["", "", "", "另外，", "补充一下，", "还有一件事，", "顺便说一下，"],
    "en": ["", "", "", "Also, ", "One more thing: ", "A quick note: ", "Just to add, "],
}
EXPANDED_FAMILY_NAMES = {
    "complaint_incident_diverse",
    "complaint_implicit_failure",
    "confirmation_selection_short",
    "follow_up_triggered",
    "personal_action_item_boundary",
    "resolved_issue_boundary",
    "task_assignment_diverse",
    "task_completion_boundary",
    "task_indirect_assignment",
    "task_indirect_question",
}


@dataclass(frozen=True)
class Labels:
    task: bool = False
    question: bool = False
    invitation: bool = False
    complaint: bool = False
    scheduleNegotiation: bool = False
    confirmationDecision: bool = False
    followUpReminder: bool = False
    blessing: bool = False
    sentiment: str = "neutral"
    replyable: bool | None = None

    def __post_init__(self) -> None:
        if self.replyable is None:
            inferred = (
                self.task
                or self.question
                or self.invitation
                or self.complaint
                or self.blessing
                or self.sentiment == "positive"
            )
            object.__setattr__(self, "replyable", inferred)


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
    scheduleNegotiation: bool
    confirmationDecision: bool
    followUpReminder: bool
    blessing: bool
    sentiment: str
    replyable: bool


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
    "event": ["吃饭", "开会", "看电影", "喝咖啡", "项目评审", "客户拜访", "线上沟通", "周末聚会", "复诊", "接机", "产品演示", "截止日期"],
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
    "chat_update": ["我刚到家", "我已经出门了", "我这边刚忙完", "今天提前下班了", "路上有点堵", "我刚看到消息", "事情总算处理完了", "明天我可能晚一点", "我到公司了", "刚吃完饭"],
    "chat_detail": ["今天真的累坏了", "现在终于能歇会儿", "整体还挺顺利的", "比预想中快一点", "差点没赶上", "刚才笑死我了", "心情一下好多了", "晚点再和你细说", "这下可以放心了", "感觉还挺有意思"],
    "chat_opener": ["跟你说一声", "对了", "刚想起来", "顺便告诉你", "你绝对想不到", "说真的", "太巧了", "刚刚发生个事"],
    "chat_reaction": ["你也太夸张了", "这个真的有点好笑", "我一开始还不信", "结果居然成了", "这也太巧了吧", "我当场就愣住了", "听起来还不错", "这次确实挺惊喜", "我现在还有点懵", "你说得还真准"],
    "ack_phrase": ["好的", "收到", "知道了", "明白", "行", "可以", "没问题", "嗯嗯", "好嘞", "OK", "记下了", "了解"],
    "ack_closer": ["谢谢", "辛苦了", "我会处理", "晚点看", "先这样", "回头再说", "我记住了", "不用再回复"],
    "alternate_time": ["明天下午四点", "周四上午", "下周二中午", "周五下午两点", "今晚八点", "下周一早上"],
    "option": ["A 方案", "第二版设计", "按月方案", "蓝色版本", "供应商乙", "先发布基础版"],
    "follow_up_action": ["给客户回电话", "确认发票状态", "发送最终版本", "检查审批结果", "预约复诊", "更新项目群", "核对退款进度", "整理会议决定", "联系申请人", "跟进供应商交期", "检查物流状态", "创建发布标签", "记录体温"],
    "vague_future": ["以后有机会再联系", "改天也许会看看", "之后可能聊一下", "未来再考虑", "哪天想起来再说", "有空或许跟进"],
    "blessing_recipient": ["你", "您", "大家", "家人们", "小林", "王老师", "新婚的你们", "团队伙伴们"],
    "blessing_occasion": ["生日", "新年", "春节", "中秋节", "端午节", "毕业", "婚礼", "升职", "开业", "乔迁"],
    "blessing_wish": ["平安顺遂", "天天开心", "心想事成", "身体健康", "前程似锦", "工作顺利", "阖家幸福", "好运常伴", "万事如意", "梦想成真"],
    "third_person": ["小林", "阿杰", "王老师", "李经理", "新郎新娘", "今天的寿星", "毕业班同学", "项目组伙伴"],
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
    "event": ["have dinner", "join a meeting", "watch a movie", "get coffee", "attend the design review", "visit the client", "have a quick call", "meet this weekend", "attend an appointment", "arrange pickup", "give the product demo", "meet the deadline"],
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
    "chat_update": ["I just got home", "I have already left", "I just finished up here", "I got off work early today", "Traffic is a little slow", "I just saw your message", "That is finally sorted out", "I may be a little late tomorrow", "I made it to the office", "I just finished dinner"],
    "chat_detail": ["I am completely exhausted today", "I can finally take a break", "Everything went pretty smoothly", "It was quicker than expected", "I almost missed it", "That made me laugh so hard", "I feel much better now", "I will tell you the rest later", "That is a relief", "It was actually pretty interesting"],
    "chat_opener": ["Just letting you know", "By the way", "I just remembered", "Quick update", "You will never guess this", "Honestly", "What a coincidence", "Something just happened"],
    "chat_reaction": ["You are being so dramatic", "That was genuinely funny", "I did not believe it at first", "It somehow worked out", "What are the odds", "I just stood there stunned", "That actually sounds good", "This was a nice surprise", "I am still processing it", "You were completely right"],
    "ack_phrase": ["Okay", "Got it", "Understood", "Sure", "Sounds good", "No problem", "All right", "Yep", "Noted", "OK", "Will do", "I see"],
    "ack_closer": ["thanks", "appreciate it", "I will handle it", "I will check later", "that is all", "talk later", "I have noted it", "no need to reply"],
    "alternate_time": ["tomorrow at 4 PM", "Thursday morning", "next Tuesday at noon", "Friday at 2 PM", "eight tonight", "next Monday morning"],
    "option": ["option A", "the second design", "the monthly plan", "the blue version", "vendor B", "the basic release first"],
    "follow_up_action": ["call the client back", "check the invoice status", "send the final version", "review the approval result", "book the follow-up visit", "update the project channel", "verify the refund status", "summarize the meeting decisions", "contact the applicant", "check the vendor delivery date", "review the shipment status", "create the release tag", "record my temperature"],
    "vague_future": ["maybe reconnect someday", "perhaps look at it another time", "possibly talk later", "consider it in the future", "mention it whenever it comes up", "perhaps follow up if there is time"],
    "blessing_recipient": ["you", "all of you", "our family", "Maya", "Alex", "Professor Lee", "the newlyweds", "the whole team"],
    "blessing_occasion": ["birthday", "New Year", "Christmas", "graduation", "wedding", "promotion", "new home", "new job", "anniversary", "retirement"],
    "blessing_wish": ["good health and happiness", "a joyful year ahead", "success in everything you do", "peace and good fortune", "a bright future", "many happy memories", "continued success", "dreams coming true", "love and laughter", "a wonderful new chapter"],
    "third_person": ["Maya", "Alex", "Professor Lee", "the newlyweds", "today's birthday star", "the graduating class", "our project team", "the new parents"],
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
                    "请按要求{deadline}{work_item}。",
                    "这项工作由你{work_item}，结果同步给{recipient}。",
                    "这项任务由负责人{deadline}{work_item}。",
                ],
                "validation": [
                    "请在{deadline}以前完成这项工作：{work_item}，并通知{recipient}。",
                    "这件事还没处理，麻烦按{deadline}{work_item}。",
                    "请按计划{deadline}{work_item}，这是你的任务。",
                    "负责人需要先{work_item}，再回复{recipient}。",
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
                    "You are responsible for this item: {work_item}; {recipient} needs the result {deadline}.",
                    "We still need to {work_item} {deadline}.",
                    "Please make sure you {work_item} {deadline}.",
                    "First {work_item}, then send the outcome to {recipient}.",
                    "The owner must {work_item} {deadline}.",
                ],
                "validation": [
                    "Complete this work {deadline}: {work_item}. Then notify {recipient}.",
                    "This item is still pending; please {work_item} {deadline}.",
                    "One thing remains: {work_item}, with an update to {recipient} {deadline}.",
                    "Please complete your assigned item, {work_item}, {deadline}.",
                    "The owner should first {work_item}, then update {recipient}.",
                ],
                "test": [
                    "You own the item to {work_item}; deliver the result to {recipient} {deadline}.",
                    "The deadline is {deadline}; make sure you {work_item}.",
                    "Before we can continue, {work_item} {deadline}.",
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
                    "方便帮我{work_item}吗？时间安排在{time}。",
                    "这些事项能在{deadline}准备好吗：{work_item}？",
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
                    "Would you {work_item} for {time}?",
                    "Could this be ready {deadline}: {work_item}?",
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
    "task_assignment_diverse": {
        "labels": Labels(task=True),
        "templates": {
            "zh-Hans": {
                "train": [
                    "{recipient}还在等{object}，请你{deadline}{action}{object}。",
                    "这项责任归你：{work_item}，交付时间是{deadline}。",
                    "负责人已经指定为你，需要{deadline}{work_item}。",
                    "请接手{topic}相关事项，先{work_item}。",
                    "需要有人完成{work_item}，这次由你负责。",
                    "请把{object}补齐，{deadline}给{recipient}。",
                ],
                "validation": [
                    "{recipient}需要{object}，这项工作请你在{deadline}处理。",
                    "该事项由你承担：{work_item}，期限是{deadline}。",
                    "请负责{topic}，并先完成{work_item}。",
                ],
                "test": [
                    "这项交付明确由你负责，{deadline}{work_item}。",
                    "{recipient}缺少{object}，请你补充并按{deadline}交付。",
                    "分工结果是你来{work_item}，完成后同步结果。",
                ],
            },
            "en": {
                "train": [
                    "{recipient} is still waiting for {object}; please {action} it {deadline}.",
                    "This responsibility is yours: {work_item}, due {deadline}.",
                    "You have been named as the owner and need to {work_item} {deadline}.",
                    "Please take ownership of {topic} and begin by handling {work_item}.",
                    "Someone needs to {work_item}, and you are responsible this time.",
                    "Complete the missing {object} and deliver it to {recipient} {deadline}.",
                ],
                "validation": [
                    "{recipient} needs {object}; please handle this item {deadline}.",
                    "You own this deliverable: {work_item}, with a deadline of {deadline}.",
                    "Take responsibility for {topic} and start by completing {work_item}.",
                ],
                "test": [
                    "This deliverable is explicitly assigned to you: {work_item} {deadline}.",
                    "{recipient} is missing {object}; complete it and deliver it {deadline}.",
                    "The assignment is for you to {work_item} and report the outcome.",
                ],
            },
        },
    },
    "task_indirect_assignment": {
        "labels": Labels(task=True),
        "templates": {
            "zh-Hans": {
                "train": [
                    "想请你接手{topic}，并在{deadline}前{work_item}。",
                    "{object}这项交付安排给你了，麻烦{deadline}收尾。",
                    "如果方便，请你负责{work_item}，完成后同步{recipient}。",
                    "这次需要你来处理{object}，最晚时间是{deadline}。",
                    "请接下{topic}并继续推进，在{deadline}给出结果。",
                    "{recipient}希望由你完成{work_item}。",
                    "请确保{object}在{deadline}前处理完毕。",
                    "这项分工落在你这里：{work_item}。",
                ],
                "validation": [
                    "麻烦你把{object}接过去，{deadline}前处理完成。",
                    "{work_item}已经分配给你，请完成后通知{recipient}。",
                    "这件事需要你负责到底：{topic}。",
                ],
                "test": [
                    "希望你能承担{work_item}，期限是{deadline}。",
                    "请由你完成{object}的最后处理并同步结果。",
                    "{recipient}把{topic}交给你继续推进。",
                ],
            },
            "en": {
                "train": [
                    "Please take ownership of {topic} and {work_item} {deadline}.",
                    "The {object} has been assigned to you; please close it out {deadline}.",
                    "It would help if you could handle {work_item} and update {recipient}.",
                    "We need you to take care of the {object}, no later than {deadline}.",
                    "I am leaving {topic} with you to finish {deadline}.",
                    "{recipient} would like you to complete this: {work_item}.",
                    "Please make sure the {object} is completed {deadline}.",
                    "This assignment now sits with you: {work_item}.",
                ],
                "validation": [
                    "Please pick up the {object} and finish it {deadline}.",
                    "You have been assigned to {work_item}; notify {recipient} when done.",
                    "We are relying on you to own {topic} through completion.",
                ],
                "test": [
                    "You are responsible for {work_item}, due {deadline}.",
                    "Please complete the final handling of the {object} and share the outcome.",
                    "{recipient} has handed {topic} to you for the next stage.",
                ],
            },
        },
    },
    "task_indirect_question": {
        "labels": Labels(task=True, question=True),
        "templates": {
            "zh-Hans": {
                "train": [
                    "你能接手{topic}并在{deadline}{work_item}吗？",
                    "方便由你把{object}收尾后同步{recipient}吗？",
                    "这项分工可以请你负责到底吗？",
                    "能把{object}留给你在{deadline}完成吗？",
                    "你可以确保{work_item}按时完成吗？",
                    "是否能请你处理{topic}并给出结果？",
                ],
                "validation": [
                    "你能承担{work_item}并在{deadline}交付吗？",
                    "可以麻烦你完成{object}的最后处理吗？",
                    "{topic}接下来能由你负责吗？",
                ],
                "test": [
                    "这项工作能交给你在{deadline}收尾吗？",
                    "你方便接下{object}并通知{recipient}吗？",
                    "能请你负责推进{topic}吗？",
                ],
            },
            "en": {
                "train": [
                    "Could you take ownership of {topic} and {work_item} {deadline}?",
                    "Can you close out the {object} and update {recipient}?",
                    "Would you own this assignment through completion?",
                    "Can I leave the {object} with you to finish {deadline}?",
                    "Could you make sure to {work_item} on time?",
                    "Would you handle {topic} and provide the outcome?",
                ],
                "validation": [
                    "Can you take responsibility for {work_item} and deliver {deadline}?",
                    "Could you finish the final handling of the {object}?",
                    "Would you own the next stage of {topic}?",
                ],
                "test": [
                    "Can this work be assigned to you for completion {deadline}?",
                    "Could you pick up the {object} and notify {recipient}?",
                    "Can you be responsible for moving {topic} forward?",
                ],
            },
        },
    },
    "task_completion_boundary": {
        "labels": Labels(task=True),
        "templates": {
            "zh-Hans": {
                "train": [
                    "请现在完成{object}并发给{recipient}，交付后不需要回访。",
                    "{deadline}前把{work_item}做完即可，随后任务关闭。",
                    "这是一项一次性交付：{work_item}。",
                    "只需处理{object}并提交，不涉及后续提醒。",
                ],
                "validation": [
                    "完成{object}后直接结项，不需要再次联系。",
                    "请一次性{work_item}，提交后流程结束。",
                ],
                "test": [
                    "把{object}交给{recipient}就算完成，没有后续动作。",
                    "当前任务仅要求{work_item}。",
                ],
            },
            "en": {
                "train": [
                    "Complete the {object} now and send it to {recipient}; no follow-up is required.",
                    "Finish {work_item} {deadline}, then close the task.",
                    "This is a one-time delivery: {work_item}.",
                    "Only handle the {object} and submit it; there is no later reminder.",
                ],
                "validation": [
                    "Close the item after delivering the {object}; do not follow up later.",
                    "Complete {work_item} once, then end the workflow.",
                ],
                "test": [
                    "The task ends when the {object} reaches {recipient}.",
                    "The current assignment only requires you to {work_item}.",
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
                    "邀请你{time}到{place}{event}，期待你参加。",
                    "{time}一起{event}怎么样？在{place}碰面。",
                    "想请你来{place}{event}，时间是{time}。",
                ],
                "validation": [
                    "想邀请你{time}到{place}{event}，可以吗？",
                    "{time}我们准备在{place}{event}，你愿意一起吗？",
                    "如果你有空，很希望你{time}来{place}{event}。",
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
                    "I was wondering whether you might join us to {event} {time} at {place}.",
                    "It would be lovely to {event} with you {time} at {place}, if you are around.",
                    "You are invited to {event} {time} at {place}.",
                    "We would love you to join us to {event} {time} at {place}.",
                    "How about we {event} together {time}? Let us meet at {place}.",
                    "I would like you to join us at {place} to {event} {time}.",
                ],
                "validation": [
                    "I would like to invite you to {event} {time} at {place}. Are you available?",
                    "We are planning to {event} at {place} {time}; would you like to join?",
                    "Any chance you could make it to {event} {time} at {place}?",
                    "If you are around, we would love you to {event} {time} at {place}.",
                ],
                "test": [
                    "I saved you a spot to {event} {time} at {place}. How does that sound?",
                    "Not sure if you are free {time}, but would you like to {event} at {place}?",
                    "We would be glad to have you with us to {event} {time} at {place}.",
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
                    "说实话这次挺让人失望的，{issue}，而且{impact}。",
                    "本来不想抱怨，但{issue}，现在{impact}。",
                    "这个体验有点离谱：{issue}，{impact}。",
                    "问题是{issue}，而且{impact}。",
                    "直到现在还是{issue}，{impact}。",
                    "我遇到的情况是{issue}，到现在{impact}。",
                ],
                "validation": [
                    "这次服务完全不能接受，{issue}，而且{impact}。",
                    "必须正式反馈：{issue}，目前{impact}。",
                    "我一般不投诉，不过{issue}，还导致{impact}。",
                    "问题一直是{issue}，现在{impact}。",
                    "{issue}，{impact}，确实让人失望。",
                ],
                "test": [
                    "我对处理结果很不满意，{issue}，甚至{impact}。",
                    "{issue}不是第一次发生了，现在{impact}。",
                    "这次确实让人窝火，{issue}，到现在{impact}。",
                ],
            },
            "en": {
                "train": [
                    "{issue}, {impact}. This has been a terrible experience.",
                    "Since the update, {issue}, {impact}, and I am very disappointed.",
                    "I need to report a serious problem: {issue}, {impact}.",
                    "{issue} has continued for too long, {impact}, and nobody has fixed it.",
                    "Unfortunately, {issue}, and {impact}.",
                    "The problem is that {issue}; meanwhile, {impact}.",
                    "It is still true that {issue}, so {impact}.",
                    "What happened is that {issue}; it now means {impact}.",
                ],
                "validation": [
                    "This service is unacceptable: {issue}, and {impact}.",
                    "I need to make a formal complaint because {issue}, and {impact}.",
                    "The problem remains: {issue}, and {impact}.",
                    "Unfortunately, {issue}; as a result, {impact}.",
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
    "complaint_incident_diverse": {
        "labels": Labels(complaint=True, sentiment="negative"),
        "templates": {
            "zh-Hans": {
                "train": [
                    "我已经尝试了好几次，{issue}，现在{impact}。",
                    "同一个问题又出现了：{issue}，直接导致{impact}。",
                    "订单处理明显有误，{issue}，至今没有补救。",
                    "收到的东西有损坏，{issue}，这不能算正常交付。",
                    "连续多天没有进展，{issue}，已经影响到{impact}。",
                    "这不是普通提醒，实际情况是{issue}，而且{impact}。",
                    "服务没有按承诺完成，{issue}，我需要明确处理结果。",
                ],
                "validation": [
                    "重复操作仍然{issue}，目前{impact}。",
                    "问题再次发生：{issue}，并且{impact}。",
                    "交付结果不完整，{issue}，到现在也没人处理。",
                ],
                "test": [
                    "我反复重试还是{issue}，这已经让{impact}。",
                    "实际收到的结果不符合约定，{issue}，请正面处理。",
                    "这个故障持续了几天：{issue}，同时{impact}。",
                ],
            },
            "en": {
                "train": [
                    "I have tried several times, but {issue}, and now {impact}.",
                    "The same problem happened again: {issue}, directly causing {impact}.",
                    "The order was handled incorrectly: {issue}, with no remedy so far.",
                    "The delivery arrived damaged; {issue}, which is not an acceptable result.",
                    "There has been no progress for days: {issue}, and {impact}.",
                    "This is not a routine note: {issue}, and {impact}.",
                    "The service did not deliver what was promised: {issue}. I need a resolution.",
                ],
                "validation": [
                    "Repeated attempts still leave me with this problem: {issue}; {impact}.",
                    "The failure has returned: {issue}, and {impact}.",
                    "The delivery is incomplete because {issue}, and nobody has addressed it.",
                ],
                "test": [
                    "I retried repeatedly and {issue}; this means {impact}.",
                    "What arrived does not match the agreement: {issue}. Please address it.",
                    "This failure has continued for days: {issue}, while {impact}.",
                ],
            },
        },
    },
    "complaint_implicit_failure": {
        "labels": Labels(complaint=True, sentiment="negative"),
        "templates": {
            "zh-Hans": {
                "train": [
                    "{issue}已经是第三次发生了，{impact}。",
                    "从{deadline}到现在一直{issue}，事情完全没有进展。",
                    "原本承诺会处理，但目前仍然{issue}。",
                    "每次尝试都会遇到同样结果：{issue}。",
                    "没有任何人回复，{issue}的问题还在继续。",
                    "实际结果和承诺不一致，导致{impact}。",
                    "到现在为止，{issue}，我只能停在这里。",
                    "同样的问题反复出现，已经不是偶发情况。",
                ],
                "validation": [
                    "{issue}又发生了，已经影响到{impact}。",
                    "等待了很久，结果仍然是{issue}。",
                    "承诺的处理没有发生，现在{impact}。",
                ],
                "test": [
                    "问题没有消失：{issue}，同时{impact}。",
                    "这次依然{issue}，和前两次完全一样。",
                    "处理结果迟迟没有出现，已经造成{impact}。",
                ],
            },
            "en": {
                "train": [
                    "This is the third time that {issue}, and now {impact}.",
                    "Since {deadline}, {issue}, with no progress at all.",
                    "It was supposed to be handled, but {issue} is still the outcome.",
                    "Every attempt ends the same way: {issue}.",
                    "Nobody has responded, and the problem remains: {issue}.",
                    "What happened does not match what was promised, so {impact}.",
                    "At this point, {issue}, and I cannot move forward.",
                    "The same problem keeps returning; this is no longer an isolated incident.",
                ],
                "validation": [
                    "The failure happened again: {issue}, leaving me with {impact}.",
                    "After a long wait, the result is still that {issue}.",
                    "The promised handling never happened, and now {impact}.",
                ],
                "test": [
                    "The problem is still present: {issue}, while {impact}.",
                    "Once again, {issue}, exactly as on the previous attempts.",
                    "There is still no resolution, and {impact}.",
                ],
            },
        },
    },
    "self_plan": {
        "labels": Labels(replyable=False),
        "templates": {
            "zh-Hans": {
                "train": [
                    "我准备{deadline}自己{work_item}。",
                    "这件事我会亲自处理：{work_item}，计划{deadline}开始。",
                    "我的安排是{deadline}{work_item}，暂时不需要别人处理。",
                    "我正在考虑什么时候{work_item}。",
                    "我可能会在{deadline}{work_item}，目前还没决定。",
                    "暂时设想由我自己{work_item}，没有明确时间。",
                    "这是我的个人计划，不是给别人的任务：{work_item}。",
                ],
                "validation": [
                    "这不是交给你的任务，我打算{deadline}亲自{work_item}。",
                    "这项工作由我自己处理：{work_item}，你不用做任何事情。",
                ],
                "test": [
                    "这只是一个未确定的个人想法：以后也许{work_item}，最早也要{deadline}。",
                    "这件事我会自己完成：{work_item}，不是在安排别人。",
                ],
            },
            "en": {
                "train": [
                    "I plan to {work_item} myself {deadline}.",
                    "I will personally {work_item}, starting {deadline}.",
                    "My plan is to {work_item} {deadline}; nobody else needs to handle it.",
                    "I am considering when to {work_item}.",
                    "I may {work_item} {deadline}, but I have not decided.",
                    "I am only considering whether to {work_item}; there is no schedule.",
                    "This is my personal plan, not an assignment: {work_item}.",
                ],
                "validation": [
                    "This is not an assignment for you; I will {work_item} myself {deadline}.",
                    "I am going to {work_item}; you do not need to do anything.",
                ],
                "test": [
                    "This is only an undecided idea: perhaps I will {work_item}, no earlier than {deadline}.",
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
    "conversational_message": {
        "labels": Labels(replyable=True),
        "templates": {
            "zh-Hans": {
                "train": [
                    "{chat_update}，{chat_detail}。",
                    "{chat_opener}，{chat_update}。",
                    "{chat_opener}，{chat_reaction}。",
                    "{chat_update}，{chat_reaction}。",
                ],
                "validation": [
                    "{chat_detail}，所以{chat_opener}。",
                    "刚刚还在想这件事，{chat_reaction}，{chat_update}。",
                ],
                "test": [
                    "跟你分享一下，{chat_update}，{chat_detail}。",
                    "说起来也巧，{chat_reaction}，而且{chat_detail}。",
                ],
            },
            "en": {
                "train": [
                    "{chat_update}, and {chat_detail}.",
                    "{chat_opener}: {chat_update}.",
                    "{chat_opener}: {chat_reaction}.",
                    "{chat_update}, and {chat_reaction}.",
                ],
                "validation": [
                    "{chat_detail}, so {chat_opener}.",
                    "I was just thinking about it: {chat_reaction}, and {chat_update}.",
                ],
                "test": [
                    "A quick thing to share: {chat_update}, and {chat_detail}.",
                    "Funny how things work out; {chat_reaction}, and {chat_detail}.",
                ],
            },
        },
    },
    "acknowledgment": {
        "labels": Labels(replyable=False),
        "templates": {
            "zh-Hans": {
                "train": [
                    "{ack_phrase}。",
                    "我已经看到了，{ack_phrase}。",
                    "回复确认：{ack_phrase}。",
                    "{ack_phrase}，这边{ack_closer}。",
                ],
                "validation": [
                    "嗯，{ack_phrase}。",
                    "{ack_phrase}，{ack_closer}。",
                ],
                "test": [
                    "好，{ack_phrase}。",
                    "简单确认一下：{ack_phrase}，{ack_closer}。",
                ],
            },
            "en": {
                "train": [
                    "{ack_phrase}.",
                    "I have seen it. {ack_phrase}.",
                    "Confirming: {ack_phrase}.",
                    "{ack_phrase}; {ack_closer}.",
                ],
                "validation": [
                    "Yep, {ack_phrase}.",
                    "{ack_phrase}, and {ack_closer}.",
                ],
                "test": [
                    "All right, {ack_phrase}.",
                    "Just confirming: {ack_phrase}; {ack_closer}.",
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
                    "问题已经顺利解决，客服处理得很专业。",
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
                    "Support fixed the issue quickly and handled it professionally.",
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
    "schedule_negotiation": {
        "labels": Labels(
            question=True,
            scheduleNegotiation=True,
            replyable=True,
        ),
        "templates": {
            "zh-Hans": {
                "train": [
                    "原定{time}不太方便，可以改到{alternate_time}吗？",
                    "{time}我有冲突，{alternate_time}你是否有空？",
                    "我们把{event}从{time}挪到{alternate_time}怎么样？",
                    "如果{time}不行，{alternate_time}可以吗？",
                    "{time}和{alternate_time}两个时段，你更方便哪个？",
                    "需要重新安排{event}，{alternate_time}有空吗？",
                    "{event}能提前或延后到{alternate_time}吗？",
                    "换个时间吧，{alternate_time}是否合适？",
                    "这个时间太早，晚一点到{alternate_time}行吗？",
                    "如果{time}不合适，我可以改成{alternate_time}。",
                    "我提议把{event}延期到{alternate_time}。",
                    "能把{event}从{time}挪到{alternate_time}吗？",
                    "{time}我没空，改约{alternate_time}怎么样？",
                    "{event}比{time}晚半小时可以吗？",
                ],
                "validation": [
                    "需要重新协调时间，改成{alternate_time}你方便吗？",
                    "能否不用原来的{time}，换到{alternate_time}？",
                    "{time}和{alternate_time}你选哪个？",
                    "{event}需要改期，{alternate_time}合适吗？",
                ],
                "test": [
                    "{time}赶不上，是否可以另约{alternate_time}？",
                    "关于{event}，我提议改期到{alternate_time}，你觉得呢？",
                ],
            },
            "en": {
                "train": [
                    "The original time, {time}, no longer works. Could we move it to {alternate_time}?",
                    "I have a conflict {time}; would {alternate_time} work for you?",
                    "How about rescheduling {event} from {time} to {alternate_time}?",
                    "If {time} is difficult, could we use {alternate_time} instead?",
                    "Would {alternate_time} suit you better than {time}?",
                    "Which works better for you, {time} or {alternate_time}?",
                    "We need to reschedule {event}. Is {alternate_time} available?",
                    "Could {event} be brought forward or delayed to {alternate_time}?",
                    "This time is too early; would {alternate_time} be better?",
                    "If {time} does not work, I can switch to {alternate_time}.",
                    "I suggest delaying {event} until {alternate_time}.",
                    "Can we shift {event} from {time} to {alternate_time}?",
                    "{time} is unavailable for me; how about {alternate_time} instead?",
                    "Would half an hour later than {time} work for {event}?",
                ],
                "validation": [
                    "We need to find another time. Are you available {alternate_time}?",
                    "Could we replace the original {time} slot with {alternate_time}?",
                    "Which do you prefer, {time} or {alternate_time}?",
                    "{event} needs rescheduling; does {alternate_time} suit you?",
                ],
                "test": [
                    "I cannot make {time}; can we arrange {alternate_time} instead?",
                    "For {event}, I propose moving it to {alternate_time}. Does that work?",
                ],
            },
        },
    },
    "schedule_fixed_invitation_boundary": {
        # A fixed-time invitation asks for attendance, not a different time.
        "labels": Labels(question=True, invitation=True, replyable=True),
        "templates": {
            "zh-Hans": {
                "train": [
                    "{time}在{place}{event}，你要来吗？时间已经确定。",
                    "邀请你{time}到{place}{event}，有空参加吗？",
                    "活动定在{time}，地点是{place}，你能到场吗？",
                    "{time}一起{event}吧，就在{place}，来不来？",
                ],
                "validation": [
                    "时间不变，{time}在{place}{event}，你参加吗？",
                    "给你留了{time}的名额，要来{place}{event}吗？",
                ],
                "test": [
                    "确认邀请：{time}到{place}{event}，你能来吗？",
                    "{event}已经定在{time}，想邀请你到{place}参加。",
                ],
            },
            "en": {
                "train": [
                    "Would you join us to {event} {time} at {place}? The time is fixed.",
                    "You are invited to {event} {time} at {place}. Can you attend?",
                    "The event is set for {time} at {place}; are you coming?",
                    "Let us {event} {time} at {place}. Would you like to come?",
                ],
                "validation": [
                    "The time remains {time}: will you join us to {event} at {place}?",
                    "I saved you a place for {event} {time}. Can you attend?",
                ],
                "test": [
                    "Invitation confirmed for {time} at {place}; can you join us to {event}?",
                    "{event} is already fixed for {time}, and I would like you to attend at {place}.",
                ],
            },
        },
    },
    "confirmation_decision": {
        "labels": Labels(
            confirmationDecision=True,
            replyable=True,
        ),
        "templates": {
            "zh-Hans": {
                "train": [
                    "就这么定了，批准采用{option}，{deadline}通知{recipient}。",
                    "我确认选择{option}，请{deadline}按这个方案执行。",
                    "最终决定用{option}，{recipient}不再比较其他选项。",
                    "{option}通过，可以在{deadline}正式推进。",
                    "我的最终选择是{option}，请{recipient}照此执行。",
                    "正式授权采用{option}，{deadline}开始。",
                    "决定优先处理{topic}，其余选项暂缓。",
                    "我签字确认{option}，可以进入下一步。",
                    "在几个候选中我选{option}，由{recipient}负责。",
                    "我批准{topic}的最终版本，可以签字。",
                    "审批通过：选择{option}。",
                    "我们将优先处理{topic}，其他事项延后。",
                ],
                "validation": [
                    "拍板了，我们选{option}，请{deadline}开始落实。",
                    "明确批准{option}，{recipient}后续以它为准。",
                ],
                "test": [
                    "最终结论：采用{option}，{deadline}可以执行。",
                    "我同意并确认{option}，请{recipient}按这个决定走。",
                ],
            },
            "en": {
                "train": [
                    "It is decided: I approve {option}. Notify {recipient} {deadline}.",
                    "I confirm that we are choosing {option}; please proceed {deadline}.",
                    "The final decision is {option}; {recipient} needs no further comparison.",
                    "{option} is approved and can move forward {deadline}.",
                    "My final choice is {option}; {recipient} should execute it.",
                    "I formally authorize {option}, starting {deadline}.",
                    "The decision is to prioritize {topic} and defer the alternatives.",
                    "I sign off on {option}; it can enter the next stage.",
                    "Among the candidates, I choose {option} and confirm {recipient} as owner.",
                    "I approve the final version of {topic}; it is ready for signature.",
                    "Approved: select {option}.",
                    "We will prioritize {topic} and defer the other items.",
                ],
                "validation": [
                    "Decision made: we are going with {option}. Please implement it {deadline}.",
                    "I explicitly approve {option}; {recipient} should use it as the final choice.",
                ],
                "test": [
                    "Final call: adopt {option} and proceed {deadline}.",
                    "I approve and confirm {option}; {recipient} should treat that as our decision.",
                ],
            },
        },
    },
    "confirmation_selection_short": {
        "labels": Labels(confirmationDecision=True, replyable=True),
        "templates": {
            "zh-Hans": {
                "train": [
                    "不再比较，最终选{option}。",
                    "结论已经确定：采用{option}。",
                    "我拍板用{option}，其他候选停止评估。",
                    "{topic}按当前方案通过。",
                    "正式确认{recipient}作为负责人。",
                    "我的明确选择是{option}。",
                    "审批结论为通过，方案是{option}。",
                ],
                "validation": [
                    "选择已经完成，最后采用{option}。",
                    "这是最终决定：{topic}按现方案推进。",
                    "候选不用再看了，我确认{option}。",
                ],
                "test": [
                    "最终选择就是{option}，不再保留其他方案。",
                    "我已作出决定，{topic}通过。",
                    "负责人确定为{recipient}，这是正式结论。",
                ],
            },
            "en": {
                "train": [
                    "No further comparison; the final choice is {option}.",
                    "The conclusion is settled: adopt {option}.",
                    "I am making the call for {option}; stop reviewing the alternatives.",
                    "The current proposal for {topic} is approved.",
                    "I formally confirm {recipient} as the owner.",
                    "My explicit selection is {option}.",
                    "The approval outcome is yes, using {option}.",
                ],
                "validation": [
                    "The selection is complete; we are using {option}.",
                    "This is the final decision: proceed with the current approach to {topic}.",
                    "Stop reviewing candidates; I confirm {option}.",
                ],
                "test": [
                    "The final choice is {option}, with no alternative retained.",
                    "I have made the decision: {topic} is approved.",
                    "{recipient} is the confirmed owner; this is the formal conclusion.",
                ],
            },
        },
    },
    "acknowledgment_decision_boundary": {
        # Receipt and generic agreement do not select or approve an option.
        "labels": Labels(replyable=False),
        "templates": {
            "zh-Hans": {
                "train": [
                    "{ack_phrase}，关于{topic}的消息收到了。",
                    "{ack_phrase}，我先看看{topic}。",
                    "只是向{recipient}确认收到：{ack_phrase}。",
                    "{ack_phrase}，{topic}暂时还没有决定。",
                    "{ack_phrase}，但这不是{recipient}的最终决定。",
                    "尚未批准{option}，只是确认收到。",
                    "可以先这样，但我稍后才会回复最终选项。",
                    "材料已经看过，是否采用{option}还在评估。",
                    "当前只是风险说明，{topic}并没有审批结论。",
                ],
                "validation": [
                    "我看到了{topic}，但还没选方案。",
                    "{ack_phrase}，等{recipient}讨论后再拍板。",
                ],
                "test": [
                    "已收到{topic}，目前没有批准任何选项。",
                    "{ack_phrase}，这不代表{recipient}的最终决定。",
                ],
            },
            "en": {
                "train": [
                    "{ack_phrase}; I received the message about {topic}.",
                    "{ack_phrase}; I will review {topic} first.",
                    "This only confirms receipt to {recipient}: {ack_phrase}.",
                    "{ack_phrase}, but no decision about {topic} has been made.",
                    "{ack_phrase}, but this is not {recipient}'s final decision.",
                    "{option} has not been approved; this only confirms receipt.",
                    "That is fine for now, but I will provide the final choice later.",
                    "I reviewed the material, but {option} is still being evaluated.",
                    "This is only a risk note; there is no approval decision on {topic}.",
                ],
                "validation": [
                    "I saw the update about {topic}, but I have not chosen an option.",
                    "{ack_phrase}; {recipient} will decide after the discussion.",
                ],
                "test": [
                    "Received the note about {topic}, with no option approved yet.",
                    "{ack_phrase}; this is not {recipient}'s final decision.",
                ],
            },
        },
    },
    "follow_up_action": {
        "labels": Labels(task=True, followUpReminder=True, replyable=True),
        "templates": {
            "zh-Hans": {
                "train": [
                    "下一步请在{deadline}{follow_up_action}。",
                    "记得{deadline}{follow_up_action}，完成后告诉我。",
                    "后续动作是{follow_up_action}，截止{deadline}。",
                    "请设个提醒：{deadline}{follow_up_action}。",
                    "等{topic}处理完，下一步{work_item}。",
                    "当前步骤结束后，记得{work_item}。",
                    "{deadline}跟进{topic}，并通知{recipient}。",
                    "下一项行动：{deadline}{work_item}。",
                    "别忘了{deadline}{work_item}。",
                ],
                "validation": [
                    "{deadline}需要继续跟进，具体是{follow_up_action}。",
                    "别忘了后续{follow_up_action}，时间是{deadline}。",
                    "{topic}结束后，下一项行动是{work_item}。",
                    "{deadline}跟进{topic}，并把结果发给{recipient}。",
                ],
                "test": [
                    "请把{follow_up_action}列为下一项行动，{deadline}执行。",
                    "提醒一下，{deadline}要{follow_up_action}。",
                ],
            },
            "en": {
                "train": [
                    "The next step is to {follow_up_action} {deadline}.",
                    "Remember to {follow_up_action} {deadline}, then let me know.",
                    "The follow-up action is to {follow_up_action}, due {deadline}.",
                    "Set a reminder to {follow_up_action} {deadline}.",
                    "Once {topic} is resolved, {work_item}.",
                    "After the current step, remember to {work_item}.",
                    "Follow up on {topic} {deadline} and update {recipient}.",
                    "Next action: {work_item} {deadline}.",
                    "Do not forget to {work_item} {deadline}.",
                ],
                "validation": [
                    "A follow-up is required {deadline}: {follow_up_action}.",
                    "Do not forget to {follow_up_action} {deadline}.",
                    "After {topic} is complete, the next action is to {work_item}.",
                    "Follow up on {topic} {deadline} and send the result to {recipient}.",
                ],
                "test": [
                    "Make {follow_up_action} the next action and do it {deadline}.",
                    "Reminder: {follow_up_action} {deadline}.",
                ],
            },
        },
    },
    "follow_up_personal_reminder": {
        # Executable reminders for the clipboard owner are follow-ups, but they
        # are not assignments from another person.
        "labels": Labels(followUpReminder=True, replyable=False),
        "templates": {
            "zh-Hans": {
                "train": [
                    "个人提醒：我会在{deadline}{follow_up_action}。",
                    "给自己记一下，{deadline}{follow_up_action}。",
                    "我的后续待办是{follow_up_action}，时间{deadline}。",
                    "提醒我自己{deadline}{follow_up_action}。",
                ],
                "validation": [
                    "这是我的个人后续动作：{deadline}{follow_up_action}。",
                    "自用提醒，{deadline}{follow_up_action}。",
                ],
                "test": [
                    "我需要记住{deadline}{follow_up_action}。",
                    "个人行动项：{follow_up_action}，计划{deadline}完成。",
                ],
            },
            "en": {
                "train": [
                    "Personal reminder: I will {follow_up_action} {deadline}.",
                    "Note to self: {follow_up_action} {deadline}.",
                    "My follow-up action is to {follow_up_action} {deadline}.",
                    "Remind myself to {follow_up_action} {deadline}.",
                ],
                "validation": [
                    "This is my personal next action: {follow_up_action} {deadline}.",
                    "Private reminder to {follow_up_action} {deadline}.",
                ],
                "test": [
                    "I need to remember to {follow_up_action} {deadline}.",
                    "Personal action item: {follow_up_action}, planned for {deadline}.",
                ],
            },
        },
    },
    "personal_action_item_boundary": {
        "labels": Labels(followUpReminder=True, replyable=False),
        "templates": {
            "zh-Hans": {
                "train": [
                    "个人行动项：{deadline}{follow_up_action}。",
                    "这是我自己的清单，之后要{work_item}。",
                    "仅供自己记录：{deadline}{follow_up_action}。",
                    "我给自己安排的下一步是{work_item}。",
                    "自用待办，不是交给别人的任务：{follow_up_action}。",
                    "我的个人事项是等{topic}结束后再{work_item}。",
                ],
                "validation": [
                    "个人清单里记着：{deadline}{follow_up_action}。",
                    "这是我的自用行动项，之后要{work_item}。",
                    "提醒自己在{topic}结束后{follow_up_action}。",
                ],
                "test": [
                    "只给自己看的待办：{work_item}。",
                    "我的下一项个人安排是{deadline}{follow_up_action}。",
                    "这不是委派，只是我自己的提醒。",
                ],
            },
            "en": {
                "train": [
                    "Personal action item: {follow_up_action} {deadline}.",
                    "This is on my own checklist: {work_item}.",
                    "Private note to myself: {follow_up_action} {deadline}.",
                    "My own next step is to {work_item}.",
                    "Self-use todo, not an assignment for anyone else: {follow_up_action}.",
                    "My personal item is to {work_item} after {topic} is complete.",
                ],
                "validation": [
                    "My personal checklist says to {follow_up_action} {deadline}.",
                    "This is my own action item for later: {work_item}.",
                    "Remind myself to {follow_up_action} after {topic}.",
                ],
                "test": [
                    "Todo visible only to me: {work_item}.",
                    "My next personal plan is to {follow_up_action} {deadline}.",
                    "This is not delegated work, only my own reminder.",
                ],
            },
        },
    },
    "resolved_issue_boundary": {
        "labels": Labels(),
        "templates": {
            "zh-Hans": {
                "train": [
                    "{issue}已经处理完成，这里只记录关闭状态。",
                    "{recipient}确认之前的问题已恢复，当前不需要支持。",
                    "{topic}的故障已经解决，没有遗留诉求。",
                    "{object}的最终结果正常，这是一条结案说明。",
                ],
                "validation": [
                    "{topic}的问题已结束，{recipient}确认无需继续处理。",
                    "{issue}已经恢复正常，仅为{recipient}保留记录。",
                ],
                "test": [
                    "{object}当前没有故障，早先的问题已经关闭。",
                    "{topic}已经恢复，{recipient}不需要回复或补救。",
                ],
            },
            "en": {
                "train": [
                    "The issue where {issue} has been resolved; this only records closure.",
                    "{recipient} confirmed that the earlier problem is fixed and no support is needed now.",
                    "The failure involving {topic} is resolved with no remaining request.",
                    "The final outcome for the {object} is normal; this is a closure note.",
                ],
                "validation": [
                    "The problem with {topic} is over, and {recipient} confirmed that no action remains.",
                    "The issue where {issue} is back to normal; this record is only for {recipient}.",
                ],
                "test": [
                    "There is no current failure with the {object}; the earlier problem is closed.",
                    "{topic} has recovered, with no reply or remedy required from {recipient}.",
                ],
            },
        },
    },
    "follow_up_triggered": {
        "labels": Labels(task=True, followUpReminder=True, replyable=True),
        "templates": {
            "zh-Hans": {
                "train": [
                    "等{topic}有结果后，再联系{recipient}确认下一步。",
                    "{deadline}重新检查{topic}，有变化就通知{recipient}。",
                    "收到反馈后的第二天，继续{follow_up_action}。",
                    "先等当前流程结束，然后{work_item}。",
                    "如果{topic}更新了，记得再次{follow_up_action}。",
                    "过两天回头确认{topic}，不要让这件事遗漏。",
                    "完成当前事项以后，需要再次联系{recipient}。",
                ],
                "validation": [
                    "{topic}结束后第二天再{follow_up_action}。",
                    "稍后需要回访{recipient}，确认{topic}的处理进展。",
                    "{deadline}再检查一次{topic}并记录结果。",
                ],
                "test": [
                    "当前步骤完成后，请继续联系{recipient}确认结果。",
                    "隔几天重新查看{topic}，然后同步最新状态。",
                    "下一轮跟进安排在{deadline}，内容是{follow_up_action}。",
                ],
            },
            "en": {
                "train": [
                    "Once {topic} has an outcome, contact {recipient} again to confirm the next step.",
                    "Recheck {topic} {deadline} and notify {recipient} if anything changes.",
                    "On the day after feedback arrives, continue with this action: {follow_up_action}.",
                    "Wait for the current process to finish, then {work_item}.",
                    "If {topic} changes, remember to {follow_up_action} again.",
                    "Return to {topic} in two days so it does not get missed.",
                    "After the current item is complete, contact {recipient} again.",
                ],
                "validation": [
                    "The day after {topic} finishes, {follow_up_action}.",
                    "Check back with {recipient} later and confirm progress on {topic}.",
                    "Review {topic} once more {deadline} and record the result.",
                ],
                "test": [
                    "When the current step is done, contact {recipient} again for the outcome.",
                    "Revisit {topic} after a few days and share the latest status.",
                    "The next follow-up is {deadline}: {follow_up_action}.",
                ],
            },
        },
    },
    "vague_future_boundary": {
        # A possibility without an actor, target, or executable next step is
        # not a follow-up reminder.
        "labels": Labels(),
        "templates": {
            "zh-Hans": {
                "train": [
                    "关于{topic}，{vague_future}，现在不用做什么。",
                    "只是随口一说，{context}{vague_future}。",
                    "{recipient}对{topic}{vague_future}，没有具体行动。",
                    "目前没有后续安排，{context}{vague_future}。",
                ],
                "validation": [
                    "关于{topic}{vague_future}，但还没有明确目标。",
                    "这不是{recipient}的提醒，只是说{vague_future}。",
                ],
                "test": [
                    "{topic}没有确定下一步，{vague_future}。",
                    "{recipient}对{topic}{vague_future}，暂时不安排。",
                ],
            },
            "en": {
                "train": [
                    "Regarding {topic}, we may {vague_future}; nothing needs to happen now.",
                    "It was only a passing thought about {topic}: {vague_future}.",
                    "{recipient} may {vague_future} regarding {topic}, with no concrete action.",
                    "There is no follow-up plan for {topic}; we may {vague_future}.",
                    "This is only an uncertain possibility about {topic}, not an actionable issue.",
                ],
                "validation": [
                    "For {topic}, we may {vague_future}, but there is no defined target.",
                    "This is not a reminder for {recipient}, only a thought that we could {vague_future}.",
                ],
                "test": [
                    "No next step has been set for {topic}; we might {vague_future}.",
                    "Perhaps {recipient} will {vague_future} about {topic}, but nothing is scheduled.",
                ],
            },
        },
    },
    "blessing_message": {
        "labels": Labels(blessing=True, sentiment="positive", replyable=True),
        "templates": {
            "zh-Hans": {
                "train": [
                    "祝{blessing_recipient}{blessing_occasion}快乐，愿{blessing_wish}！",
                    "{blessing_occasion}到了，衷心祝愿{blessing_recipient}{blessing_wish}。",
                    "送上最真诚的祝福，愿{blessing_recipient}{blessing_wish}。",
                    "在这个特别的日子里，祝{blessing_recipient}{blessing_wish}。",
                    "{blessing_recipient}，祝你{blessing_occasion}快乐，未来{blessing_wish}。",
                    "大家一起祝{third_person}{blessing_occasion}快乐，愿今后{blessing_wish}！",
                    "也祝{third_person}{blessing_wish}，一起迎接美好的{blessing_occasion}。",
                    "替大家送一句祝福给{third_person}：愿你{blessing_wish}。",
                ],
                "validation": [
                    "愿{blessing_recipient}在{blessing_occasion}收获快乐，往后{blessing_wish}。",
                    "祝福{third_person}{blessing_occasion}快乐，新阶段{blessing_wish}。",
                    "借这个特别的日子，祝{blessing_recipient}{blessing_wish}。",
                    "我们一起祝{third_person}{blessing_wish}，{blessing_occasion}快乐！",
                ],
                "test": [
                    "把最好的祝愿送给{blessing_recipient}，愿你{blessing_wish}。",
                    "{blessing_occasion}之际，祝{third_person}{blessing_wish}。",
                    "真心祝愿{blessing_recipient}今后{blessing_wish}！",
                ],
            },
            "en": {
                "train": [
                    "Happy {blessing_occasion}, {blessing_recipient}! Wishing you {blessing_wish}.",
                    "Warm wishes to {blessing_recipient} on this {blessing_occasion}; may you have {blessing_wish}.",
                    "Sending my heartfelt wishes to {blessing_recipient} for {blessing_wish}.",
                    "On this special occasion, I wish {blessing_recipient} {blessing_wish}.",
                    "To {blessing_recipient}: happy {blessing_occasion} and best wishes for {blessing_wish}.",
                    "Let us all wish {third_person} a happy {blessing_occasion} and {blessing_wish}.",
                    "Joining everyone in wishing {third_person} {blessing_wish} on this {blessing_occasion}.",
                    "A special wish for {third_person}: may you enjoy {blessing_wish}.",
                ],
                "validation": [
                    "May this {blessing_occasion} bring {blessing_recipient} {blessing_wish}.",
                    "Congratulations to {third_person}; wishing you {blessing_wish}.",
                    "Marking this special day with wishes that {blessing_recipient} enjoys {blessing_wish}.",
                    "We are all wishing {third_person} {blessing_wish}. Happy {blessing_occasion}!",
                ],
                "test": [
                    "All my best to {blessing_recipient}; may the days ahead bring {blessing_wish}.",
                    "For this {blessing_occasion}, wishing {third_person} {blessing_wish}.",
                    "Here is to {blessing_recipient} and {blessing_wish} in the next chapter!",
                ],
            },
        },
    },
    "blessing_boundary": {
        # Occasion mentions and quoted greetings are not blessings unless the
        # writer actually expresses a good wish to someone.
        "labels": Labels(replyable=False),
        "templates": {
            "zh-Hans": {
                "train": [
                    "文档里收录了给{blessing_recipient}的{blessing_occasion}祝福语模板。",
                    "日历显示{blessing_occasion}活动将在下个月举行。",
                    "群里正在讨论怎么给{third_person}写祝福语。",
                    "这是一篇分析{blessing_occasion}贺词写法的文章。",
                    "{third_person}负责整理{blessing_occasion}贺卡名单。",
                    "系统把“愿你{blessing_wish}”识别成了一段示例文本。",
                ],
                "validation": [
                    "{blessing_occasion}祝福模板已保存到共享文档。",
                    "会议只讨论了是否给{third_person}准备贺卡。",
                    "文章引用了一句“祝{blessing_recipient}{blessing_wish}”。",
                    "{third_person}正在统计{blessing_occasion}活动人数。",
                ],
                "test": [
                    "这段资料解释了{blessing_occasion}祝福语的结构。",
                    "群公告要求收集给{third_person}的贺卡内容。",
                    "搜索词是“{blessing_recipient}{blessing_occasion}祝福”。",
                ],
            },
            "en": {
                "train": [
                    "The document contains {blessing_occasion} greeting templates for {blessing_recipient}.",
                    "The calendar lists the {blessing_occasion} event for next month.",
                    "The group is discussing how to write a greeting for {third_person}.",
                    "This article analyzes the wording of {blessing_occasion} cards.",
                    "{third_person} is organizing the {blessing_occasion} card list.",
                    "The system treated “wishing you {blessing_wish}” as sample text.",
                ],
                "validation": [
                    "The {blessing_occasion} message template is stored in the shared document.",
                    "The meeting only discussed whether to prepare a card for {third_person}.",
                    "The article quotes the phrase “wishing {blessing_recipient} {blessing_wish}.”",
                    "{third_person} is counting registrations for the {blessing_occasion} event.",
                ],
                "test": [
                    "This reference explains the structure of a {blessing_occasion} greeting.",
                    "The group notice asks for card messages for {third_person}.",
                    "The search phrase is “{blessing_occasion} wishes for {blessing_recipient}.”",
                ],
            },
        },
    },
}

GOLDEN_EXAMPLES = [
    # Chinese: manually authored, non-templated holdout for realistic sanity checks.
    ("zh-Hans", "task_statement", "请在周五下班前把新版 PRD 发我，重点补上风险和排期。", Labels(task=True)),
    ("zh-Hans", "task_statement", "小王负责整理会议纪要，今天发到项目群。", Labels(task=True)),
    ("zh-Hans", "task_statement", "记得把发票抬头改好以后重新提交。", Labels(task=True, followUpReminder=True)),
    ("zh-Hans", "task_statement", "下一步先联系客户确认交付地址，再更新订单。", Labels(task=True, followUpReminder=True)),
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
    ("zh-Hans", "self_plan", "我打算周五自己整理完这份报告。", Labels(replyable=False)),
    ("zh-Hans", "self_plan", "明天我要去财务核对发票，不用你帮忙。", Labels(replyable=False)),
    ("zh-Hans", "self_plan", "先记一下：月底前我自己联系客户。", Labels(followUpReminder=True, replyable=False)),
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
    ("zh-Hans", "conversational_message", "我刚到家，今天真是累坏了。", Labels(replyable=True)),
    ("zh-Hans", "conversational_message", "哈哈，你刚才那个说法也太好笑了。", Labels(replyable=True)),
    ("zh-Hans", "conversational_message", "事情终于解决了，我现在轻松多了。", Labels(replyable=True)),
    ("zh-Hans", "conversational_message", "今天路上特别堵，我差点没赶上。", Labels(replyable=True)),
    ("zh-Hans", "conversational_message", "你推荐的那家店真不错，我很喜欢。", Labels(replyable=True)),
    ("zh-Hans", "acknowledgment", "好，我知道了。", Labels(replyable=False)),
    ("zh-Hans", "acknowledgment", "收到，谢谢。", Labels(replyable=False)),
    ("zh-Hans", "acknowledgment", "没问题，就这样吧。", Labels(replyable=False)),
    ("zh-Hans", "acknowledgment", "嗯嗯，我记下了。", Labels(replyable=False)),
    # English: independently phrased holdout rather than translations of templates.
    ("en", "task_statement", "Please send me the revised product brief by Friday, including the risks and timeline.", Labels(task=True)),
    ("en", "task_statement", "Alex owns the meeting notes and should post them in the project channel today.", Labels(task=True)),
    ("en", "task_statement", "Remember to correct the invoice name and submit it again.", Labels(task=True, followUpReminder=True)),
    ("en", "task_statement", "First confirm the delivery address with the client, then update the order.", Labels(task=True, followUpReminder=True)),
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
    ("en", "self_plan", "I plan to finish organizing this report myself on Friday.", Labels(replyable=False)),
    ("en", "self_plan", "Tomorrow I will check the invoice with Finance; you do not need to help.", Labels(replyable=False)),
    ("en", "self_plan", "Personal reminder: I will contact the client before month-end.", Labels(followUpReminder=True, replyable=False)),
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
    ("en", "conversational_message", "I just got home, and today completely wore me out.", Labels(replyable=True)),
    ("en", "conversational_message", "That thing you said earlier was genuinely hilarious.", Labels(replyable=True)),
    ("en", "conversational_message", "It finally worked out, and I feel so much better now.", Labels(replyable=True)),
    ("en", "conversational_message", "Traffic was awful today and I nearly missed it.", Labels(replyable=True)),
    ("en", "conversational_message", "The place you recommended was great. I loved it.", Labels(replyable=True)),
    ("en", "acknowledgment", "Okay, I understand.", Labels(replyable=False)),
    ("en", "acknowledgment", "Got it, thanks.", Labels(replyable=False)),
    ("en", "acknowledgment", "No problem. That is all.", Labels(replyable=False)),
    ("en", "acknowledgment", "Yep, I have noted it.", Labels(replyable=False)),
]

# New-intent golden records are manually phrased and remain evaluation-only.
# Each intent has ten positive and ten boundary-negative examples per language.
GOLDEN_EXAMPLES.extend([
    # Schedule negotiation: alternatives and rescheduling are positive.
    ("zh-Hans", "schedule_negotiation_golden", "周三的会我赶不上，改到周四上午十点可以吗？", Labels(question=True, scheduleNegotiation=True, replyable=True)),
    ("zh-Hans", "schedule_negotiation_golden", "原定今晚的晚餐能不能挪到明晚？", Labels(question=True, scheduleNegotiation=True, replyable=True)),
    ("zh-Hans", "schedule_negotiation_golden", "下午两点和三点我都可以，你更倾向哪个时间？", Labels(question=True, scheduleNegotiation=True, replyable=True)),
    ("zh-Hans", "schedule_negotiation_golden", "客户临时有事，咱们另约下周一下午怎么样？", Labels(question=True, scheduleNegotiation=True, replyable=True)),
    ("zh-Hans", "schedule_negotiation_golden", "这个时段太早了，晚半小时是否方便？", Labels(question=True, scheduleNegotiation=True, replyable=True)),
    ("zh-Hans", "schedule_negotiation_golden", "如果周五不行，我可以配合周六上午。", Labels(scheduleNegotiation=True, replyable=True)),
    ("zh-Hans", "schedule_negotiation_golden", "想和你重新协调复诊时间，周二还是周四合适？", Labels(question=True, scheduleNegotiation=True, replyable=True)),
    ("zh-Hans", "schedule_negotiation_golden", "航班改了，接机时间改成晚上九点行吗？", Labels(question=True, scheduleNegotiation=True, replyable=True)),
    ("zh-Hans", "schedule_negotiation_golden", "我们把演示提前到上午，你那边能配合吗？", Labels(question=True, scheduleNegotiation=True, replyable=True)),
    ("zh-Hans", "schedule_negotiation_golden", "我提议延期一天，新的截止时间定在周四如何？", Labels(question=True, scheduleNegotiation=True, replyable=True)),
    ("en", "schedule_negotiation_golden", "I cannot make Wednesday's meeting; could we move it to Thursday at ten?", Labels(question=True, scheduleNegotiation=True, replyable=True)),
    ("en", "schedule_negotiation_golden", "Can we shift tonight's dinner to tomorrow evening?", Labels(question=True, scheduleNegotiation=True, replyable=True)),
    ("en", "schedule_negotiation_golden", "Two or three works for me. Which time suits you better?", Labels(question=True, scheduleNegotiation=True, replyable=True)),
    ("en", "schedule_negotiation_golden", "The client is unavailable, so how about next Monday afternoon instead?", Labels(question=True, scheduleNegotiation=True, replyable=True)),
    ("en", "schedule_negotiation_golden", "This slot is too early. Would half an hour later work?", Labels(question=True, scheduleNegotiation=True, replyable=True)),
    ("en", "schedule_negotiation_golden", "If Friday does not work, I can do Saturday morning.", Labels(scheduleNegotiation=True, replyable=True)),
    ("en", "schedule_negotiation_golden", "We need to reschedule the appointment. Is Tuesday or Thursday better?", Labels(question=True, scheduleNegotiation=True, replyable=True)),
    ("en", "schedule_negotiation_golden", "My flight changed; can pickup move to nine tonight?", Labels(question=True, scheduleNegotiation=True, replyable=True)),
    ("en", "schedule_negotiation_golden", "Could we bring the demo forward to the morning?", Labels(question=True, scheduleNegotiation=True, replyable=True)),
    ("en", "schedule_negotiation_golden", "I suggest a one-day delay, with Thursday as the new deadline. Thoughts?", Labels(question=True, scheduleNegotiation=True, replyable=True)),
    ("zh-Hans", "schedule_negotiation_boundary", "项目启动会定在周一上午九点，请准时参加。", Labels(invitation=True)),
    ("zh-Hans", "schedule_negotiation_boundary", "今晚七点老地方见，你能来吗？", Labels(question=True, invitation=True)),
    ("zh-Hans", "schedule_negotiation_boundary", "日历显示体检时间是8月30日上午。", Labels()),
    ("zh-Hans", "schedule_negotiation_boundary", "会议从十点开始，预计持续一个小时。", Labels()),
    ("zh-Hans", "schedule_negotiation_boundary", "邀请你周五下午参加评审，时间不变。", Labels(invitation=True)),
    ("zh-Hans", "schedule_negotiation_boundary", "她说明天三点到办公室。", Labels()),
    ("zh-Hans", "schedule_negotiation_boundary", "航班计划晚上八点起飞。", Labels()),
    ("zh-Hans", "schedule_negotiation_boundary", "午餐已经订好十二点半的位置。", Labels()),
    ("zh-Hans", "schedule_negotiation_boundary", "发布会安排在下周二，不需要回复。", Labels()),
    ("zh-Hans", "schedule_negotiation_boundary", "周末一起看电影吗？票是周六晚八点的。", Labels(question=True, invitation=True)),
    ("en", "schedule_negotiation_boundary", "The kickoff is fixed for Monday at nine; please attend on time.", Labels(invitation=True)),
    ("en", "schedule_negotiation_boundary", "Can you join us at the usual place at seven tonight?", Labels(question=True, invitation=True)),
    ("en", "schedule_negotiation_boundary", "The calendar lists the checkup for August 30 in the morning.", Labels()),
    ("en", "schedule_negotiation_boundary", "The meeting starts at ten and lasts about an hour.", Labels()),
    ("en", "schedule_negotiation_boundary", "You are invited to Friday's review; the time is unchanged.", Labels(invitation=True)),
    ("en", "schedule_negotiation_boundary", "She said she will arrive at the office at three tomorrow.", Labels()),
    ("en", "schedule_negotiation_boundary", "The flight is scheduled to depart at eight tonight.", Labels()),
    ("en", "schedule_negotiation_boundary", "Lunch is already booked for twelve thirty.", Labels()),
    ("en", "schedule_negotiation_boundary", "The launch is set for next Tuesday and needs no reply.", Labels()),
    ("en", "schedule_negotiation_boundary", "Want to see a movie this weekend? The tickets are for Saturday at eight.", Labels(question=True, invitation=True)),

    # Confirmation decision: explicit approval or final selection is positive.
    ("zh-Hans", "confirmation_decision_golden", "两个版本里我选第二版，就按它上线。", Labels(confirmationDecision=True, replyable=True)),
    ("zh-Hans", "confirmation_decision_golden", "预算我批准了，可以开始采购。", Labels(confirmationDecision=True, replyable=True)),
    ("zh-Hans", "confirmation_decision_golden", "最终拍板用供应商乙，不再比价。", Labels(confirmationDecision=True, replyable=True)),
    ("zh-Hans", "confirmation_decision_golden", "确认采用按月付费方案，请推进签约。", Labels(confirmationDecision=True, replyable=True)),
    ("zh-Hans", "confirmation_decision_golden", "我同意这个发布范围，照此执行。", Labels(confirmationDecision=True, replyable=True)),
    ("zh-Hans", "confirmation_decision_golden", "决定先修稳定性问题，其他需求放到下个版本。", Labels(confirmationDecision=True, replyable=True)),
    ("zh-Hans", "confirmation_decision_golden", "审批通过，选择蓝色包装方案。", Labels(confirmationDecision=True, replyable=True)),
    ("zh-Hans", "confirmation_decision_golden", "不用再讨论了，方案 A 正式通过。", Labels(confirmationDecision=True, replyable=True)),
    ("zh-Hans", "confirmation_decision_golden", "这三个候选里定小李负责，我确认。", Labels(confirmationDecision=True, replyable=True)),
    ("zh-Hans", "confirmation_decision_golden", "可以签字了，我批准这份最终合同。", Labels(confirmationDecision=True, replyable=True)),
    ("en", "confirmation_decision_golden", "Between the two versions, I choose the second. Ship that one.", Labels(confirmationDecision=True, replyable=True)),
    ("en", "confirmation_decision_golden", "I approve the budget; procurement can begin.", Labels(confirmationDecision=True, replyable=True)),
    ("en", "confirmation_decision_golden", "Final decision: use vendor B and stop comparing bids.", Labels(confirmationDecision=True, replyable=True)),
    ("en", "confirmation_decision_golden", "I confirm the monthly plan. Please proceed with the contract.", Labels(confirmationDecision=True, replyable=True)),
    ("en", "confirmation_decision_golden", "I approve this release scope; execute it as written.", Labels(confirmationDecision=True, replyable=True)),
    ("en", "confirmation_decision_golden", "We will fix stability first and defer the other requests.", Labels(confirmationDecision=True, replyable=True)),
    ("en", "confirmation_decision_golden", "Approved: select the blue packaging option.", Labels(confirmationDecision=True, replyable=True)),
    ("en", "confirmation_decision_golden", "No more discussion needed; option A is formally approved.", Labels(confirmationDecision=True, replyable=True)),
    ("en", "confirmation_decision_golden", "Of the three candidates, I confirm Lee as the owner.", Labels(confirmationDecision=True, replyable=True)),
    ("en", "confirmation_decision_golden", "You may sign it; I approve the final contract.", Labels(confirmationDecision=True, replyable=True)),
    ("zh-Hans", "confirmation_decision_boundary", "好的，我收到了。", Labels(replyable=False)),
    ("zh-Hans", "confirmation_decision_boundary", "没问题，我先看看两个方案。", Labels(replyable=False)),
    ("zh-Hans", "confirmation_decision_boundary", "嗯嗯，等大家讨论完再说。", Labels(replyable=False)),
    ("zh-Hans", "confirmation_decision_boundary", "了解，目前还没有最终结论。", Labels(replyable=False)),
    ("zh-Hans", "confirmation_decision_boundary", "消息已阅，不代表审批通过。", Labels(replyable=False)),
    ("zh-Hans", "confirmation_decision_boundary", "可以，我稍后回复选哪个。", Labels(replyable=False)),
    ("zh-Hans", "confirmation_decision_boundary", "谢谢说明，我需要再比较一下。", Labels(replyable=False)),
    ("zh-Hans", "confirmation_decision_boundary", "收到，审批结果明天公布。", Labels(replyable=False)),
    ("zh-Hans", "confirmation_decision_boundary", "行，我知道有这三个候选了。", Labels(replyable=False)),
    ("zh-Hans", "confirmation_decision_boundary", "OK，先把合同发我审阅。", Labels(replyable=False)),
    ("en", "confirmation_decision_boundary", "Okay, I received it.", Labels(replyable=False)),
    ("en", "confirmation_decision_boundary", "No problem; I will review both options first.", Labels(replyable=False)),
    ("en", "confirmation_decision_boundary", "Sure, let us wait until everyone has discussed it.", Labels(replyable=False)),
    ("en", "confirmation_decision_boundary", "Understood, but there is no final conclusion yet.", Labels(replyable=False)),
    ("en", "confirmation_decision_boundary", "Message received; this does not mean approval.", Labels(replyable=False)),
    ("en", "confirmation_decision_boundary", "Sounds good. I will say which one later.", Labels(replyable=False)),
    ("en", "confirmation_decision_boundary", "Thanks for explaining; I still need to compare them.", Labels(replyable=False)),
    ("en", "confirmation_decision_boundary", "Noted. The approval result comes tomorrow.", Labels(replyable=False)),
    ("en", "confirmation_decision_boundary", "All right, I know there are three candidates.", Labels(replyable=False)),
    ("en", "confirmation_decision_boundary", "OK, send me the contract for review first.", Labels(replyable=False)),

    # Follow-up reminders: explicit, executable next actions are positive.
    ("zh-Hans", "follow_up_reminder_golden", "明早九点提醒我给牙医打电话确认复诊。", Labels(followUpReminder=True, replyable=False)),
    ("zh-Hans", "follow_up_reminder_golden", "客户回复后，下一步把最终报价发给财务。", Labels(task=True, followUpReminder=True)),
    ("zh-Hans", "follow_up_reminder_golden", "别忘了周五检查退款有没有到账。", Labels(task=True, followUpReminder=True)),
    ("zh-Hans", "follow_up_reminder_golden", "会后需要整理三个决定并发到项目群。", Labels(task=True, followUpReminder=True)),
    ("zh-Hans", "follow_up_reminder_golden", "给自己记个后续：月底续订域名。", Labels(followUpReminder=True, replyable=False)),
    ("zh-Hans", "follow_up_reminder_golden", "等审批结果出来，请联系申请人说明原因。", Labels(task=True, followUpReminder=True)),
    ("zh-Hans", "follow_up_reminder_golden", "下周一跟进供应商的交货日期。", Labels(task=True, followUpReminder=True)),
    ("zh-Hans", "follow_up_reminder_golden", "提醒目标是今晚把药吃完后记录体温。", Labels(followUpReminder=True, replyable=False)),
    ("zh-Hans", "follow_up_reminder_golden", "这是下一项行动：测试通过后创建发布标签。", Labels(task=True, followUpReminder=True)),
    ("zh-Hans", "follow_up_reminder_golden", "三天后再查一次物流状态，并通知客户。", Labels(task=True, followUpReminder=True)),
    ("en", "follow_up_reminder_golden", "Remind me at nine tomorrow to call the dentist about my follow-up visit.", Labels(followUpReminder=True, replyable=False)),
    ("en", "follow_up_reminder_golden", "Once the client replies, send the final quote to Finance.", Labels(task=True, followUpReminder=True)),
    ("en", "follow_up_reminder_golden", "Do not forget to check whether the refund arrives on Friday.", Labels(task=True, followUpReminder=True)),
    ("en", "follow_up_reminder_golden", "After the meeting, summarize the three decisions in the project channel.", Labels(task=True, followUpReminder=True)),
    ("en", "follow_up_reminder_golden", "Note to self: renew the domain before month-end.", Labels(followUpReminder=True, replyable=False)),
    ("en", "follow_up_reminder_golden", "When approval arrives, contact the applicant and explain the reason.", Labels(task=True, followUpReminder=True)),
    ("en", "follow_up_reminder_golden", "Follow up with the vendor about the delivery date next Monday.", Labels(task=True, followUpReminder=True)),
    ("en", "follow_up_reminder_golden", "Tonight's reminder is to record my temperature after taking the medicine.", Labels(followUpReminder=True, replyable=False)),
    ("en", "follow_up_reminder_golden", "Next action: create the release tag after the tests pass.", Labels(task=True, followUpReminder=True)),
    ("en", "follow_up_reminder_golden", "Check the shipment again in three days and notify the customer.", Labels(task=True, followUpReminder=True)),
    ("zh-Hans", "follow_up_reminder_boundary", "以后有机会再联系吧。", Labels()),
    ("zh-Hans", "follow_up_reminder_boundary", "改天可能会看看这个问题。", Labels()),
    ("zh-Hans", "follow_up_reminder_boundary", "后面也许聊一下，没有具体安排。", Labels()),
    ("zh-Hans", "follow_up_reminder_boundary", "未来再考虑是否需要处理。", Labels()),
    ("zh-Hans", "follow_up_reminder_boundary", "有空的话或许跟进，但不确定。", Labels()),
    ("zh-Hans", "follow_up_reminder_boundary", "先放着，哪天想起来再说。", Labels()),
    ("zh-Hans", "follow_up_reminder_boundary", "这只是一个可能性，不是行动项。", Labels()),
    ("zh-Hans", "follow_up_reminder_boundary", "没有负责人，也没有下一步。", Labels()),
    ("zh-Hans", "follow_up_reminder_boundary", "之后看情况吧，现在不用提醒。", Labels()),
    ("zh-Hans", "follow_up_reminder_boundary", "我们可能会再见，但时间未定。", Labels()),
    ("en", "follow_up_reminder_boundary", "Maybe we will reconnect someday.", Labels()),
    ("en", "follow_up_reminder_boundary", "I might look at this another time.", Labels()),
    ("en", "follow_up_reminder_boundary", "Perhaps we will discuss it later, with no plan yet.", Labels()),
    ("en", "follow_up_reminder_boundary", "We can consider whether to handle it in the future.", Labels()),
    ("en", "follow_up_reminder_boundary", "Someone may follow up if there is time, but it is uncertain.", Labels()),
    ("en", "follow_up_reminder_boundary", "Leave it for now and mention it whenever it comes up.", Labels()),
    ("en", "follow_up_reminder_boundary", "This is only a possibility, not an action item.", Labels()),
    ("en", "follow_up_reminder_boundary", "There is no owner and no next step.", Labels()),
    ("en", "follow_up_reminder_boundary", "We will see what happens later; no reminder is needed now.", Labels()),
    ("en", "follow_up_reminder_boundary", "We may meet again, but no time has been chosen.", Labels()),
    ("zh-Hans", "blessing_golden", "生日快乐！愿你新的一岁平安顺遂，每天都有好心情。", Labels(blessing=True, sentiment="positive")),
    ("zh-Hans", "blessing_golden", "新年快乐，祝你和家人身体健康，万事如意。", Labels(blessing=True, sentiment="positive")),
    ("zh-Hans", "blessing_golden", "中秋团圆，愿大家所念皆如愿，所行皆坦途。", Labels(blessing=True, sentiment="positive")),
    ("zh-Hans", "blessing_golden", "恭喜毕业，祝你前程似锦，在新的旅程里闪闪发光。", Labels(blessing=True, sentiment="positive")),
    ("zh-Hans", "blessing_golden", "祝两位新婚快乐，往后的日子相互陪伴，长长久久。", Labels(blessing=True, sentiment="positive")),
    ("zh-Hans", "blessing_golden", "恭喜升职，祝小陈在新的岗位上一切顺利。", Labels(blessing=True, sentiment="positive")),
    ("zh-Hans", "blessing_golden", "群里的朋友们，一起祝王老师生日快乐、身体健康！", Labels(blessing=True, sentiment="positive")),
    ("zh-Hans", "blessing_golden", "祝宝宝健康成长，也祝新手爸妈每天都有好睡眠。", Labels(blessing=True, sentiment="positive")),
    ("zh-Hans", "blessing_golden", "乔迁之喜，愿你们的新家温暖明亮，常有欢声笑语。", Labels(blessing=True, sentiment="positive")),
    ("zh-Hans", "blessing_golden", "考试加油，愿你从容发挥，取得理想的成绩。", Labels(blessing=True, sentiment="positive")),
    ("en", "blessing_golden", "Happy birthday! Wishing you a joyful year filled with good health and new adventures.", Labels(blessing=True, sentiment="positive")),
    ("en", "blessing_golden", "Happy New Year to you and your family—may the year ahead be peaceful and bright.", Labels(blessing=True, sentiment="positive")),
    ("en", "blessing_golden", "Congratulations on graduating; wishing you every success in the journey ahead.", Labels(blessing=True, sentiment="positive")),
    ("en", "blessing_golden", "Wishing the newlyweds a lifetime of love, laughter, and wonderful memories.", Labels(blessing=True, sentiment="positive")),
    ("en", "blessing_golden", "Congratulations on the promotion, Maya. May you thrive in your new role.", Labels(blessing=True, sentiment="positive")),
    ("en", "blessing_golden", "Everyone, let us wish Alex a very happy birthday and a fantastic year ahead!", Labels(blessing=True, sentiment="positive")),
    ("en", "blessing_golden", "Warm Christmas wishes to the whole team; may your holidays be peaceful and joyful.", Labels(blessing=True, sentiment="positive")),
    ("en", "blessing_golden", "Best wishes for your new home—may it always be filled with warmth and laughter.", Labels(blessing=True, sentiment="positive")),
    ("en", "blessing_golden", "Good luck with your exam tomorrow; I hope all your hard work pays off.", Labels(blessing=True, sentiment="positive")),
    ("en", "blessing_golden", "Congratulations to the new parents, and every good wish for your growing family.", Labels(blessing=True, sentiment="positive")),
    ("zh-Hans", "blessing_boundary", "共享文档里整理了春节祝福语模板。", Labels()),
    ("zh-Hans", "blessing_boundary", "今天是小林生日，蛋糕已经送到会议室。", Labels()),
    ("zh-Hans", "blessing_boundary", "群里在讨论要不要给王老师准备生日贺卡。", Labels()),
    ("zh-Hans", "blessing_boundary", "这篇文章解释了“万事如意”这个成语的来源。", Labels()),
    ("zh-Hans", "blessing_boundary", "日历提醒下周是中秋节。", Labels()),
    ("zh-Hans", "blessing_boundary", "贺卡上原本印着一句祝福，后来被删掉了。", Labels()),
    ("zh-Hans", "blessing_boundary", "请把毕业祝福收集到同一个表格里。", Labels(task=True)),
    ("zh-Hans", "blessing_boundary", "你觉得生日祝福应该写正式一点吗？", Labels(question=True)),
    ("zh-Hans", "blessing_boundary", "系统正在检查这段话是不是新年祝福。", Labels()),
    ("zh-Hans", "blessing_boundary", "公司公布了今年春节放假安排。", Labels()),
    ("en", "blessing_boundary", "The shared document contains a collection of New Year greeting templates.", Labels()),
    ("en", "blessing_boundary", "It is Maya's birthday today, and the cake is already in the meeting room.", Labels()),
    ("en", "blessing_boundary", "The group is deciding whether to prepare a birthday card for Professor Lee.", Labels()),
    ("en", "blessing_boundary", "This article explains the history of the phrase “best wishes.”", Labels()),
    ("en", "blessing_boundary", "The calendar says Christmas is next week.", Labels()),
    ("en", "blessing_boundary", "A greeting used to be printed on the card, but it was removed.", Labels()),
    ("en", "blessing_boundary", "Please collect the graduation messages in one spreadsheet.", Labels(task=True)),
    ("en", "blessing_boundary", "Should a birthday message sound formal?", Labels(question=True)),
    ("en", "blessing_boundary", "The system is checking whether this sentence is a holiday wish.", Labels()),
    ("en", "blessing_boundary", "The company published its New Year holiday schedule.", Labels()),
])

GOLDEN_BOUNDARY_FAMILIES = {
    "scheduleNegotiation": "schedule_negotiation_boundary",
    "confirmationDecision": "confirmation_decision_boundary",
    "followUpReminder": "follow_up_reminder_boundary",
    "blessing": "blessing_boundary",
}


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
    minimum_target: int | None,
    seen: set[str],
    uses_discourse_prefixes: bool,
) -> Iterable[Record]:
    seed_material = f"{SEED}|{family}|{language}|{split}".encode()
    family_seed = int(hashlib.sha256(seed_material).hexdigest()[:16], 16)
    rng = random.Random(family_seed)
    produced = 0
    attempts = 0
    maximum_attempts = target * 200
    while produced < target and attempts < maximum_attempts:
        attempts += 1
        template = rng.choice(templates)
        # Draw only slots referenced by this template. Unrelated vocabulary
        # additions must not perturb deterministic sampling in other families.
        required_keys = sorted(
            {
                placeholder.split(".", maxsplit=1)[0]
                for placeholder in re.findall(r"{([^{}]+)}", template)
            }
        )
        values = {key: rng.choice(slots[key]) for key in required_keys}
        prefix = (
            DISCOURSE_PREFIXES[language][
                rng.randrange(len(DISCOURSE_PREFIXES[language]))
            ]
            if uses_discourse_prefixes
            else ""
        )
        text = prefix + render(template, values)
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
            scheduleNegotiation=labels.scheduleNegotiation,
            confirmationDecision=labels.confirmationDecision,
            followUpReminder=labels.followUpReminder,
            blessing=labels.blessing,
            sentiment=labels.sentiment,
            replyable=bool(labels.replyable),
        )

    if produced != target and (
        minimum_target is None or produced < minimum_target
    ):
        raise RuntimeError(
            f"Only generated {produced}/{target} unique records for "
            f"{family} {language} {split}"
        )
    if produced != target:
        print(
            f"Warning: generated all {produced} unique records available "
            f"for {family} {language} {split}; requested {target}.",
            file=sys.stderr,
        )


def generate_records(profile: str) -> list[Record]:
    records: list[Record] = []
    golden_texts = {
        " ".join(text.split()).casefold()
        for _, _, text, _ in GOLDEN_EXAMPLES
    }
    if len(golden_texts) != len(GOLDEN_EXAMPLES):
        raise RuntimeError("Golden corpus contains duplicate normalized text")
    # Reserve golden text before template expansion so deterministic slot
    # changes can never turn a generated sample into holdout leakage.
    seen: set[str] = set(golden_texts)

    active_families = {
        family: definition
        for family, definition in FAMILIES.items()
        if profile == "expanded" or family not in EXPANDED_FAMILY_NAMES
    }
    for family, definition in active_families.items():
        labels = definition["labels"]
        for language, slots in (("zh-Hans", ZH_SLOTS), ("en", EN_SLOTS)):
            split_templates = definition["templates"][language]
            family_targets = FAMILY_TARGETS.get(family, TARGETS)
            for split, target in family_targets.items():
                scaled_target = (
                    target * TRAIN_SAMPLE_SCALE if split == "train" else target
                )
                records.extend(
                    generate_family(
                        family=family,
                        language=language,
                        split=split,
                        templates=split_templates[split],
                        slots=slots,
                        labels=labels,
                        target=scaled_target,
                        minimum_target=(
                            target
                            if split == "train" and TRAIN_SAMPLE_SCALE > 1
                            else None
                        ),
                        seen=seen,
                        uses_discourse_prefixes=profile == "expanded",
                    )
                )

    for index, (language, family, text, labels) in enumerate(GOLDEN_EXAMPLES, start=1):
        normalized = " ".join(text.split()).casefold()
        if normalized not in golden_texts:
            raise RuntimeError(f"Golden reservation missing for: {text}")
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
                scheduleNegotiation=labels.scheduleNegotiation,
                confirmationDecision=labels.confirmationDecision,
                followUpReminder=labels.followUpReminder,
                blessing=labels.blessing,
                sentiment=labels.sentiment,
                replyable=bool(labels.replyable),
            )
        )

    records.sort(key=lambda item: item.id)
    return records


def validate(records: list[Record]) -> None:
    if not records:
        raise RuntimeError("Generated corpus is empty")
    ids = [record.id for record in records]
    if len(ids) != len(set(ids)):
        raise RuntimeError("Corpus contains duplicate record IDs")
    texts = [" ".join(record.text.split()).casefold() for record in records]
    if len(texts) != len(set(texts)):
        raise RuntimeError("Corpus contains duplicate normalized text")
    text_splits: dict[str, set[str]] = {}
    for record, normalized in zip(records, texts):
        text_splits.setdefault(normalized, set()).add(record.split)
    leaked = [text for text, splits in text_splits.items() if len(splits) > 1]
    if leaked:
        raise RuntimeError(f"Corpus contains cross-split text leakage: {leaked[:3]}")
    valid_sentiments = {"positive", "neutral", "negative"}
    if any(record.sentiment not in valid_sentiments for record in records):
        raise RuntimeError("Corpus contains an unsupported sentiment label")
    for split in TARGETS:
        if not any(record.split == split for record in records):
            raise RuntimeError(f"Corpus has no {split} records")
    for family, definition in FAMILIES.items():
        for language in SUPPORTED_LANGUAGES:
            split_templates = definition["templates"][language]
            normalized_templates = {
                split: {" ".join(template.split()).casefold() for template in templates}
                for split, templates in split_templates.items()
            }
            for left_index, left_split in enumerate(TARGETS):
                for right_split in list(TARGETS)[left_index + 1:]:
                    overlap = normalized_templates[left_split] & normalized_templates[right_split]
                    if overlap:
                        raise RuntimeError(
                            f"Template leakage in {family} {language}: {sorted(overlap)}"
                        )

    golden = [record for record in records if record.split == "golden"]
    if len(golden) < GOLDEN_MINIMUM_TOTAL:
        raise RuntimeError(
            f"Golden corpus has {len(golden)} records; minimum is {GOLDEN_MINIMUM_TOTAL}"
        )
    for intent in NEW_INTENTS:
        boundary_family = GOLDEN_BOUNDARY_FAMILIES[intent]
        for language in SUPPORTED_LANGUAGES:
            positives = sum(
                record.language == language and bool(getattr(record, intent))
                for record in golden
            )
            boundaries = sum(
                record.language == language
                and record.family == boundary_family
                and not bool(getattr(record, intent))
                for record in golden
            )
            if positives < GOLDEN_MINIMUM_PER_LANGUAGE_AND_POLARITY:
                raise RuntimeError(
                    f"Golden {intent} has only {positives} positive {language} records"
                )
            if boundaries < GOLDEN_MINIMUM_PER_LANGUAGE_AND_POLARITY:
                raise RuntimeError(
                    f"Golden {intent} has only {boundaries} boundary-negative "
                    f"{language} records"
                )

    # Synthetic examples must not accidentally resemble copied credentials or
    # direct personal contact data.
    sensitive_patterns = {
        "email": re.compile(r"\b[\w.+-]+@[\w.-]+\.[A-Za-z]{2,}\b"),
        "longPhoneOrCard": re.compile(r"(?<!\d)(?:\d[\s-]?){11,19}(?!\d)"),
        "secret": re.compile(
            r"(?i)\b(?:api[_ -]?key|access[_ -]?token|password|private[_ -]?key)"
            r"\s*[:=]\s*\S+"
        ),
    }
    for record in records:
        if any(character in record.text for character in ("\x00", "\r")):
            raise RuntimeError(f"Control character in record {record.id}")
        for name, pattern in sensitive_patterns.items():
            if pattern.search(record.text):
                raise RuntimeError(
                    f"Potential {name} content in synthetic record {record.id}"
                )


def summary(records: list[Record]) -> dict[str, object]:
    split_counts = Counter(record.split for record in records)
    language_counts = Counter(record.language for record in records)
    family_counts = Counter(record.family for record in records)
    intent_counts = {
        intent: sum(bool(getattr(record, intent)) for record in records)
        for intent in (
            "task",
            "question",
            "invitation",
            "complaint",
            "replyable",
            *NEW_INTENTS,
        )
    }
    labels_by_language = {
        language: {
            intent: {
                "positive": sum(
                    record.language == language and bool(getattr(record, intent))
                    for record in records
                ),
                "negative": sum(
                    record.language == language and not bool(getattr(record, intent))
                    for record in records
                ),
            }
            for intent in (
                "task",
                "question",
                "invitation",
                "complaint",
                "replyable",
                *NEW_INTENTS,
            )
        }
        for language in SUPPORTED_LANGUAGES
    }
    golden_coverage = {
        intent: {
            language: {
                "positive": sum(
                    record.split == "golden"
                    and record.language == language
                    and bool(getattr(record, intent))
                    for record in records
                ),
                "boundaryNegative": sum(
                    record.split == "golden"
                    and record.language == language
                    and record.family == GOLDEN_BOUNDARY_FAMILIES[intent]
                    for record in records
                ),
            }
            for language in SUPPORTED_LANGUAGES
        }
        for intent in NEW_INTENTS
    }
    sentiment_counts = Counter(record.sentiment for record in records)
    return {
        "seed": SEED,
        "trainSampleScale": TRAIN_SAMPLE_SCALE,
        "total": len(records),
        "splits": dict(sorted(split_counts.items())),
        "languages": dict(sorted(language_counts.items())),
        "families": dict(sorted(family_counts.items())),
        "positiveIntentLabels": intent_counts,
        "labelsByLanguage": labels_by_language,
        "goldenCoverage": golden_coverage,
        "sentiments": dict(sorted(sentiment_counts.items())),
        "containsUserClipboardData": False,
        "validation": {
            "duplicateIDs": 0,
            "duplicateNormalizedTexts": 0,
            "crossSplitTextLeaks": 0,
            "sensitiveContentMatches": 0,
        },
    }


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--train-sample-scale",
        type=int,
        default=1,
        help="Multiply train records per family without changing evaluation splits.",
    )
    parser.add_argument(
        "--profile",
        choices=("baseline", "expanded"),
        default="expanded",
    )
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
    global TRAIN_SAMPLE_SCALE

    arguments = parse_arguments()
    if arguments.train_sample_scale < 1:
        raise ValueError("--train-sample-scale must be at least 1")
    TRAIN_SAMPLE_SCALE = arguments.train_sample_scale
    records = generate_records(arguments.profile)
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
