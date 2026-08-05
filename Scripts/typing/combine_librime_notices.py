#!/usr/bin/env python3
"""Combine librime release notices into one in-app readable text file."""

from pathlib import Path
from zipfile import ZipFile

ROOT = Path(__file__).resolve().parents[2]
RESOURCE_DIR = ROOT / "OSGKeyboardShared" / "Resources" / "Typing"
OUTPUT = RESOURCE_DIR / "LIBRIME-COMBINED-NOTICES.txt"


def main() -> None:
    sections: list[str] = []
    for name in ("LICENSE.txt", "THIRD_PARTY_NOTICES.md"):
        path = RESOURCE_DIR / name
        sections.append(f"{'=' * 72}\n{name}\n{'=' * 72}\n\n{path.read_text(encoding='utf-8')}")

    with ZipFile(RESOURCE_DIR / "third-party-notices.zip") as archive:
        for name in sorted(item for item in archive.namelist() if item.endswith(".txt")):
            text = archive.read(name).decode("utf-8", errors="replace")
            sections.append(f"{'=' * 72}\n{name}\n{'=' * 72}\n\n{text}")

    OUTPUT.write_text("\n\n".join(sections) + "\n", encoding="utf-8")
    print(f"Wrote {OUTPUT} ({OUTPUT.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
