#!/usr/bin/env python3
"""Build the companion Shortcut for the Navigate skill.

Writes an unsigned binary plist that `shortcuts sign` can notarize.

The host already picked 高德 → 百度 → Apple Maps and passes one URL.
This recipe only materializes Shortcut Input as Text and opens it:

  Text (Shortcut Input)
    → Open URLs
"""

from __future__ import annotations

import plistlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = ROOT / "OSGKeyboard" / "Resources" / "Shortcuts"
UNSIGNED = OUT_DIR / "OSGNavigate.unsigned.shortcut"
SIGNED = OUT_DIR / "OSGNavigate.shortcut"

OBJECT_REPLACEMENT = "\ufffc"

TEXT_UUID = "C1D2E3F0-1111-4E00-8A5A-FD7E1B0C396F"
OPEN_UUID = "C1D2E3F1-2222-4F11-9A6B-0E8F2C1D4A70"


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


def workflow() -> dict:
    return {
        "WFWorkflowClientVersion": "3600.0.4",
        "WFWorkflowClientRelease": "26.0",
        "WFWorkflowMinimumClientVersion": 900,
        "WFWorkflowMinimumClientVersionString": "900",
        "WFWorkflowName": "OSG · 导航",
        "WFWorkflowHasShortcutInputVariables": True,
        "WFWorkflowHasOutputFallback": False,
        "WFWorkflowImportQuestions": [],
        "WFWorkflowTypes": [],
        "WFWorkflowInputContentItemClasses": [
            "WFStringContentItem",
            "WFURLContentItem",
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
            "WFWorkflowIconGlyphNumber": 59723,
            "WFWorkflowIconStartColor": 4278222847,
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
                "WFWorkflowActionIdentifier": "is.workflow.actions.openurl",
                "WFWorkflowActionParameters": {
                    "UUID": OPEN_UUID,
                    "WFURL": action_output_text("快捷指令文本", TEXT_UUID),
                    "WFShowWhenRun": False,
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
