#!/usr/bin/env python3
"""Seed rich demo data into OSGKeyboard via in-app DEBUG URL.

Uses `osgkeyboard://seed-demo` so the app itself disables iCloud sync and
writes Home / History / Dictionary placeholders with the real Swift models
(avoids KVS wiping plist-only seeds).

Usage:
  python3 scripts/seed_demo_data.py --mac
  python3 scripts/seed_demo_data.py --sim <UDID>
  python3 scripts/seed_demo_data.py --all
"""

from __future__ import annotations

import argparse
import subprocess
import sys
import time
from pathlib import Path

BUNDLE_IOS = "com.osgkeyboard.ios"
SEED_URL = "osgkeyboard://seed-demo"
MAC_APP = Path(
    "/Users/rocky/Library/Developer/Xcode/DerivedData/OSGKeyboard-dgaosbtwferhcpclfyzxmfuwaikn"
    "/Build/Products/Debug/OSGKeyboard.app"
)
# Fallback if DerivedData folder hash changes.
if not MAC_APP.exists():
    alt = Path("/Users/rocky/Documents/OSGKeyboard/build/mac/Build/Products/Debug/OSGKeyboard.app")
    if alt.exists():
        MAC_APP = alt
    else:
        found = sorted(Path.home().glob(
            "Library/Developer/Xcode/DerivedData/OSGKeyboard-*/Build/Products/Debug/OSGKeyboard.app"
        ))
        if found:
            MAC_APP = found[-1]


def run(cmd: list[str], check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(cmd, check=check, capture_output=True, text=True)


def seed_mac() -> None:
    print("=== macOS ===")
    run(["osascript", "-e", 'tell application "OSGKeyboard" to quit'], check=False)
    run(["pkill", "-x", "OSGKeyboard"], check=False)
    time.sleep(0.5)
    if MAC_APP.exists():
        run(["open", str(MAC_APP)], check=False)
    else:
        run(["open", "-a", "OSGKeyboard"], check=False)
    time.sleep(2.0)
    # openURL while app is running
    result = run(["open", SEED_URL], check=False)
    if result.returncode != 0:
        print("open URL failed:", result.stderr, file=sys.stderr)
    else:
        print(f"opened {SEED_URL}")
    time.sleep(1.5)


def seed_sim(udid: str) -> None:
    print(f"=== simulator {udid} ===")
    run(["xcrun", "simctl", "boot", udid], check=False)
    run(["xcrun", "simctl", "bootstatus", udid, "-b"], check=False)
    # Ensure app is frontmost
    run(["xcrun", "simctl", "terminate", udid, BUNDLE_IOS], check=False)
    time.sleep(0.3)
    launch = run(["xcrun", "simctl", "launch", udid, BUNDLE_IOS], check=False)
    if launch.returncode != 0:
        raise RuntimeError(f"launch failed: {launch.stderr.strip()}")
    time.sleep(2.0)
    opened = run(["xcrun", "simctl", "openurl", udid, SEED_URL], check=False)
    if opened.returncode != 0:
        raise RuntimeError(f"openurl failed: {opened.stderr.strip()}")
    print(f"opened {SEED_URL}")
    time.sleep(1.5)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mac", action="store_true")
    parser.add_argument("--sim", action="append", default=[])
    parser.add_argument("--all", action="store_true")
    args = parser.parse_args()

    sims = list(args.sim)
    do_mac = args.mac
    if args.all:
        do_mac = True
        for udid in [
            "D6D8DA15-704E-4A4E-8A47-7AAB5A9DE4C4",  # iPad A16
            "B3EB5C4D-6802-42A7-92C1-56530523F8E3",  # iPhone 17 Pro
        ]:
            if udid not in sims:
                sims.append(udid)

    if not do_mac and not sims:
        parser.error("Pass --mac, --sim UDID, or --all")

    if do_mac:
        seed_mac()
    for udid in sims:
        try:
            seed_sim(udid)
        except Exception as exc:  # noqa: BLE001
            print(f"skip {udid}: {exc}", file=sys.stderr)
    print("done — check Home / History / Dictionary in each running app")


if __name__ == "__main__":
    main()
