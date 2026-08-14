#!/usr/bin/env python3
"""Build the companion Shortcut for the Extract Events skill.

Writes an unsigned binary plist that `shortcuts sign` can notarize.

Workflow (must materialize Shortcut Input as Text first — Split Text's
WFInput/ExtensionInput binding finishes the run without iterating):

  Text (Shortcut Input)
    → Split Text (new lines)
    → Repeat Each
    → Split Text (|)
    → Get items 1–4 (start, end, title, location)
    → If end == ALLDAY
        → Add New Event (all-day)
      Otherwise
        → Add New Event (timed)
"""

from __future__ import annotations

import plistlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = ROOT / "OSGKeyboard" / "Resources" / "Shortcuts"
UNSIGNED = OUT_DIR / "OSGExtractEvents.unsigned.shortcut"
SIGNED = OUT_DIR / "OSGExtractEvents.shortcut"
SHORTCUT_NAME = "OSGExtractEvents"

OBJECT_REPLACEMENT = "\ufffc"

TEXT_UUID = "A1B2C3D0-1111-4E00-8A5A-FD7E1B0C396F"
SPLIT_LINES_UUID = "A1B2C3D1-2222-4F11-9A6B-0E8F2C1D4A70"
REPEAT_GROUP = "A1B2C3D2-3333-4E02-B3C4-91F0E6A7B812"
REPEAT_START = "A1B2C3D3-4444-4F13-A4D5-02A1F7B8C923"
SPLIT_FIELDS_UUID = "A1B2C3D4-5555-4014-B5E6-13B2A8C9D034"
START_UUID = "A1B2C3D5-6666-4125-C6F7-24C3B9DAE145"
END_UUID = "A1B2C3D6-7777-4236-D7A8-35D4CAEBF256"
TITLE_UUID = "A1B2C3D7-8888-4347-E8B9-46E5DBF0C367"
LOCATION_UUID = "A1B2C3D8-9999-4458-F9CA-57F6EC01D478"
IF_GROUP = "A1B2C3D9-AAAA-4569-0ADB-6807FD12E589"
IF_START = "A1B2C3DA-BBBB-467A-1BEC-79180E23F69A"
EVENT_ALLDAY_UUID = "A1B2C3DB-CCCC-478B-2CFD-8A291F3407AB"
IF_ELSE = "A1B2C3DC-DDDD-489C-3D0E-9B3A204518BC"
EVENT_TIMED_UUID = "A1B2C3DD-EEEE-49AD-4E1F-AC4B315629CD"
IF_END = "A1B2C3DE-FFFF-4ABE-5F20-BD5C42673ADE"
REPEAT_END = "A1B2C3DF-0000-4BCF-6031-CE6D53784BEF"


def attachment(value: dict) -> dict:
    return {"Value": value, "WFSerializationType": "WFTextTokenAttachment"}


def token_string(attachment_value: dict) -> dict:
    return {
        "Value": {
            "attachmentsByRange": {"{0, 1}": attachment_value},
            "string": OBJECT_REPLACEMENT,
        },
        "WFSerializationType": "WFTextTokenString",
    }


def shortcut_input_text() -> dict:
    return token_string({"Type": "ExtensionInput"})


def action_output_text(output_name: str, output_uuid: str) -> dict:
    return token_string(
        {
            "Aggrandizements": [],
            "OutputName": output_name,
            "OutputUUID": output_uuid,
            "Type": "ActionOutput",
        }
    )


def action_output_attachment(output_name: str, output_uuid: str) -> dict:
    return attachment(
        {
            "Aggrandizements": [],
            "OutputName": output_name,
            "OutputUUID": output_uuid,
            "Type": "ActionOutput",
        }
    )


def named_variable_text(variable_name: str) -> dict:
    return token_string(
        {
            "Aggrandizements": [],
            "Type": "Variable",
            "VariableName": variable_name,
        }
    )


def if_input(output_name: str, output_uuid: str) -> dict:
    return {
        "Type": "Variable",
        "Variable": {
            "Value": {
                "Aggrandizements": [],
                "OutputName": output_name,
                "OutputUUID": output_uuid,
                "Type": "ActionOutput",
            },
            "WFSerializationType": "WFTextTokenAttachment",
        },
    }


def get_item(uuid: str, name: str, index: int) -> dict:
    return {
        "WFWorkflowActionIdentifier": "is.workflow.actions.getitemfromlist",
        "WFWorkflowActionParameters": {
            "UUID": uuid,
            "CustomOutputName": name,
            "WFInput": action_output_attachment("字段", SPLIT_FIELDS_UUID),
            "WFItemSpecifier": "Item At Index",
            "WFItemIndex": index,
        },
    }


def add_event(
    uuid: str,
    *,
    all_day: bool,
    include_end: bool,
) -> dict:
    parameters = {
        "UUID": uuid,
        "WFCalendarItemTitle": action_output_text("标题", TITLE_UUID),
        "WFCalendarItemLocation": action_output_text("地点", LOCATION_UUID),
        "WFCalendarItemDates": True,
        "WFCalendarItemStartDate": action_output_text("开始", START_UUID),
        "WFCalendarItemAllDay": all_day,
        "WFCalendarItemShowComposer": False,
        "ShowComposeSheet": False,
        "WFShowWhenRun": False,
    }
    if include_end:
        parameters["WFCalendarItemEndDate"] = action_output_text("结束", END_UUID)
    return {
        "WFWorkflowActionIdentifier": "is.workflow.actions.addnewevent",
        "WFWorkflowActionParameters": parameters,
    }


def workflow() -> dict:
    return {
        "WFWorkflowClientVersion": "3600.0.4",
        "WFWorkflowClientRelease": "26.0",
        "WFWorkflowMinimumClientVersion": 900,
        "WFWorkflowMinimumClientVersionString": "900",
        "WFWorkflowName": SHORTCUT_NAME,
        "WFWorkflowHasShortcutInputVariables": True,
        "WFWorkflowHasOutputFallback": False,
        "WFWorkflowImportQuestions": [],
        "WFWorkflowTypes": [],
        "WFWorkflowInputContentItemClasses": [
            "WFStringContentItem",
            "WFRichTextContentItem",
        ],
        "WFWorkflowOutputContentItemClasses": [],
        "WFWorkflowNoInputBehavior": {
            "Name": "WFWorkflowNoInputBehaviorAskForInput",
            "Parameters": {
                "ItemClass": "WFStringContentItem",
            },
        },
        "WFWorkflowIcon": {
            "WFWorkflowIconGlyphNumber": 59675,
            "WFWorkflowIconStartColor": 4286828031,
        },
        "WFWorkflowActions": [
            {
                "WFWorkflowActionIdentifier": "is.workflow.actions.gettext",
                "WFWorkflowActionParameters": {
                    "UUID": TEXT_UUID,
                    "CustomOutputName": "快捷指令文本",
                    "WFTextActionText": shortcut_input_text(),
                },
            },
            {
                "WFWorkflowActionIdentifier": "is.workflow.actions.text.split",
                "WFWorkflowActionParameters": {
                    "UUID": SPLIT_LINES_UUID,
                    "CustomOutputName": "行",
                    "text": action_output_text("快捷指令文本", TEXT_UUID),
                    "WFTextSeparator": "New Lines",
                },
            },
            {
                "WFWorkflowActionIdentifier": "is.workflow.actions.repeat.each",
                "WFWorkflowActionParameters": {
                    "UUID": REPEAT_START,
                    "GroupingIdentifier": REPEAT_GROUP,
                    "WFControlFlowMode": 0,
                    "WFInput": action_output_attachment("行", SPLIT_LINES_UUID),
                },
            },
            {
                "WFWorkflowActionIdentifier": "is.workflow.actions.text.split",
                "WFWorkflowActionParameters": {
                    "UUID": SPLIT_FIELDS_UUID,
                    "CustomOutputName": "字段",
                    "text": named_variable_text("Repeat Item"),
                    "WFTextSeparator": "Custom",
                    "WFTextCustomSeparator": "|",
                },
            },
            get_item(START_UUID, "开始", 1),
            get_item(END_UUID, "结束", 2),
            get_item(TITLE_UUID, "标题", 3),
            get_item(LOCATION_UUID, "地点", 4),
            {
                "WFWorkflowActionIdentifier": "is.workflow.actions.conditional",
                "WFWorkflowActionParameters": {
                    "UUID": IF_START,
                    "GroupingIdentifier": IF_GROUP,
                    "WFControlFlowMode": 0,
                    "WFCondition": 4,
                    "WFConditionalActionString": "ALLDAY",
                    "WFInput": if_input("结束", END_UUID),
                },
            },
            add_event(EVENT_ALLDAY_UUID, all_day=True, include_end=False),
            {
                "WFWorkflowActionIdentifier": "is.workflow.actions.conditional",
                "WFWorkflowActionParameters": {
                    "UUID": IF_ELSE,
                    "GroupingIdentifier": IF_GROUP,
                    "WFControlFlowMode": 1,
                },
            },
            add_event(EVENT_TIMED_UUID, all_day=False, include_end=True),
            {
                "WFWorkflowActionIdentifier": "is.workflow.actions.conditional",
                "WFWorkflowActionParameters": {
                    "UUID": IF_END,
                    "GroupingIdentifier": IF_GROUP,
                    "WFControlFlowMode": 2,
                },
            },
            {
                "WFWorkflowActionIdentifier": "is.workflow.actions.repeat.each",
                "WFWorkflowActionParameters": {
                    "UUID": REPEAT_END,
                    "GroupingIdentifier": REPEAT_GROUP,
                    "WFControlFlowMode": 2,
                },
            },
        ],
    }


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    UNSIGNED.write_bytes(plistlib.dumps(workflow(), fmt=plistlib.FMT_BINARY))
    print(f"wrote {UNSIGNED}")
    print(
        "sign with: shortcuts sign --mode anyone "
        f"--input {UNSIGNED} --output {SIGNED}"
    )


if __name__ == "__main__":
    main()
