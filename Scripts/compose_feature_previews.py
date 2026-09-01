#!/usr/bin/env python3
"""Compose the four Chinese feature preview clips for OSGKeyboard.

Takes raw Simulator screen recordings (1290x2796, iPhone 16 Plus) produced by
`Scripts/record_feature_previews.sh` and turns each into an App Store Connect
compliant preview: title card -> captioned footage -> end card, plus a soft
generated audio bed.

This ffmpeg build ships without libfreetype / libass, so every piece of text is
rendered to RGBA PNG with Pillow and composited with `overlay`.

Usage:
    Scripts/compose_feature_previews.py [slug ...]

Output: docs/assets/app-preview/zh/OSGKeyboard-<slug>-6.7-zh.mp4
"""

from __future__ import annotations

import json
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
RAW_DIR = ROOT / ".tmp" / "feature-previews" / "raw"
WORK_ROOT = ROOT / ".tmp" / "feature-previews" / "work"
OUT_DIR = ROOT / "docs" / "assets" / "app-preview" / "zh"

W, H = 1290, 2796  # App Store Connect 6.7" / 6.9" portrait
FPS = 30

ICON = ROOT / "docs" / "assets" / "app-icon.png"

# No PingFang on every machine; Hiragino Sans GB is the cleanest CJK fallback.
FONT_CANDIDATES = [
    (Path("/System/Library/Fonts/Hiragino Sans GB.ttc"), 1),
    (Path("/System/Library/Fonts/Hiragino Sans GB.ttc"), 0),
    (Path("/System/Library/Fonts/STHeiti Medium.ttc"), 0),
    (Path("/System/Library/Fonts/Supplemental/Songti.ttc"), 0),
]

BG = (11, 13, 12)
FG = (245, 246, 248)
ACCENT = (52, 168, 96)


# --------------------------------------------------------------------------
# Timeline description
# --------------------------------------------------------------------------


@dataclass
class Caption:
    """A lower-third super burned over the footage."""

    start: float
    end: float
    text: str
    # Second line, rendered smaller under `text`.
    sub: str | None = None


@dataclass
class Source:
    """One trimmed window of raw footage, with its own captions.

    A clip can chain several — the voice clip cuts from the polish flow in the
    keyboard to the Styles page that owns the playful personalities.
    """

    # Raw recording slug, i.e. `.tmp/feature-previews/raw/<raw>.mov`.
    raw: str
    trim_start: float
    trim_duration: float
    captions: list[Caption] = field(default_factory=list)
    # `simctl io recordVideo` only emits frames when the screen changes, so a
    # static page yields a few seconds of footage no matter how long you wait.
    # Set this to grab one frame at that timestamp and hold it for
    # `trim_duration` instead, letting `ken_burns` supply the motion.
    freeze_at: float | None = None
    # Slow push-in over otherwise-static footage (e.g. a settings page that
    # does not animate). Expressed as the final zoom factor; 1.0 disables it.
    ken_burns: float = 1.0
    # Normalised focal point for the push-in — (0.5, 0.5) is dead centre.
    ken_burns_focus: tuple[float, float] = (0.5, 0.5)


@dataclass
class Clip:
    slug: str
    # Title card copy.
    title: list[str]
    subtitle: str
    sources: list[Source]
    title_seconds: float = 2.4
    end_seconds: float = 2.6
    end_title: str = "OSGKeyboard"
    end_subtitle: str = "开口即文字"

    @property
    def body_seconds(self) -> float:
        return sum(source.trim_duration for source in self.sources)

    @property
    def total_seconds(self) -> float:
        return self.title_seconds + self.body_seconds + self.end_seconds


def font(size: int) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    for path, index in FONT_CANDIDATES:
        if not path.exists():
            continue
        try:
            return ImageFont.truetype(str(path), size=size, index=index)
        except OSError:
            continue
    return ImageFont.load_default()


def text_width(draw: ImageDraw.ImageDraw, text: str, fnt) -> int:
    box = draw.textbbox((0, 0), text, font=fnt)
    return box[2] - box[0]


def centered(draw: ImageDraw.ImageDraw, y: int, text: str, fnt, fill) -> None:
    draw.text(((W - text_width(draw, text, fnt)) // 2, y), text, font=fnt, fill=fill)


# --------------------------------------------------------------------------
# Card + caption rendering
# --------------------------------------------------------------------------


def title_card(lines: list[str], subtitle: str, with_icon: bool = True) -> Image.Image:
    im = Image.new("RGB", (W, H), BG)
    glow = Image.new("RGB", (W, H), BG)
    gdraw = ImageDraw.Draw(glow)
    cx, cy = W // 2, int(H * 0.40)
    for radius, lift in ((560, 26), (380, 38), (230, 52)):
        gdraw.ellipse(
            (cx - radius, cy - radius, cx + radius, cy + radius),
            fill=(BG[0] + lift // 5, BG[1] + lift // 2, BG[2] + lift // 4),
        )
    im = Image.blend(im, glow, 0.6)
    draw = ImageDraw.Draw(im)

    y = int(H * 0.36)
    if with_icon and ICON.exists():
        icon = Image.open(ICON).convert("RGBA").resize((216, 216), Image.Resampling.LANCZOS)
        mask = Image.new("L", (216, 216), 0)
        ImageDraw.Draw(mask).rounded_rectangle((0, 0, 215, 215), radius=48, fill=255)
        im.paste(icon, ((W - 216) // 2, y - 300), mask)

    title_font = font(104 if len(lines) == 1 else 92)
    for line in lines:
        centered(draw, y, line, title_font, FG)
        y += 132

    if subtitle:
        centered(draw, y + 28, subtitle, font(46), (146, 166, 150))
    return im


def caption_overlay(text: str, sub: str | None) -> Image.Image:
    """Full-frame RGBA layer: bottom scrim + caption. Composited via overlay.

    The app UI is light, so the scrim has to carry real weight — a gentle
    gradient leaves white supers unreadable over a white settings card.
    """
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    draw = ImageDraw.Draw(im)

    scrim_height = 780
    for i in range(scrim_height):
        # Sub-linear ramp: the supers sit well above the bottom edge, so the
        # gradient has to carry real weight by the time it reaches them.
        alpha = int(246 * (i / (scrim_height - 1)) ** 0.85)
        draw.line([(0, H - scrim_height + i), (W, H - scrim_height + i)], fill=(0, 0, 0, alpha))

    main_font = font(66)
    baseline = H - 320 if sub else H - 268
    centered(draw, baseline, text, main_font, (255, 255, 255, 255))
    if sub:
        centered(draw, baseline + 104, sub, font(44), (203, 221, 207, 255))
    return im


# --------------------------------------------------------------------------
# ffmpeg plumbing
# --------------------------------------------------------------------------


def run(cmd: list[str]) -> None:
    proc = subprocess.run(cmd, capture_output=True, text=True)
    if proc.returncode != 0:
        sys.stderr.write(" ".join(cmd) + "\n")
        sys.stderr.write(proc.stderr[-4000:] + "\n")
        raise SystemExit(f"ffmpeg failed ({proc.returncode})")


def probe(path: Path) -> dict:
    out = subprocess.check_output(
        [
            "ffprobe", "-v", "error",
            "-select_streams", "v:0",
            "-show_entries", "stream=width,height,r_frame_rate,codec_name",
            "-show_entries", "format=duration,size",
            "-of", "json",
            str(path),
        ],
        text=True,
    )
    return json.loads(out)


def still_to_segment(image: Image.Image, seconds: float, dest: Path, zoom_in: bool) -> None:
    src = dest.with_suffix(".png")
    image.save(src, optimize=True)
    frames = max(1, int(seconds * FPS))
    if zoom_in:
        z = "min(zoom+0.00042,1.07)"
    else:
        z = "if(eq(on,1),1.07,max(zoom-0.00042,1.0))"
    vf = (
        f"scale={W}:{H}:force_original_aspect_ratio=increase,crop={W}:{H},"
        f"zoompan=z='{z}':x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':"
        f"d={frames}:s={W}x{H}:fps={FPS},setsar=1,format=yuv420p"
    )
    run([
        "ffmpeg", "-y", "-loop", "1", "-i", str(src),
        "-vf", vf, "-t", f"{seconds:.2f}",
        "-c:v", "libx264", "-pix_fmt", "yuv420p",
        "-profile:v", "high", "-level", "4.0", "-crf", "18", "-r", str(FPS),
        "-colorspace", "bt709", "-color_primaries", "bt709",
        "-color_trc", "iec61966-2-1", "-color_range", "tv",
        str(dest),
    ])


def constant_frame_rate(slug: str) -> Path:
    """Return a CFR copy of a raw recording, building it on first use.

    `simctl io recordVideo` writes variable-frame-rate footage whose timeline
    does not advance at wall-clock rate, so seeking into it lands in the wrong
    place and `-t` windows come out the wrong length. Normalising once up
    front makes every `trim_start` / `trim_duration` below mean real seconds.
    """
    raw = RAW_DIR / f"{slug}.mov"
    if not raw.exists():
        raise SystemExit(f"missing recording: {raw}")

    cfr = WORK_ROOT / "cfr" / f"{slug}.mp4"
    if cfr.exists() and cfr.stat().st_mtime >= raw.stat().st_mtime:
        return cfr

    cfr.parent.mkdir(parents=True, exist_ok=True)
    run([
        "ffmpeg", "-y", "-i", str(raw),
        "-vf", f"fps={FPS},scale={W}:{H}:force_original_aspect_ratio=increase,"
               f"crop={W}:{H},setsar=1",
        "-vsync", "cfr",
        "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "16",
        "-colorspace", "bt709", "-color_primaries", "bt709",
        "-color_trc", "iec61966-2-1", "-color_range", "tv",
        "-r", str(FPS), str(cfr),
    ])
    return cfr


def footage_segment(source: Source, work: Path, dest: Path, index: int) -> None:
    """Trim one recording, normalise to 1290x2796, burn its captions."""
    raw = constant_frame_rate(source.raw)

    if source.freeze_at is None:
        inputs: list[str] = [
            "-ss", f"{source.trim_start:.2f}",
            "-t", f"{source.trim_duration:.2f}",
            "-i", str(raw),
        ]
    else:
        frame = work / f"freeze-{index:02d}.png"
        run([
            "ffmpeg", "-y", "-ss", f"{source.freeze_at:.2f}", "-i", str(raw),
            "-frames:v", "1", str(frame),
        ])
        inputs = [
            "-loop", "1", "-t", f"{source.trim_duration:.2f}", "-i", str(frame),
        ]
    for idx, cap in enumerate(source.captions):
        png = work / f"cap-{index:02d}-{idx:02d}.png"
        caption_overlay(cap.text, cap.sub).save(png)
        # A single-frame input has pts 0 forever, which freezes `fade` at its
        # t=0 value and leaves the super permanently transparent. Loop it so
        # the overlay carries a real timeline for the fades to run against.
        inputs += ["-loop", "1", "-t", f"{source.trim_duration:.2f}", "-i", str(png)]

    # Normalise the recording first, then stack caption overlays on top.
    normalise = (
        f"scale={W}:{H}:force_original_aspect_ratio=increase,"
        f"crop={W}:{H},fps={FPS}"
    )
    if source.ken_burns > 1.0:
        # Static pages (a settings screen) need the motion to come from the
        # camera. Step per frame so the push-in lands exactly at `ken_burns`.
        frames = max(1, int(source.trim_duration * FPS))
        step = (source.ken_burns - 1.0) / frames
        fx, fy = source.ken_burns_focus
        normalise += (
            f",zoompan=z='min(zoom+{step:.6f},{source.ken_burns:.4f})'"
            f":x='(iw-iw/zoom)*{fx:.3f}':y='(ih-ih/zoom)*{fy:.3f}'"
            f":d=1:s={W}x{H}:fps={FPS}"
        )
    chain = [f"[0:v]{normalise},setsar=1[base]"]
    current = "base"
    for idx, cap in enumerate(source.captions):
        nxt = f"ov{idx}"
        # Fade the supers in and out so cuts do not pop.
        chain.append(
            f"[{idx + 1}:v]format=rgba,"
            f"fade=t=in:st={cap.start:.2f}:d=0.28:alpha=1,"
            f"fade=t=out:st={max(cap.start, cap.end - 0.28):.2f}:d=0.28:alpha=1[c{idx}]"
        )
        chain.append(
            f"[{current}][c{idx}]overlay=0:0:"
            f"enable='between(t,{cap.start:.2f},{cap.end:.2f})'[{nxt}]"
        )
        current = nxt
    chain.append(f"[{current}]format=yuv420p[vout]")

    run([
        "ffmpeg", "-y", *inputs,
        "-filter_complex", ";".join(chain),
        "-map", "[vout]",
        # `simctl io recordVideo` writes variable-frame-rate footage, so an
        # input-side `-t` drifts once `fps=` fills the gaps. Clamp the output
        # instead or the finished clip overruns the App Store 30s ceiling.
        "-t", f"{source.trim_duration:.2f}",
        "-c:v", "libx264", "-pix_fmt", "yuv420p",
        "-profile:v", "high", "-level", "4.0", "-crf", "18", "-r", str(FPS),
        "-colorspace", "bt709", "-color_primaries", "bt709",
        "-color_trc", "iec61966-2-1", "-color_range", "tv",
        str(dest),
    ])


def build(clip: Clip) -> Path:
    work = WORK_ROOT / clip.slug
    work.mkdir(parents=True, exist_ok=True)
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    title = work / "00-title.mp4"
    still_to_segment(title_card(clip.title, clip.subtitle), clip.title_seconds, title, True)
    parts = [title]

    for index, source in enumerate(clip.sources):
        part = work / f"{index + 1:02d}-body.mp4"
        footage_segment(source, work, part, index)
        parts.append(part)

    end = work / "99-end.mp4"
    still_to_segment(
        title_card([clip.end_title], clip.end_subtitle), clip.end_seconds, end, False
    )
    parts.append(end)

    concat = work / "concat.txt"
    concat.write_text("".join(f"file '{p}'\n" for p in parts), encoding="utf-8")

    silent = work / "silent.mp4"
    run([
        "ffmpeg", "-y", "-f", "concat", "-safe", "0", "-i", str(concat),
        "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "18",
        "-colorspace", "bt709", "-color_primaries", "bt709",
        "-color_trc", "iec61966-2-1", "-color_range", "tv",
        "-r", str(FPS), "-movflags", "+faststart", str(silent),
    ])

    # App previews need an audio track; generate a soft royalty-free bed.
    total = clip.total_seconds
    fade_out = max(0.0, total - 2.2)
    final = OUT_DIR / f"OSGKeyboard-{clip.slug}-6.7-zh.mp4"
    run([
        "ffmpeg", "-y", "-i", str(silent),
        "-f", "lavfi", "-i",
        f"sine=frequency=196:sample_rate=44100,volume=0.030,"
        f"afade=t=in:st=0:d=1.1,afade=t=out:st={fade_out:.2f}:d=2.0",
        "-f", "lavfi", "-i",
        f"sine=frequency=293.66:sample_rate=44100,volume=0.018,"
        f"afade=t=in:st=0:d=1.4,afade=t=out:st={fade_out:.2f}:d=2.0",
        "-filter_complex", "[1:a][2:a]amix=inputs=2:duration=first:dropout_transition=2[a]",
        "-map", "0:v", "-map", "[a]",
        "-c:v", "copy", "-c:a", "aac", "-b:a", "128k",
        "-shortest", "-movflags", "+faststart", str(final),
    ])
    return final


CLIPS: dict[str, Clip] = {}


def main(argv: list[str]) -> int:
    from feature_preview_clips import CLIPS as configured  # noqa: PLC0415

    slugs = argv or list(configured)
    failures = 0
    for slug in slugs:
        clip = configured.get(slug)
        if clip is None:
            sys.stderr.write(f"unknown clip: {slug}\n")
            failures += 1
            continue
        final = build(clip)
        info = probe(final)
        duration = float(info["format"]["duration"])
        stream = info["streams"][0]
        size_mb = int(info["format"]["size"]) / 1_000_000
        ok = (
            stream["width"] == W
            and stream["height"] == H
            and 15.0 <= duration <= 30.0
            and stream["codec_name"] == "h264"
        )
        flag = "OK " if ok else "!! "
        print(
            f"{flag}{final.name}  {stream['width']}x{stream['height']}  "
            f"{duration:.1f}s  {size_mb:.1f} MB  {stream['codec_name']}"
        )
        if not ok:
            failures += 1
            if not 15.0 <= duration <= 30.0:
                print(f"   duration {duration:.1f}s outside the App Store 15-30s window")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    raise SystemExit(main(sys.argv[1:]))
