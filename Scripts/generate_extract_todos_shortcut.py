#!/usr/bin/env python3
"""Build the companion Shortcut for the Extract Tasks skill.

Writes an unsigned binary plist that `shortcuts sign` can notarize.

Workflow (must materialize Shortcut Input as Text first — Split Text's
WFInput/ExtensionInput binding finishes the run without iterating):

  Text (Shortcut Input)
    → Split Text (new lines)
    → Repeat Each
    → Add New Reminder (title = Repeat Item, default list, no composer)
"""

from __future__ import annotations

import plistlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = ROOT / "OSGKeyboard" / "Resources" / "Shortcuts"
UNSIGNED = OUT_DIR / "OSGExtractTodos.unsigned.shortcut"
SIGNED = OUT_DIR / "OSGExtractTodos.shortcut"

OBJECT_REPLACEMENT = "\ufffc"

TEXT_UUID = "6A2D0A80-3B1C-4E00-8A5A-FD7E1B0C396F"
SPLIT_UUID = "7A3E1B90-4C2D-4F11-9A6B-0E8F2C1D4A70"
REPEAT_GROUP = "2B9C8D11-55AA-4E02-B3C4-91F0E6A7B812"
REPEAT_START = "3C0D9E22-66BB-4F13-A4D5-02A1F7B8C923"
REMINDER_UUID = "4D1E0F33-77CC-4014-B5E6-13B2A8C9D034"
REPEAT_END = "5E2F1044-88DD-4125-C6F7-24C3B9DAE145"


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


def named_variable_text(variable_name: str) -> dict:
    return token_string(
        {
            "Aggrandizements": [],
            "Type": "Variable",
            "VariableName": variable_name,
        }
    )


def workflow() -> dict:
    return {
        "WFWorkflowClientVersion": "3600.0.4",
        "WFWorkflowClientRelease": "26.0",
        "WFWorkflowMinimumClientVersion": 900,
        "WFWorkflowMinimumClientVersionString": "900",
        "WFWorkflowName": "OSG · 提取待办",
        "WFWorkflowHasShortcutInputVariables": True,
        "WFWorkflowHasOutputFallback": False,
        "WFWorkflowImportQuestions": [],
        # Empty types: a normal library shortcut. QuickActions/ActionExtension
        # made `run-shortcut?name=` open Shortcuts without running it.
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
            "WFWorkflowIconGlyphNumber": 59511,
            "WFWorkflowIconStartColor": 2071128575,
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
                    "UUID": SPLIT_UUID,
                    # Split Text reads `text`, not `WFInput`.
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
                    "WFInput": attachment(
                        {
                            "Aggrandizements": [],
                            "OutputName": "Split Text",
                            "OutputUUID": SPLIT_UUID,
                            "Type": "ActionOutput",
                        }
                    ),
                },
            },
            {
                "WFWorkflowActionIdentifier": "is.workflow.actions.addnewreminder",
                "WFWorkflowActionParameters": {
                    "UUID": REMINDER_UUID,
                    "WFCalendarItemTitle": named_variable_text("Repeat Item"),
                    "WFCalendarItemShowComposer": False,
                    "ShowComposeSheet": False,
                    "WFShowWhenRun": False,
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
