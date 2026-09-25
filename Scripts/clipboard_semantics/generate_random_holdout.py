#!/usr/bin/env python3
"""Generate a reproducible blind random-combination corpus for deployed models.

This corpus is evaluation-only. Its templates and slot vocabulary are kept
separate from generate_corpus.py and must never be added to model training.
"""

from __future__ import annotations

import argparse
import json
import random
from dataclasses import asdict, dataclass
from pathlib import Path


DEFAULT_SEED = 20260826
DEFAULT_SAMPLES_PER_FAMILY = 20


@dataclass(frozen=True)
class Labels:
    task: bool = False
    question: bool = False
    invitation: bool = False
    complaint: bool = False
    scheduleNegotiation: bool = False
    confirmationDecision: bool = False
    followUpReminder: bool = False
    sentiment: str = "neutral"
    replyable: bool = False


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
    sentiment: str
    replyable: bool


SLOTS = {
    "zh-Hans": {
        "discourse": ["", "对了，", "另外，", "补充一下，", "还有一件事，", "先说重点，", "顺便提一句，", "刚想到，", "简单说，", "单独记一下，"],
        "owner": ["设计同学", "财务", "供应商", "项目负责人", "客服团队", "运营"],
        "artifact": ["验收截图", "预算备注", "测试结论", "签字页", "交付清单", "复盘摘要"],
        "deadline": ["午休前", "明晚之前", "本周收尾时", "下次评审前", "两个工作日内", "月底前"],
        "channel": ["群里", "工单下方", "邮件线程里", "共享文档中", "项目卡片上"],
        "topic": ["费用调整", "权限开通", "排期变动", "售后范围", "资料归档", "版本上线"],
        "event": ["参加小范围评审", "吃顿便饭", "看内部演示", "碰面聊方案", "参加庆功会"],
        "time": ["周六傍晚", "明天十点半", "下周三午后", "今晚九点", "周一早会后"],
        "alternate": ["周二四点半", "周四午休后", "明早第一段时间", "周五临下班前", "下周一下午"],
        "place": ["楼下咖啡店", "三号会议室", "园区北门", "线上会议室", "客户办公室"],
        "issue": ["页面一直空白", "付款结果重复扣款", "附件始终打不开", "物流状态停了五天", "账号又被锁住"],
        "impact": ["工作完全卡住", "客户已经在催", "我无法继续操作", "交付时间被耽误", "家人收不到商品"],
        "option": ["轻量版本", "第二套报价", "供应商丙", "季度结算", "先灰度发布", "线下处理方案"],
        "trigger": ["客户回信", "补丁上线", "款项入账", "复诊结束", "合同盖章", "样品送达"],
        "person": ["客户经理", "医生", "仓库负责人", "法务", "房东", "招聘方"],
        "thing": ["最终结论", "下一步安排", "到账情况", "补充材料", "交付日期", "处理进度"],
        "update": ["我刚到酒店", "演示比预想顺利", "路上有点堵", "今天终于忙完了", "刚看到你发的照片"],
        "positive": ["这次响应非常快", "新流程顺手多了", "处理结果超出预期", "讲解特别清楚", "修复后体验很好"],
        "negative_news": ["行业指数连续回落", "昨夜航班大面积延误", "原材料价格再次上涨", "部分门店暂停营业", "天气预警已经升级"],
        "fact": ["仓库共有三层", "合同附件为 PDF", "当前版本号是 2.1", "展厅周一闭馆", "蓝色标签表示已归档"],
    },
    "en": {
        "discourse": ["", "Also, ", "One more thing: ", "For context, ", "The main point is this: ", "Just to add, ", "By the way, ", "A quick note: ", "In short, ", "For the record, "],
        "owner": ["Design", "Finance", "the vendor", "the project lead", "Support", "Operations"],
        "artifact": ["acceptance screenshots", "budget notes", "test findings", "signature page", "delivery checklist", "retro summary"],
        "deadline": ["before lunch", "by tomorrow evening", "as this week closes", "before the next review", "within two business days", "before month-end"],
        "channel": ["in the group thread", "under the ticket", "in the email chain", "inside the shared document", "on the project card"],
        "topic": ["the fee adjustment", "access activation", "the timeline change", "support coverage", "document archiving", "the release"],
        "event": ["join a small review", "have a casual dinner", "watch the internal demo", "meet to discuss the proposal", "attend the celebration"],
        "time": ["Saturday evening", "tomorrow at 10:30", "next Wednesday afternoon", "tonight at nine", "after Monday's stand-up"],
        "alternate": ["Tuesday at 4:30", "after lunch on Thursday", "first thing tomorrow", "late Friday afternoon", "next Monday afternoon"],
        "place": ["the cafe downstairs", "meeting room three", "the north campus gate", "the online room", "the client office"],
        "issue": ["the page stays blank", "the payment was charged twice", "the attachment never opens", "tracking has not moved for five days", "the account is locked again"],
        "impact": ["all work is blocked", "the client is already chasing us", "I cannot continue", "delivery is now delayed", "my family cannot receive the item"],
        "option": ["the lightweight version", "the second quote", "vendor C", "quarterly billing", "a limited rollout first", "the offline resolution"],
        "trigger": ["the client replies", "the patch ships", "the payment lands", "the checkup ends", "the contract is signed", "the sample arrives"],
        "person": ["the account manager", "the doctor", "the warehouse lead", "Legal", "the landlord", "the recruiter"],
        "thing": ["the final decision", "next steps", "payment status", "the missing documents", "the delivery date", "resolution progress"],
        "update": ["I just reached the hotel", "the demo went better than expected", "traffic is a little slow", "I finally wrapped up today", "I just saw the photo you sent"],
        "positive": ["the response was exceptionally fast", "the new flow is much easier", "the outcome exceeded expectations", "the explanation was crystal clear", "the fix feels solid"],
        "negative_news": ["the industry index fell again", "many flights were delayed overnight", "raw material prices rose again", "several stores paused operations", "the weather alert was upgraded"],
        "fact": ["the warehouse has three floors", "the contract attachment is a PDF", "the current version is 2.1", "the showroom closes on Mondays", "a blue label means archived"],
    },
}


def labels(**values: object) -> Labels:
    return Labels(**values)


FAMILIES = {
    "task_request": {
        "labels": labels(task=True, replyable=True),
        "templates": {
            "zh-Hans": [
                "{owner}还缺{artifact}，麻烦{deadline}补齐后在{channel}留言。",
            ],
            "en": [
                "{owner} still needs the {artifact}; please add it {deadline} and leave a note {channel}.",
            ],
        },
    },
    "task_next_action": {
        "labels": labels(
            task=True,
            followUpReminder=True,
            replyable=True,
        ),
        "templates": {
            "zh-Hans": [
                "下一步由你整理{artifact}，请在{deadline}交给{owner}。",
            ],
            "en": [
                "Your next action is to prepare the {artifact} {deadline} for {owner}.",
            ],
        },
    },
    "information_question": {
        "labels": labels(question=True, replyable=True),
        "templates": {
            "zh-Hans": ["想核实一下，{topic}现在由谁拍板？", "{topic}目前走到哪一步了，方便说明吗？"],
            "en": ["Quick check: who owns the final call on {topic}?", "Where does {topic} stand right now?"],
        },
    },
    "fixed_invitation": {
        "labels": labels(question=True, invitation=True, replyable=True),
        "templates": {
            "zh-Hans": ["我给你留了位置，{time}到{place}{event}，能来不？", "{time}我们在{place}{event}，要不要一起？"],
            "en": ["I saved you a spot to {event} {time} at {place}; can you make it?", "Want to {event} with us {time} at {place}?"],
        },
    },
    "complaint_support": {
        "labels": labels(question=True, complaint=True, sentiment="negative", replyable=True),
        "templates": {
            "zh-Hans": ["我已经重试三次，还是{issue}，导致{impact}。请问什么时候能处理？", "{issue}到现在没解决，{impact}，能给一个明确答复吗？"],
            "en": ["I have tried three times and {issue}; {impact}. When will this be fixed?", "{issue} is still unresolved and {impact}. Can I get a clear answer?"],
        },
    },
    "schedule_negotiation": {
        "labels": labels(question=True, scheduleNegotiation=True, replyable=True),
        "templates": {
            "zh-Hans": ["原来的时段卡住了，我只能{alternate}，能不能对调？", "{time}赶不过去，换成{alternate}你觉得可行吗？"],
            "en": ["The original slot is blocked for me; could we swap to {alternate}?", "I cannot make {time}. Would {alternate} be workable instead?"],
        },
    },
    "confirmation_decision": {
        "labels": labels(confirmationDecision=True, replyable=True),
        "templates": {
            "zh-Hans": ["不用再比较了，就选{option}，后续都按这个口径走。", "我正式确认{option}，请{deadline}启动后续安排。"],
            "en": ["No more comparisons: choose {option} and use it as the final direction.", "I formally approve {option}; start the next steps {deadline}."],
        },
    },
    "follow_up_instruction": {
        "labels": labels(
            task=True,
            followUpReminder=True,
            replyable=True,
        ),
        "templates": {
            "zh-Hans": ["等{trigger}后第二天再找{person}确认{thing}，别漏了。"],
            "en": ["Once {trigger}, check with {person} the next day about {thing}."],
        },
    },
    "follow_up_personal_reminder": {
        "labels": labels(followUpReminder=True, replyable=False),
        "templates": {
            "zh-Hans": ["个人备忘：提醒我{deadline}联系{person}，追一下{thing}。"],
            "en": ["Note to self: remind me to contact {person} {deadline} about {thing}."],
        },
    },
    "conversation": {
        "labels": labels(replyable=True),
        "templates": {
            "zh-Hans": ["跟你说一声，{update}，晚点再聊。", "{update}，突然想到你可能会想知道。"],
            "en": ["Just letting you know, {update}; we can talk later.", "{update}, and I thought you might want to know."],
        },
    },
    "acknowledgment_boundary": {
        "labels": labels(),
        "templates": {
            "zh-Hans": ["看到了，先这样，不需要回复。", "嗯，内容已收到，我只是确认一下。"],
            "en": ["Seen, that is all for now; no reply needed.", "Okay, I received it. This is only an acknowledgment."],
        },
    },
    "quoted_question_boundary": {
        "labels": labels(),
        "templates": {
            "zh-Hans": ["文档标题是“{topic}怎么办？”，这里不是在问你。", "纪要保留了“谁负责{topic}？”这句话，答案已经写在后面。"],
            "en": ["The document heading says “What about {topic}?”, but it is not asking you.", "The notes preserve the question “Who owns {topic}?”, which is answered below."],
        },
    },
    "event_boundary": {
        "labels": labels(),
        "templates": {
            "zh-Hans": ["公告只记录一件事：{event}定在{time}，地点是{place}。", "历史行程显示他们曾在{place}{event}，没有邀请任何人。"],
            "en": ["The notice only records that they will {event} {time} at {place}.", "The old itinerary says they went to {place} to {event}; nobody is being invited."],
        },
    },
    "vague_future_boundary": {
        "labels": labels(),
        "templates": {
            "zh-Hans": ["哪天有心情再找{person}聊{thing}吧。", "以后也许会看看{topic}，目前没有安排。"],
            "en": ["Maybe I will talk to {person} about {thing} someday.", "I may revisit {topic} eventually, but there is no plan."],
        },
    },
    "positive_feedback": {
        "labels": labels(sentiment="positive", replyable=True),
        "templates": {
            "zh-Hans": ["必须夸一下，{positive}，谢谢你们。", "{positive}，整个过程让人很安心。"],
            "en": ["Credit where it is due: {positive}. Thank you.", "{positive}, and the whole process felt reassuring."],
        },
    },
    "negative_news": {
        "labels": labels(sentiment="negative"),
        "templates": {
            "zh-Hans": ["新闻简报显示，{negative_news}，本文仅陈述情况。", "数据显示{negative_news}，没有提出处理诉求。"],
            "en": ["The news brief reports that {negative_news}; this is only a factual summary.", "Data shows that {negative_news}, with no request for support."],
        },
    },
    "neutral_fact": {
        "labels": labels(),
        "templates": {
            "zh-Hans": ["资料页写明：{fact}。", "当前记录只包含一个事实：{fact}。"],
            "en": ["The reference page states that {fact}.", "The current record contains one fact: {fact}."],
        },
    },
}

FRESH_FAMILIES = {
    "fresh_task_assignment": {
        "labels": labels(task=True, replyable=True),
        "templates": {
            "zh-Hans": [
                "这份交付由你收尾：把{artifact}整理好，最迟{deadline}交给{owner}。",
                "{owner}把{artifact}分给你处理，完成时间不能晚于{deadline}。",
            ],
            "en": [
                "You are closing out this deliverable: finish the {artifact} and give it to {owner} {deadline}.",
                "{owner} assigned the {artifact} to you, with completion required {deadline}.",
            ],
        },
    },
    "fresh_task_question": {
        "labels": labels(task=True, question=True, replyable=True),
        "templates": {
            "zh-Hans": [
                "{artifact}能由你在{deadline}前收尾吗？完成后告诉{owner}。",
                "这项分工你能接吗：{deadline}整理{artifact}？",
            ],
            "en": [
                "Can you close out the {artifact} {deadline} and update {owner}?",
                "Can you take this assignment and finish the {artifact} {deadline}?",
            ],
        },
    },
    "fresh_self_plan_boundary": {
        "labels": labels(),
        "templates": {
            "zh-Hans": [
                "我可能自己看看{topic}，但还没决定什么时候做。",
                "只是个人想法：以后也许整理{artifact}，目前没有安排。",
            ],
            "en": [
                "I may look into {topic} myself, but I have not decided when.",
                "This is only a personal idea: perhaps I will organize the {artifact} someday.",
            ],
        },
    },
    "fresh_complaint": {
        "labels": labels(complaint=True, sentiment="negative", replyable=True),
        "templates": {
            "zh-Hans": [
                "本来承诺今天解决，结果还是{issue}，现在{impact}。",
                "同样的故障第三次出现，{issue}，整个事情已经{impact}。",
            ],
            "en": [
                "This was promised for today, yet {issue}, and now {impact}.",
                "The same failure has happened a third time: {issue}, so {impact}.",
            ],
        },
    },
    "fresh_complaint_request": {
        "labels": labels(
            question=True,
            complaint=True,
            sentiment="negative",
            replyable=True,
        ),
        "templates": {
            "zh-Hans": [
                "{issue}已经影响到{impact}，你们准备哪天真正解决？",
                "因为{issue}，现在{impact}，能不能给出明确处理时限？",
            ],
            "en": [
                "{issue} has reached the point where {impact}. When will you actually resolve it?",
                "Because {issue}, {impact}. Can you provide a firm resolution date?",
            ],
        },
    },
    "fresh_negative_report_boundary": {
        "labels": labels(sentiment="negative"),
        "templates": {
            "zh-Hans": [
                "行业通报称{negative_news}，这里只摘录公开信息。",
                "统计报告记录了{negative_news}，没有客户投诉。",
            ],
            "en": [
                "The industry bulletin says that {negative_news}; this only quotes public information.",
                "The statistical report records that {negative_news}, with no customer complaint.",
            ],
        },
    },
    "fresh_confirmation": {
        "labels": labels(confirmationDecision=True, replyable=True),
        "templates": {
            "zh-Hans": [
                "评审结束，我的最终选择是{option}，其他方案关闭。",
                "结论正式生效：{topic}采用{option}。",
            ],
            "en": [
                "The review is over; my final selection is {option}, and the alternatives are closed.",
                "The decision is now official: use {option} for {topic}.",
            ],
        },
    },
    "fresh_pending_boundary": {
        "labels": labels(),
        "templates": {
            "zh-Hans": [
                "我看过{option}了，但还没有选择，等明天再决定。",
                "{topic}仍在评审，当前没有批准结论。",
            ],
            "en": [
                "I reviewed {option}, but have not selected it; the decision waits until tomorrow.",
                "{topic} remains under review, with no approval yet.",
            ],
        },
    },
    "fresh_follow_up": {
        "labels": labels(
            task=True,
            followUpReminder=True,
            replyable=True,
        ),
        "templates": {
            "zh-Hans": [
                "等{trigger}满两天后，再找{person}核实{thing}并记录结果。",
                "当前事项结束以后，回头联系{person}追踪{thing}。",
            ],
            "en": [
                "Two days after {trigger}, check with {person} again about {thing} and record the outcome.",
                "After the current item closes, return to {person} and track {thing}.",
            ],
        },
    },
    "fresh_personal_reminder": {
        "labels": labels(followUpReminder=True),
        "templates": {
            "zh-Hans": [
                "给自己设一条后续提醒：{deadline}找{person}确认{thing}。",
                "个人行动项：{trigger}以后再次检查{thing}。",
            ],
            "en": [
                "Set myself a follow-up reminder to ask {person} about {thing} {deadline}.",
                "Personal action item: check {thing} again after {trigger}.",
            ],
        },
    },
    "fresh_plain_task_boundary": {
        "labels": labels(task=True, replyable=True),
        "templates": {
            "zh-Hans": [
                "现在请直接整理{artifact}并发给{owner}，不需要后续回访。",
                "一次性完成{artifact}即可，交给{owner}后任务结束。",
            ],
            "en": [
                "Prepare the {artifact} now and send it to {owner}; no later follow-up is needed.",
                "Complete the {artifact} once, deliver it to {owner}, and close the task.",
            ],
        },
    },
    "fresh_vague_follow_boundary": {
        "labels": labels(),
        "templates": {
            "zh-Hans": [
                "以后说不定会再问{person}，目前没有后续计划。",
                "{thing}哪天想起来再看，现在不用提醒。",
            ],
            "en": [
                "I might ask {person} again someday, but there is no follow-up plan.",
                "Maybe I will revisit {thing} whenever it comes to mind; no reminder is needed.",
            ],
        },
    },
}

TARGETED_FINAL_FAMILIES = {
    "final_task_direct": {
        "labels": labels(task=True, replyable=True),
        "templates": {
            "zh-Hans": [
                "{artifact}现在明确由你负责，{deadline}前交给{owner}。",
                "请你承担{artifact}的交付，完成后在{channel}确认。",
            ],
            "en": [
                "Ownership of the {artifact} now belongs to you; deliver it to {owner} {deadline}.",
                "You are responsible for delivering the {artifact}; confirm completion {channel}.",
            ],
        },
    },
    "final_task_indirect": {
        "labels": labels(task=True, replyable=True),
        "templates": {
            "zh-Hans": [
                "{owner}希望你能接下{artifact}，并在{deadline}前收尾。",
                "这件事想交给你继续推进：整理{artifact}。",
            ],
            "en": [
                "{owner} is counting on you to pick up the {artifact} and close it out {deadline}.",
                "We would like you to carry this forward by preparing the {artifact}.",
            ],
        },
    },
    "final_task_question": {
        "labels": labels(task=True, question=True, replyable=True),
        "templates": {
            "zh-Hans": [
                "能请你负责{artifact}并在{deadline}前完成吗？",
                "{artifact}接下来可以由你收尾吗？",
            ],
            "en": [
                "Would you be able to own the {artifact} and finish it {deadline}?",
                "Could the {artifact} be left with you for final completion?",
            ],
        },
    },
    "final_personal_action_boundary": {
        "labels": labels(followUpReminder=True),
        "templates": {
            "zh-Hans": [
                "这是我自己的行动清单：{trigger}后检查{thing}。",
                "个人记录，不是委派：{deadline}找{person}确认{thing}。",
            ],
            "en": [
                "This is on my own action list: check {thing} after {trigger}.",
                "Personal note, not delegated work: ask {person} about {thing} {deadline}.",
            ],
        },
    },
    "final_self_intent_boundary": {
        "labels": labels(),
        "templates": {
            "zh-Hans": [
                "我自己可能会整理{artifact}，但还没有正式计划。",
                "以后有空我再看{topic}，目前不用安排。",
            ],
            "en": [
                "I may organize the {artifact} myself, but there is no firm plan.",
                "I might look at {topic} when I have time; nothing is scheduled.",
            ],
        },
    },
    "final_event_boundary": {
        "labels": labels(),
        "templates": {
            "zh-Hans": [
                "{owner}在{deadline}举行评审，这只是日程通知。",
                "{topic}会议已经定在{deadline}，没有分配任务。",
            ],
            "en": [
                "{owner} is holding a review {deadline}; this is only a calendar notice.",
                "The meeting about {topic} is set for {deadline}, with no assignment.",
            ],
        },
    },
    "final_complaint_implicit": {
        "labels": labels(complaint=True, sentiment="negative", replyable=True),
        "templates": {
            "zh-Hans": [
                "我不应该为同一个问题反复追问，{issue}，现在{impact}。",
                "又是同样的结果：{issue}，已经连续影响到{impact}。",
            ],
            "en": [
                "I should not have to chase the same issue repeatedly: {issue}, and now {impact}.",
                "It is the same outcome again: {issue}, repeatedly leaving me with {impact}.",
            ],
        },
    },
    "final_complaint_short": {
        "labels": labels(complaint=True, sentiment="negative", replyable=True),
        "templates": {
            "zh-Hans": [
                "{issue}，已经第三次了。",
                "等了这么久还是{issue}，实在无法接受。",
            ],
            "en": [
                "{issue}. This is already the third time.",
                "After all this waiting, {issue}; this is not acceptable.",
            ],
        },
    },
    "final_complaint_request": {
        "labels": labels(
            question=True,
            complaint=True,
            sentiment="negative",
            replyable=True,
        ),
        "templates": {
            "zh-Hans": [
                "{issue}一直没有变化，什么时候才能真正处理？",
                "因为{issue}，现在{impact}，谁能给出解决结果？",
            ],
            "en": [
                "Nothing has changed with this problem: {issue}. When will it actually be handled?",
                "Because {issue}, {impact}. Who can provide a real resolution?",
            ],
        },
    },
    "final_negative_fact_boundary": {
        "labels": labels(sentiment="negative"),
        "templates": {
            "zh-Hans": [
                "公开报告显示{negative_news}，这里没有服务申诉。",
                "资料仅记录{negative_news}，不涉及个人问题。",
            ],
            "en": [
                "The public report shows that {negative_news}; there is no service grievance here.",
                "The document only records that {negative_news}, not an individual problem.",
            ],
        },
    },
    "final_resolved_boundary": {
        "labels": labels(),
        "templates": {
            "zh-Hans": [
                "之前的{issue}已经彻底恢复，这是一条结案记录。",
                "{topic}的问题处理完毕，现在不需要任何支持。",
            ],
            "en": [
                "The earlier issue where {issue} is fully resolved; this is a closure record.",
                "The problem involving {topic} is complete, with no support needed now.",
            ],
        },
    },
    "final_operational_task_boundary": {
        "labels": labels(task=True, replyable=True),
        "templates": {
            "zh-Hans": [
                "请完成{artifact}后直接结项，不需要投诉或后续回访。",
                "{deadline}前把{artifact}交给{owner}，随后流程关闭。",
            ],
            "en": [
                "Complete the {artifact} and close the item; no complaint or later follow-up is involved.",
                "Deliver the {artifact} to {owner} {deadline}, then close the workflow.",
            ],
        },
    },
}

TARGETED_CONFIRMATION_FAMILIES = {
    "confirmation_task_assignment": {
        "labels": labels(task=True, replyable=True),
        "templates": {
            "zh-Hans": [
                "请你把{artifact}负责到底，并在{deadline}向{owner}交付。",
                "{artifact}接下来归你处理，完成后在{channel}更新状态。",
            ],
            "en": [
                "Please see the {artifact} through and deliver it to {owner} {deadline}.",
                "The {artifact} is yours to handle next; update the status {channel} when complete.",
            ],
        },
    },
    "confirmation_task_request": {
        "labels": labels(task=True, question=True, replyable=True),
        "templates": {
            "zh-Hans": [
                "可以请你接管{artifact}并在{deadline}前处理好吗？",
                "你愿意负责{artifact}的最后交付吗？",
            ],
            "en": [
                "Could I ask you to take care of the {artifact} {deadline}?",
                "Would you own the final delivery of the {artifact}?",
            ],
        },
    },
    "confirmation_operational_task": {
        "labels": labels(task=True, replyable=True),
        "templates": {
            "zh-Hans": [
                "把{artifact}交给{owner}后直接关闭事项，不安排回访。",
                "当前只需要完成{artifact}，没有投诉处理。",
            ],
            "en": [
                "Close the item after sending the {artifact} to {owner}; do not schedule a follow-up.",
                "The only requirement is to complete the {artifact}; no grievance handling is involved.",
            ],
        },
    },
    "confirmation_personal_boundary": {
        "labels": labels(followUpReminder=True),
        "templates": {
            "zh-Hans": [
                "我自己的行动备忘：{trigger}后查看{thing}。",
                "仅记录个人计划，{deadline}联系{person}。",
            ],
            "en": [
                "My private action note is to review {thing} after {trigger}.",
                "This only records my personal plan to contact {person} {deadline}.",
            ],
        },
    },
    "confirmation_self_plan_boundary": {
        "labels": labels(),
        "templates": {
            "zh-Hans": [
                "我也许会自己整理{artifact}，目前没有确定安排。",
                "{topic}以后再考虑，现在谁都不用处理。",
            ],
            "en": [
                "I may prepare the {artifact} myself, but nothing is arranged.",
                "{topic} can be considered later; nobody needs to handle it now.",
            ],
        },
    },
    "confirmation_complaint_implicit": {
        "labels": labels(complaint=True, sentiment="negative", replyable=True),
        "templates": {
            "zh-Hans": [
                "我到现在还在面对{issue}，而且{impact}。",
                "处理承诺没有兑现，结果仍然是{issue}。",
            ],
            "en": [
                "I am still dealing with the fact that {issue}, and {impact}.",
                "The promised fix never materialized; the result is still that {issue}.",
            ],
        },
    },
    "confirmation_complaint_request": {
        "labels": labels(
            question=True,
            complaint=True,
            sentiment="negative",
            replyable=True,
        ),
        "templates": {
            "zh-Hans": [
                "{issue}已经持续很久，究竟什么时候恢复？",
                "现在因为{issue}而{impact}，谁来负责处理？",
            ],
            "en": [
                "This has continued for far too long: {issue}. When will it be restored?",
                "Because {issue}, {impact}. Who is responsible for fixing it?",
            ],
        },
    },
    "confirmation_complaint_short": {
        "labels": labels(complaint=True, sentiment="negative", replyable=True),
        "templates": {
            "zh-Hans": [
                "还是{issue}，完全没有改善。",
                "{issue}又来了，不能一直这样。",
            ],
            "en": [
                "It is still the case that {issue}, with no improvement.",
                "The problem is back again: {issue}. This cannot keep happening.",
            ],
        },
    },
    "confirmation_negative_fact": {
        "labels": labels(sentiment="negative"),
        "templates": {
            "zh-Hans": [
                "研究资料指出{negative_news}，这不是客户反馈。",
                "行业统计记录了{negative_news}，没有服务诉求。",
            ],
            "en": [
                "The research notes that {negative_news}; this is not customer feedback.",
                "Industry statistics record that {negative_news}, with no service request.",
            ],
        },
    },
    "confirmation_resolved_boundary": {
        "labels": labels(),
        "templates": {
            "zh-Hans": [
                "{issue}已经恢复，{owner}确认事项关闭。",
                "{topic}当前运行正常，不需要补救。",
            ],
            "en": [
                "The earlier state where {issue} is resolved, and {owner} confirmed closure.",
                "{topic} is operating normally now, with no remedy needed.",
            ],
        },
    },
}

TARGETED_RELEASE_FAMILIES = {
    "release_task_owner": {
        "labels": labels(task=True, replyable=True),
        "templates": {
            "zh-Hans": [
                "{artifact}的负责人就是你，请在{deadline}完成交付。",
                "接下来请你推进{artifact}，并向{owner}汇报结果。",
            ],
            "en": [
                "You are the owner of the {artifact}; complete delivery {deadline}.",
                "Please move the {artifact} forward and report the outcome to {owner}.",
            ],
        },
    },
    "release_task_polite_request": {
        "labels": labels(task=True, question=True, replyable=True),
        "templates": {
            "zh-Hans": [
                "能麻烦你把{artifact}负责到交付完成吗？",
                "你可以在{deadline}前处理好{artifact}吗？",
            ],
            "en": [
                "May I ask you to own the {artifact} through delivery?",
                "Can you have the {artifact} completed {deadline}?",
            ],
        },
    },
    "release_personal_boundary": {
        "labels": labels(followUpReminder=True),
        "templates": {
            "zh-Hans": [
                "这是我的私人待办：{trigger}之后确认{thing}。",
                "个人备忘，不交给任何人：{deadline}联系{person}。",
            ],
            "en": [
                "This is my private todo: confirm {thing} after {trigger}.",
                "Personal reminder, assigned to nobody else: contact {person} {deadline}.",
            ],
        },
    },
    "release_complaint_unspoken": {
        "labels": labels(complaint=True, sentiment="negative", replyable=True),
        "templates": {
            "zh-Hans": [
                "从上次反馈以后仍然{issue}，现在已经{impact}。",
                "说好的处理没有发生，我看到的还是{issue}。",
            ],
            "en": [
                "Since my last report, {issue}, and it has now reached the point where {impact}.",
                "The promised handling did not happen; I am still seeing that {issue}.",
            ],
        },
    },
    "release_complaint_question": {
        "labels": labels(
            question=True,
            complaint=True,
            sentiment="negative",
            replyable=True,
        ),
        "templates": {
            "zh-Hans": [
                "{issue}到现在都没处理，什么时候能恢复正常？",
                "目前因为{issue}而{impact}，可以给个处理结果吗？",
            ],
            "en": [
                "The problem where {issue} has not been addressed. When will normal service return?",
                "At the moment, {issue}, so {impact}. Can I get an actual resolution?",
            ],
        },
    },
    "release_complaint_brief": {
        "labels": labels(complaint=True, sentiment="negative", replyable=True),
        "templates": {
            "zh-Hans": [
                "{issue}，到现在还是老样子。",
                "又一次{issue}，这已经影响正常使用。",
            ],
            "en": [
                "{issue}, and nothing has changed.",
                "Once again, {issue}; normal use is now affected.",
            ],
        },
    },
    "release_negative_boundary": {
        "labels": labels(sentiment="negative"),
        "templates": {
            "zh-Hans": [
                "分析报告提到{negative_news}，不代表用户投诉。",
                "公开数据包含{negative_news}，这里只做事实引用。",
            ],
            "en": [
                "The analysis mentions that {negative_news}; it does not represent a user complaint.",
                "Public data includes the fact that {negative_news}; this is only a factual citation.",
            ],
        },
    },
    "release_resolved_boundary": {
        "labels": labels(),
        "templates": {
            "zh-Hans": [
                "{issue}的问题已经结束，目前状态稳定。",
                "{topic}已确认恢复，{owner}不需要继续介入。",
            ],
            "en": [
                "The earlier problem where {issue} is over, and the current state is stable.",
                "{topic} is confirmed restored, so {owner} does not need to intervene.",
            ],
        },
    },
}


def render(template: str, slots: dict[str, list[str]], rng: random.Random) -> str:
    values = {key: rng.choice(options) for key, options in slots.items()}
    return values["discourse"] + template.format(**values)


def generate(
    seed: int,
    samples_per_family: int,
    families: dict[str, dict[str, object]],
) -> list[Record]:
    rng = random.Random(seed)
    records: list[Record] = []
    seen: set[str] = set()

    for language in ("zh-Hans", "en"):
        slots = SLOTS[language]
        for family, configuration in families.items():
            family_labels: Labels = configuration["labels"]
            templates: list[str] = configuration["templates"][language]
            generated = 0
            attempts = 0
            while generated < samples_per_family:
                attempts += 1
                if attempts > samples_per_family * 200:
                    raise RuntimeError(f"Unable to generate unique samples for {language}/{family}")
                text = render(rng.choice(templates), slots, rng)
                normalized = " ".join(text.casefold().split())
                if normalized in seen:
                    continue
                seen.add(normalized)
                record_id = f"random-{seed}-{language}-{family}-{generated + 1:03d}"
                records.append(
                    Record(
                        id=record_id,
                        text=text,
                        language=language,
                        split="randomHoldout",
                        family=family,
                        **asdict(family_labels),
                    )
                )
                generated += 1

    rng.shuffle(records)
    return records


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--seed", type=int, default=DEFAULT_SEED)
    parser.add_argument("--samples-per-family", type=int, default=DEFAULT_SAMPLES_PER_FAMILY)
    parser.add_argument(
        "--profile",
        choices=(
            "development",
            "fresh",
            "targeted-final",
            "targeted-confirmation",
            "targeted-release",
        ),
        default="development",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=None,
    )
    arguments = parser.parse_args()

    profiles = {
        "development": FAMILIES,
        "fresh": FRESH_FAMILIES,
        "targeted-final": TARGETED_FINAL_FAMILIES,
        "targeted-confirmation": TARGETED_CONFIRMATION_FAMILIES,
        "targeted-release": TARGETED_RELEASE_FAMILIES,
    }
    families = profiles[arguments.profile]
    default_outputs = {
        "development": "random-holdout-corpus.jsonl",
        "fresh": "fresh-metric-holdout-corpus.jsonl",
        "targeted-final": "targeted-final-holdout-corpus.jsonl",
        "targeted-confirmation": "targeted-confirmation-holdout-corpus.jsonl",
        "targeted-release": "targeted-release-holdout-corpus.jsonl",
    }
    output_path = arguments.output or Path(
        "ModelTraining/ClipboardSemantics/" + default_outputs[arguments.profile]
    )
    records = generate(arguments.seed, arguments.samples_per_family, families)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with output_path.open("w", encoding="utf-8") as output:
        for record in records:
            output.write(json.dumps(asdict(record), ensure_ascii=False, sort_keys=True) + "\n")

    print(
        f"RANDOM_HOLDOUT_DONE records={len(records)} "
        f"families={len(families)} profile={arguments.profile} "
        f"seed={arguments.seed} output={output_path}"
    )


if __name__ == "__main__":
    main()
