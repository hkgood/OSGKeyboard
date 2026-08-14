#!/usr/bin/env python3
"""Build the companion Shortcut for the Save to Notes skill.

Writes an unsigned binary plist that `shortcuts sign` can notarize.

On iPhone, `com.apple.mobilenotes.SharingExtension` binds note content through
`WFCreateNoteInput`. The similarly named `contents` App Intent parameter is
ignored by this legacy action and leaves an unresolved Content placeholder.

  Text (Shortcut Input)
    → Split Text (`||OSG_NOTE||`)
    → Get item 1 (title) and item 2 (body)
    → Text (title + blank line + body)
    → Create Note (WFCreateNoteInput = Text output, silent)
"""

from __future__ import annotations

import plistlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = ROOT / "OSGKeyboard" / "Resources" / "Shortcuts"
UNSIGNED = OUT_DIR / "OSGSaveToNotes.unsigned.shortcut"
SIGNED = OUT_DIR / "OSGSaveToNotes.shortcut"

OBJECT_REPLACEMENT = "\ufffc"
FIELD_SEPARATOR = "||OSG_NOTE||"

TEXT_UUID = "B2C3D4E0-1111-4E00-8A5A-FD7E1B0C396F"
SPLIT_UUID = "B2C3D4E2-3333-4F11-9A6B-0E8F2C1D4A70"
TITLE_UUID = "B2C3D4E3-4444-4014-B5E6-13B2A8C9D034"
BODY_UUID = "B2C3D4E4-5555-4125-C6F7-24C3B9DAE145"
NOTE_TEXT_UUID = "B2C3D4E5-6666-4236-D7A8-35D4CAEBF256"
NOTE_UUID = "B2C3D4E1-2222-4F11-9A6B-0E8F2C1D4A70"


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
    return {
        "Value": {
            "Aggrandizements": [],
            "OutputName": output_name,
            "OutputUUID": output_uuid,
            "Type": "ActionOutput",
        },
        "WFSerializationType": "WFTextTokenAttachment",
    }


def get_item(uuid: str, name: str, index: int) -> dict:
    return {
        "WFWorkflowActionIdentifier": "is.workflow.actions.getitemfromlist",
        "WFWorkflowActionParameters": {
            "UUID": uuid,
            "CustomOutputName": name,
            "WFInput": action_output_attachment("字段", SPLIT_UUID),
            "WFItemSpecifier": "Item At Index",
            "WFItemIndex": index,
        },
    }


def note_text() -> dict:
    return {
        "Value": {
            "attachmentsByRange": {
                "{0, 1}": {
                    "Aggrandizements": [],
                    "OutputName": "标题",
                    "OutputUUID": TITLE_UUID,
                    "Type": "ActionOutput",
                },
                "{3, 1}": {
                    "Aggrandizements": [],
                    "OutputName": "正文",
                    "OutputUUID": BODY_UUID,
                    "Type": "ActionOutput",
                },
            },
            "string": f"{OBJECT_REPLACEMENT}\n\n{OBJECT_REPLACEMENT}",
        },
        "WFSerializationType": "WFTextTokenString",
    }


def create_note_action() -> dict:
    # The Create Note editor must show the `备忘录文本` magic-variable pill.
    # A generic `内容` placeholder means this key or value was not recognized.
    return {
        "WFWorkflowActionIdentifier": "com.apple.mobilenotes.SharingExtension",
        "WFWorkflowActionParameters": {
            "UUID": NOTE_UUID,
            "CustomOutputName": "备忘录",
            "IntentAppIdentifier": "com.apple.mobilenotes",
            "WFCreateNoteInput": action_output_text("备忘录文本", NOTE_TEXT_UUID),
            "ShowWhenRun": False,
            "WFShowWhenRun": False,
        },
    }


def workflow() -> dict:
    return {
        "WFWorkflowClientVersion": "3600.0.4",
        "WFWorkflowClientRelease": "26.0",
        "WFWorkflowMinimumClientVersion": 900,
        "WFWorkflowMinimumClientVersionString": "900",
        "WFWorkflowName": "OSGSaveToNotes",
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
            "WFWorkflowIconGlyphNumber": 61440,
            "WFWorkflowIconStartColor": 2555137535,
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
                    "CustomOutputName": "字段",
                    "text": action_output_text("快捷指令文本", TEXT_UUID),
                    "WFTextSeparator": "Custom",
                    "WFTextCustomSeparator": FIELD_SEPARATOR,
                },
            },
            get_item(TITLE_UUID, "标题", 1),
            get_item(BODY_UUID, "正文", 2),
            {
                "WFWorkflowActionIdentifier": "is.workflow.actions.gettext",
                "WFWorkflowActionParameters": {
                    "UUID": NOTE_TEXT_UUID,
                    "CustomOutputName": "备忘录文本",
                    "WFTextActionText": note_text(),
                },
            },
            create_note_action(),
        ],
    }


def validate(data: dict) -> None:
    """Reject bindings that make Create Note prompt for missing content."""
    actions = data["WFWorkflowActions"]
    create_note = actions[-1]
    parameters = create_note["WFWorkflowActionParameters"]
    note_input = parameters.get("WFCreateNoteInput")
    if create_note["WFWorkflowActionIdentifier"] != "com.apple.mobilenotes.SharingExtension":
        raise ValueError("last action must be Create Note")
    if "contents" in parameters or not note_input:
        raise ValueError("Create Note must use WFCreateNoteInput, not contents")
    if note_input.get("WFSerializationType") != "WFTextTokenString":
        raise ValueError("WFCreateNoteInput must be a Text magic-variable token")
    attachments = note_input["Value"]["attachmentsByRange"].values()
    if not any(item.get("OutputUUID") == NOTE_TEXT_UUID for item in attachments):
        raise ValueError("WFCreateNoteInput must reference the combined note text")


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    data = workflow()
    validate(data)
    UNSIGNED.write_bytes(plistlib.dumps(data, fmt=plistlib.FMT_BINARY))
    print(f"wrote {UNSIGNED}")
    print(
        "sign with: shortcuts sign --mode anyone "
        f"--input {UNSIGNED} --output {SIGNED}"
    )


if __name__ == "__main__":
    main()
