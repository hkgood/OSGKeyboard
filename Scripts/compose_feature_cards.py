#!/usr/bin/env python3
"""Compose short, silent, seamlessly looping feature clips for in-app cards.

Different deliverable from `compose_feature_previews.py`: no captions, no
title / end cards, no audio track, and cropped to the keyboard chrome so the
card shows the real keyboard rather than a stand-in host document.

Each clip is built to loop — the last frame matches the first, so a card can
autoplay it forever without a visible cut.

Reuses the raw recordings from `Scripts/record_feature_previews.sh` and the
CFR normalisation from `compose_feature_previews.py`.

Usage:
    Scripts/compose_feature_cards.py [slug ...]

Output: docs/assets/feature-cards/<slug>.mp4 (+ <slug>-poster.png)
"""

from __future__ import annotations

import json
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

from compose_feature_previews import RAW_DIR, constant_frame_rate, run  # noqa: F401

ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = ROOT / "docs" / "assets" / "feature-cards"
WORK = ROOT / ".tmp" / "feature-previews" / "cards"

FPS = 30
# Source-frame crop covering the keyboard chrome across every scenario. The
# clipboard panel is the tallest thing that appears there (top edge y=1779),
# and the bottom 72px of the screen is empty padding below the key row.
CROP_X, CROP_W = 0, 1290
CROP_Y, CROP_H = 1780, 944

# Overlap used to make the cut back to frame 0 invisible.
LOOP_BLEND = 0.5


@dataclass
class Card:
    slug: str
    # Raw recording slug under `.tmp/feature-previews/raw/`.
    raw: str
    # Window into the CFR recording, in real seconds.
    start: float
    duration: float
    # Static pages have nothing to animate; zoom in then back out so the clip
    # still moves and still loops perfectly.
    ping_pong_zoom: float = 1.0
    # Crop override for clips that are not the keyboard (e.g. a settings page).
    crop_y: int = CROP_Y
    crop_h: int = CROP_H


def probe_duration(path: Path) -> float:
    out = subprocess.check_output(
        ["ffprobe", "-v", "error", "-show_entries", "format=duration",
         "-of", "json", str(path)],
        text=True,
    )
    return float(json.loads(out)["format"]["duration"])


def encode_common(dest: Path) -> list[str]:
    return [
        "-an",  # cards are silent
        "-c:v", "libx264", "-pix_fmt", "yuv420p",
        "-profile:v", "high", "-level", "4.0", "-crf", "20",
        "-colorspace", "bt709", "-color_primaries", "bt709",
        "-color_trc", "iec61966-2-1", "-color_range", "tv",
        "-r", str(FPS), "-movflags", "+faststart",
        str(dest),
    ]


def build_motion(card: Card, work: Path) -> Path:
    """Trim + crop the window, or build a ping-pong zoom over a frozen frame."""
    src = constant_frame_rate(card.raw)
    dest = work / f"{card.slug}-motion.mp4"
    crop = f"crop={CROP_W}:{card.crop_h}:{CROP_X}:{card.crop_y}"

    if card.ping_pong_zoom > 1.0:
        frame = work / f"{card.slug}-still.png"
        run(["ffmpeg", "-y", "-ss", f"{card.start:.2f}", "-i", str(src),
             "-frames:v", "1", "-vf", crop, str(frame)])
        # Build only the zoom-in half and mirror it. Driving both directions
        # from a single zoompan expression relies on its output frame count
        # matching `duration * FPS`, which it does not — the clip then stops
        # part-way back out and the loop visibly jumps.
        half = card.duration / 2
        frames = max(2, int(half * FPS))
        step = (card.ping_pong_zoom - 1.0) / frames
        vf = (
            f"zoompan=z='min(1+{step:.6f}*on,{card.ping_pong_zoom:.4f})'"
            f":x='(iw-iw/zoom)/2':y='(ih-ih/zoom)/2'"
            f":d=1:s={CROP_W}x{card.crop_h}:fps={FPS},setsar=1"
        )
        forward = work / f"{card.slug}-zoomin.mp4"
        run([
            # A looped PNG defaults to 25 fps; without this the 30 fps zoompan
            # emits 25/30 of the frames asked for and the clip comes up short.
            "ffmpeg", "-y", "-loop", "1", "-framerate", str(FPS),
            "-t", f"{half:.2f}",
            "-i", str(frame), "-vf", vf, "-t", f"{half:.2f}",
            *encode_common(forward),
        ])
        run([
            "ffmpeg", "-y", "-i", str(forward), "-i", str(forward),
            "-filter_complex",
            "[1:v]reverse[r];[0:v][r]concat=n=2:v=1:a=0,format=yuv420p[v]",
            "-map", "[v]", *encode_common(dest),
        ])
        return dest

    run([
        "ffmpeg", "-y", "-ss", f"{card.start:.2f}", "-i", str(src),
        "-vf", f"{crop},fps={FPS},setsar=1",
        # The CFR pass already fixed timing, but clamp on the output side so
        # the window length is exact regardless of keyframe placement.
        "-t", f"{card.duration:.2f}",
        *encode_common(dest),
    ])
    return dest


def close_loop(source: Path, dest: Path, blend: float) -> None:
    """Fade the tail back over the head so frame 0 and the last frame match."""
    total = probe_duration(source)
    body = total - blend
    chain = (
        f"[0:v]split=2[head][tail];"
        f"[head]trim=start=0:end={body:.3f},setpts=PTS-STARTPTS[h];"
        f"[tail]trim=start={body:.3f}:end={total:.3f},setpts=PTS-STARTPTS,"
        f"format=yuva420p,fade=t=out:st=0:d={blend:.3f}:alpha=1[t];"
        f"[h][t]overlay=0:0:eof_action=pass,format=yuv420p[v]"
    )
    run([
        "ffmpeg", "-y", "-i", str(source),
        "-filter_complex", chain, "-map", "[v]",
        *encode_common(dest),
    ])


CARDS: dict[str, Card] = {}


def build(card: Card) -> Path:
    WORK.mkdir(parents=True, exist_ok=True)
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    motion = build_motion(card, WORK)
    final = OUT_DIR / f"{card.slug}.mp4"
    if card.ping_pong_zoom > 1.0:
        # A ping-pong already ends where it started; blending would only
        # duplicate frames.
        motion.replace(final)
    else:
        close_loop(motion, final, LOOP_BLEND)

    poster = OUT_DIR / f"{card.slug}-poster.png"
    run(["ffmpeg", "-y", "-i", str(final), "-frames:v", "1", str(poster)])
    return final


def main(argv: list[str]) -> int:
    from feature_card_specs import CARDS as configured  # noqa: PLC0415

    slugs = argv or list(configured)
    failures = 0
    for slug in slugs:
        card = configured.get(slug)
        if card is None:
            sys.stderr.write(f"unknown card: {slug}\n")
            failures += 1
            continue
        final = build(card)
        info = json.loads(subprocess.check_output(
            ["ffprobe", "-v", "error", "-select_streams", "v:0",
             "-show_entries", "stream=width,height,nb_frames",
             "-show_entries", "format=duration,size,nb_streams",
             "-of", "json", str(final)],
            text=True,
        ))
        stream, fmt = info["streams"][0], info["format"]
        duration = float(fmt["duration"])
        silent = int(fmt["nb_streams"]) == 1
        ok = 5.0 <= duration <= 11.0 and silent
        print(
            f"{'OK ' if ok else '!! '}{final.name}  "
            f"{stream['width']}x{stream['height']}  {duration:.1f}s  "
            f"{int(fmt['size']) / 1000:.0f} KB  {'silent' if silent else 'HAS AUDIO'}"
        )
        if not ok:
            failures += 1
    return 1 if failures else 0


if __name__ == "__main__":
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    raise SystemExit(main(sys.argv[1:]))
