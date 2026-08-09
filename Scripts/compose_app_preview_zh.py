#!/usr/bin/env python3
"""Compose a Chinese App Store preview (iPhone 6.7\") for OSGKeyboard.

Uses real Simulator / marketing UI stills + ffmpeg Ken Burns + ASS titles.
Output: docs/assets/app-preview/zh/OSGKeyboard-preview-6.7-zh.mp4
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = ROOT / "docs" / "assets" / "app-preview" / "zh"
WORK = ROOT / ".tmp" / "app-preview-zh" / "compose"
W, H = 1290, 2796  # App Store Connect 6.7"
FPS = 30

HOME_SRC = ROOT / ".tmp" / "app-preview-zh" / "shot-home-dark.png"
KB_IDLE = ROOT / "docs" / "assets" / "screenshots" / "zh" / "dark" / "iphone-keyboard_idle.png"
KB_REC = ROOT / "docs" / "assets" / "screenshots" / "zh" / "dark" / "iphone-keyboard_recording.png"
ICON = ROOT / "docs" / "assets" / "app-icon.png"

# Prefer a clean Chinese UI font available on this machine.
FONT_CANDIDATES = [
    Path("/Users/rocky/Library/Fonts/OPPO Sans 4.0.ttf"),
    Path("/System/Library/Fonts/STHeiti Medium.ttc"),
    Path("/System/Library/Fonts/Supplemental/Songti.ttc"),
]


def pick_font(size: int) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    for path in FONT_CANDIDATES:
        if not path.exists():
            continue
        try:
            return ImageFont.truetype(str(path), size=size, index=0)
        except OSError:
            continue
    return ImageFont.load_default()


def cover(img: Image.Image) -> Image.Image:
    """Scale to cover WxH and center-crop."""
    src = img.convert("RGB")
    scale = max(W / src.width, H / src.height)
    nw, nh = int(src.width * scale), int(src.height * scale)
    resized = src.resize((nw, nh), Image.Resampling.LANCZOS)
    left = (nw - W) // 2
    top = (nh - H) // 2
    return resized.crop((left, top, left + W, top + H))


def patch_home_warning(src: Path) -> Image.Image:
    """Hide Simulator-only Flow warning banner for marketing stills."""
    im = Image.open(src).convert("RGB")
    # Banner sits under the three status dots (~y 520–580 @ 1320×2868).
    sample = im.getpixel((im.width // 2, 500))
    draw = ImageDraw.Draw(im)
    draw.rounded_rectangle((48, 518, im.width - 48, 586), radius=28, fill=sample)
    return cover(im)


def title_card(lines: list[str], subtitle: str | None = None, with_icon: bool = False) -> Image.Image:
    im = Image.new("RGB", (W, H), (12, 12, 14))
    # Soft brand glow
    glow = Image.new("RGB", (W, H), (12, 12, 14))
    gdraw = ImageDraw.Draw(glow)
    cx, cy = W // 2, int(H * 0.38)
    for r, alpha in ((520, 28), (360, 40), (220, 55)):
        color = (18 + alpha // 4, 40 + alpha // 3, 28 + alpha // 5)
        gdraw.ellipse((cx - r, cy - r, cx + r, cy + r), fill=color)
    im = Image.blend(im, glow, 0.55)
    draw = ImageDraw.Draw(im)

    y = int(H * 0.34)
    if with_icon and ICON.exists():
        icon = Image.open(ICON).convert("RGBA").resize((220, 220), Image.Resampling.LANCZOS)
        # Rounded mask
        mask = Image.new("L", (220, 220), 0)
        ImageDraw.Draw(mask).rounded_rectangle((0, 0, 219, 219), radius=48, fill=255)
        im.paste(icon, ((W - 220) // 2, y - 280), mask)
        y = int(H * 0.42)

    title_font = pick_font(96 if len(lines) == 1 else 84)
    sub_font = pick_font(44)
    for line in lines:
        bbox = draw.textbbox((0, 0), line, font=title_font)
        tw = bbox[2] - bbox[0]
        draw.text(((W - tw) // 2, y), line, fill=(245, 246, 248), font=title_font)
        y += 120
    if subtitle:
        bbox = draw.textbbox((0, 0), subtitle, font=sub_font)
        tw = bbox[2] - bbox[0]
        draw.text(((W - tw) // 2, y + 24), subtitle, fill=(140, 160, 145), font=sub_font)
    return im


def overlay_caption(base: Image.Image, text: str) -> Image.Image:
    """Bottom gradient + caption for ad-style supers."""
    im = base.copy().convert("RGBA")
    shade = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(shade)
    for i in range(420):
        a = int(190 * (i / 419))
        y = H - 420 + i
        d.line([(0, y), (W, y)], fill=(0, 0, 0, a))
    im = Image.alpha_composite(im, shade)
    draw = ImageDraw.Draw(im)
    font = pick_font(64)
    bbox = draw.textbbox((0, 0), text, font=font)
    tw = bbox[2] - bbox[0]
    draw.text(((W - tw) // 2, H - 260), text, fill=(255, 255, 255, 255), font=font)
    return im.convert("RGB")


def write_ass(path: Path) -> None:
    # Kept for optional future hardsubs; primary captions are burned into stills.
    path.write_text(
        """[Script Info]
ScriptType: v4.00+
PlayResX: 1290
PlayResY: 2796

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Default,Heiti SC,64,&H00FFFFFF,&H000000FF,&H64000000,&H80000000,0,0,0,0,100,100,0,0,1,0,0,2,60,60,120,1

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
""",
        encoding="utf-8",
    )


def run(cmd: list[str]) -> None:
    print("+", " ".join(cmd[:8]), "..." if len(cmd) > 8 else "")
    subprocess.run(cmd, check=True)


def main() -> int:
    if not HOME_SRC.exists():
        print(f"missing home still: {HOME_SRC}", file=sys.stderr)
        return 1

    WORK.mkdir(parents=True, exist_ok=True)
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    home = patch_home_warning(HOME_SRC)
    kb_idle = cover(Image.open(KB_IDLE))
    kb_rec = cover(Image.open(KB_REC))

    scenes = {
        "01_open": title_card(["开口即文字"], with_icon=True),
        "02_hook": overlay_caption(home, "说，就好了"),
        "03_voice": overlay_caption(kb_rec, "说完就能用"),
        "04_type": overlay_caption(kb_idle, "打字也在行"),
        "05_privacy": overlay_caption(home, "默认不上传录音"),
        "06_end": title_card(["OSGKeyboard"], "开口即文字", with_icon=True),
    }
    for name, img in scenes.items():
        img.save(WORK / f"{name}.png", optimize=True)

    # Durations (seconds) — total ~28s
    timeline = [
        ("01_open", 2.2),
        ("02_hook", 3.2),
        ("03_voice", 7.0),
        ("04_type", 6.0),
        ("05_privacy", 5.0),
        ("06_end", 4.0),
    ]

    # Build concat list with zoompan Ken Burns per still.
    parts: list[Path] = []
    for idx, (name, dur) in enumerate(timeline):
        src = WORK / f"{name}.png"
        part = WORK / f"part-{idx:02d}.mp4"
        frames = max(1, int(dur * FPS))
        # Gentle zoom: alternate direction for rhythm
        if idx % 2 == 0:
            z = f"min(zoom+0.00045,1.08)"
            x = "iw/2-(iw/zoom/2)"
            y = "ih/2-(ih/zoom/2)"
        else:
            z = f"if(eq(on,1),1.08,max(zoom-0.00045,1.0))"
            x = "iw/2-(iw/zoom/2)"
            y = "ih/2-(ih/zoom/2)"
        vf = (
            f"scale={W}:{H}:force_original_aspect_ratio=increase,"
            f"crop={W}:{H},"
            f"zoompan=z='{z}':x='{x}':y='{y}':d={frames}:s={W}x{H}:fps={FPS},"
            f"setsar=1,format=yuv420p"
        )
        run(
            [
                "ffmpeg",
                "-y",
                "-loop",
                "1",
                "-i",
                str(src),
                "-vf",
                vf,
                "-t",
                f"{dur:.2f}",
                "-c:v",
                "libx264",
                "-pix_fmt",
                "yuv420p",
                "-profile:v",
                "high",
                "-level",
                "4.0",
                "-crf",
                "18",
                "-r",
                str(FPS),
                str(part),
            ]
        )
        parts.append(part)

    concat_list = WORK / "concat.txt"
    concat_list.write_text("".join(f"file '{p}'\n" for p in parts), encoding="utf-8")

    silent = WORK / "preview-silent.mp4"
    run(
        [
            "ffmpeg",
            "-y",
            "-f",
            "concat",
            "-safe",
            "0",
            "-i",
            str(concat_list),
            "-c:v",
            "libx264",
            "-pix_fmt",
            "yuv420p",
            "-movflags",
            "+faststart",
            "-r",
            str(FPS),
            str(silent),
        ]
    )

    # Soft generated bed (no third-party music / no copyright risk).
    final = OUT_DIR / "OSGKeyboard-preview-6.7-zh.mp4"
    run(
        [
            "ffmpeg",
            "-y",
            "-i",
            str(silent),
            "-f",
            "lavfi",
            "-i",
            "sine=frequency=196:sample_rate=44100,volume=0.035,afade=t=in:st=0:d=1.2,afade=t=out:st=25:d=2.5",
            "-f",
            "lavfi",
            "-i",
            "sine=frequency=293.66:sample_rate=44100,volume=0.02,afade=t=in:st=0:d=1.5,afade=t=out:st=25:d=2.5",
            "-filter_complex",
            "[1:a][2:a]amix=inputs=2:duration=first:dropout_transition=2[a]",
            "-map",
            "0:v",
            "-map",
            "[a]",
            "-c:v",
            "copy",
            "-c:a",
            "aac",
            "-b:a",
            "128k",
            "-shortest",
            "-movflags",
            "+faststart",
            str(final),
        ]
    )

    # Probe
    probe = subprocess.check_output(
        [
            "ffprobe",
            "-v",
            "error",
            "-select_streams",
            "v:0",
            "-show_entries",
            "stream=width,height,duration",
            "-show_entries",
            "format=duration,size",
            "-of",
            "default=noprint_wrappers=1",
            str(final),
        ],
        text=True,
    )
    print(probe)
    print(f"Wrote {final}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
