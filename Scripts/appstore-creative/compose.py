#!/usr/bin/env python3
"""Build the App Store creative assets (product page header + search results).

Specs (App Store Connect › Creative assets specifications):
  * Header video   21:9  3840×1646        30 fps, 5–30 s, mp4
  * Search video   3:2   1920×1280…3840×2560
  * Universal still 16:9 5244×2950 PNG (no video allowed at this size)
Safe areas are taken from Apple's creative-asset Sketch template.

Scenes are deterministic canvas pages (header.html / search.html) rendered by
render.cjs; search results composite the real simulator recordings from
`Scripts/record_feature_previews.sh` into the device screens.

Usage:
    NODE_PATH=.tmp/appstore-assets/node_modules \\
      python3 Scripts/appstore-creative/compose.py [header|search|stills ...] [--lang zh,en]

Output: .tmp/appstore-creative/out/
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

from PIL import Image, ImageDraw

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
WORK = ROOT / ".tmp" / "appstore-creative" / "work"
OUT = ROOT / ".tmp" / "appstore-creative" / "out"
RAW = {
    "zh": ROOT / ".tmp" / "feature-previews" / "raw",
    "en": ROOT / ".tmp" / "feature-previews" / "raw-en",
}

FPS = 30
DURATION = 10.0  # every scene loops on this period
LOOP_BLEND = 0.6  # tail-over-head crossfade that closes each screen loop
POSTER_T = 7.4  # header: full line written, sheen finished

HEADER_SIZE = (3840, 1646)
HEADER_SAFE = "1097,493,1646,661"
UNIVERSAL_SIZE = (5244, 2950)
UNIVERSAL_SAFE = "1921,660,1402,962"
SEARCH_SIZE = (3840, 2560)
# H.264 above Level 5.1 is not universally decodable; ship a 5.1 copy too.
SEARCH_COMPAT = (3072, 2048)


@dataclass(frozen=True)
class Window:
    """Segments of a raw recording, in real (CFR) seconds, played back to back.

    Cuts only land inside static holds (processing, generating, answer
    review), where neighbouring frames are identical, so they read as one
    continuous take. Segments must add up to DURATION + LOOP_BLEND.
    """

    raw: str
    segments: tuple[tuple[float, float], ...]


# Read off 0.5 s contact sheets of the CFR footage. Re-time after re-recording.
WINDOWS: dict[str, dict[str, Window]] = {
    "zh": {
        # 复制的消息 → 技能行 → 思考 → 答案 → 回复气泡落进对话
        "clipboard": Window("clipboard-agent", ((17.0, 27.6),)),
        # 聆听 → 处理 → 编辑后结果 → 应用到备忘录
        "voice": Window("voice-polish", ((6.3, 9.6), (10.9, 14.6), (16.9, 20.5))),
        # 长按提问 → 生成 → 答案 → 插入对话
        "ask": Window("ask-ai", ((12.8, 16.6), (20.2, 23.6), (25.9, 29.3))),
    },
    "en": {
        "clipboard": Window("clipboard-agent", ((17.5, 28.1),)),
        "voice": Window("voice-polish", ((6.3, 9.6), (11.0, 14.7), (17.6, 21.2))),
        "ask": Window("ask-ai", ((12.2, 15.9), (21.0, 24.6), (29.2, 32.5))),
    },
}

# sRGB transfer matches the simulator footage and the PNG stills, so players
# do not shift the greens between the video and its poster.
COLOR_TAGS = [
    "-colorspace", "bt709", "-color_primaries", "bt709",
    "-color_trc", "iec61966-2-1", "-color_range", "tv",
]
# Frame side data wins over the CLI tags after `scale`; pin it explicitly or
# the stream ships with unknown primaries / transfer.
SET_COLOR = "setparams=color_primaries=bt709:color_trc=iec61966-2-1:colorspace=bt709:range=tv"


def run(cmd: list[str]) -> None:
    proc = subprocess.run(cmd, capture_output=True, text=True)
    if proc.returncode != 0:
        sys.stderr.write(" ".join(map(str, cmd)) + "\n" + proc.stderr[-4000:] + "\n")
        raise SystemExit(f"command failed ({proc.returncode})")


def render(page: str, query: str, out: Path, *, still: float | None = None,
           layout: Path | None = None) -> None:
    cmd = ["node", str(HERE / "render.cjs"), "--page", page, "--query", query, "--out", str(out)]
    if still is None:
        cmd += ["--video", "--fps", str(FPS)]
    else:
        cmd += ["--still", f"{still}"]
    if layout:
        cmd += ["--layout", str(layout)]
    print(f"  render {page} {query} -> {out.name}", flush=True)
    subprocess.run(cmd, check=True, env={**os.environ})


def flatten_png(path: Path) -> None:
    """App Store Connect rejects images with an alpha channel."""
    Image.open(path).convert("RGB").save(path, optimize=True)


def deliver(src: Path, dest: Path, size: tuple[int, int], level: str) -> None:
    w, h = size
    run([
        "ffmpeg", "-y", "-i", str(src),
        "-vf", f"scale={w}:{h}:flags=lanczos:out_color_matrix=bt709:out_range=tv,"
               f"format=yuv420p,{SET_COLOR}",
        "-an", "-r", str(FPS), "-t", f"{DURATION:.3f}",
        "-c:v", "libx264", "-preset", "slow", "-profile:v", "high", "-level", level,
        "-crf", "14", "-maxrate", "60M", "-bufsize", "120M",
        *COLOR_TAGS, "-movflags", "+faststart", str(dest),
    ])


def probe(path: Path) -> str:
    info = json.loads(subprocess.check_output([
        "ffprobe", "-v", "error", "-select_streams", "v:0",
        "-show_entries", "stream=codec_name,profile,level,width,height,r_frame_rate,nb_frames",
        "-show_entries", "format=duration,size,nb_streams", "-of", "json", str(path),
    ], text=True))
    s, f = info["streams"][0], info["format"]
    return (f"{path.name}: {s['width']}x{s['height']} {s['codec_name']} {s.get('profile')} "
            f"L{s.get('level')} {s['r_frame_rate']} {float(f['duration']):.2f}s "
            f"{int(f['size']) / 1e6:.1f} MB streams={f['nb_streams']}")


# --------------------------------------------------------------------------
# Header


def build_header(lang: str) -> None:
    w, h = HEADER_SIZE
    q = f"w={w}&h={h}&safe={HEADER_SAFE}&lang={lang}"
    master = WORK / f"header-{lang}.mov"
    render("header.html", q, master)
    dest = OUT / f"OSG-Header-{w}x{h}-{lang}.mp4"
    deliver(master, dest, HEADER_SIZE, "5.1")
    poster = OUT / f"OSG-Header-{w}x{h}-{lang}-poster.png"
    render("header.html", q, poster, still=POSTER_T)
    flatten_png(poster)
    print("  " + probe(dest))


def build_universal(lang: str) -> None:
    w, h = UNIVERSAL_SIZE
    dest = OUT / f"OSG-Universal-{w}x{h}-{lang}.png"
    render("header.html", f"w={w}&h={h}&safe={UNIVERSAL_SAFE}&lang={lang}&hero=1",
           dest, still=POSTER_T)
    flatten_png(dest)
    # Static 21:9 header in the same hero state, for an image-only upload.
    hw, hh = HEADER_SIZE
    still = OUT / f"OSG-Header-{hw}x{hh}-{lang}-still.png"
    render("header.html", f"w={hw}&h={hh}&safe={HEADER_SAFE}&lang={lang}&hero=1",
           still, still=POSTER_T)
    flatten_png(still)


# --------------------------------------------------------------------------
# Search results


def cfr(lang: str, raw: str) -> Path:
    src = RAW[lang] / f"{raw}.mov"
    if not src.exists():
        raise SystemExit(f"missing recording: {src}")
    dest = WORK / "cfr" / lang / f"{raw}.mp4"
    if dest.exists() and dest.stat().st_mtime >= src.stat().st_mtime:
        return dest
    dest.parent.mkdir(parents=True, exist_ok=True)
    # simctl footage is VFR; normalise once so window times are real seconds.
    run([
        "ffmpeg", "-y", "-i", str(src), "-vf", f"fps={FPS},setsar=1", "-vsync", "cfr",
        "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "12", "-preset", "medium",
        *COLOR_TAGS, str(dest),
    ])
    return dest


def screen_mask(w: int, h: int, r: int, dest: Path) -> Path:
    """Anti-aliased rounded-rect alpha mask (4× supersampled)."""
    ss = 4
    big = Image.new("L", (w * ss, h * ss), 0)
    ImageDraw.Draw(big).rounded_rectangle((0, 0, w * ss - 1, h * ss - 1), radius=r * ss, fill=255)
    big.resize((w, h), Image.LANCZOS).save(dest)
    return dest


def screen_loop(lang: str, screen: dict) -> Path:
    """Trim → scale → close the loop → round the corners, as ProRes 4444."""
    win = WINDOWS[lang][screen["id"]]
    src = cfr(lang, win.raw)
    w, h, r = screen["w"], screen["h"], screen["r"]
    mask = screen_mask(w, h, r, WORK / f"mask-{w}x{h}.png")
    dest = WORK / f"screen-{lang}-{screen['id']}.mov"
    body = DURATION
    total = DURATION + LOOP_BLEND
    span = sum(end - start for start, end in win.segments)
    if abs(span - total) > 0.01:
        raise SystemExit(f"{lang}/{screen['id']}: segments sum to {span:.2f}s, need {total:.2f}s")

    n = len(win.segments)
    chain = f"[0:v]split={n}" + "".join(f"[s{i}]" for i in range(n)) + ";"
    for i, (start, end) in enumerate(win.segments):
        chain += f"[s{i}]trim=start={start:.3f}:end={end:.3f},setpts=PTS-STARTPTS[g{i}];"
    chain += "".join(f"[g{i}]" for i in range(n)) + f"concat=n={n}:v=1:a=0,"
    chain += (
        f"scale={w}:{h}:flags=lanczos,split=2[a][b];"
        f"[a]trim=start=0:end={body:.3f},setpts=PTS-STARTPTS[head];"
        f"[b]trim=start={body:.3f}:end={total:.3f},setpts=PTS-STARTPTS,"
        f"format=yuva444p,fade=t=out:st=0:d={LOOP_BLEND:.3f}:alpha=1[tail];"
        f"[head][tail]overlay=0:0:eof_action=pass,format=yuva444p[looped];"
        f"[1:v]format=gray,loop=-1:size=1,trim=duration={body:.3f}[m];"
        f"[looped][m]alphamerge[v]"
    )
    run([
        "ffmpeg", "-y", "-i", str(src), "-i", str(mask), "-filter_complex", chain,
        "-map", "[v]", "-t", f"{body:.3f}", "-r", str(FPS),
        "-c:v", "prores_ks", "-profile:v", "4", "-pix_fmt", "yuva444p10le", str(dest),
    ])
    return dest


def build_search(lang: str) -> None:
    w, h = SEARCH_SIZE
    base_q = f"w={w}&h={h}&lang={lang}"
    layout_path = WORK / f"search-layout-{lang}.json"
    under = WORK / f"search-under-{lang}.mov"
    over = WORK / f"search-over-{lang}.mov"
    scene_mtime = (HERE / "search.html").stat().st_mtime
    fresh = all(p.exists() and p.stat().st_mtime > scene_mtime for p in (under, over, layout_path))
    if not fresh:
        render("search.html", base_q + "&layer=under", under, layout=layout_path)
        render("search.html", base_q + "&layer=over", over)
    layout = json.loads(layout_path.read_text())

    screens = [screen_loop(lang, s) for s in layout["screens"]]

    inputs = ["-i", str(under)]
    for s in screens:
        inputs += ["-i", str(s)]
    inputs += ["-i", str(over)]
    chain = "[0:v]format=yuva444p10le[base0];"
    for i, s in enumerate(layout["screens"], start=1):
        chain += f"[base{i - 1}][{i}:v]overlay={s['x']}:{s['y']}:format=auto[base{i}];"
    n = len(screens)
    chain += f"[base{n}][{n + 1}:v]overlay=0:0:format=auto,format=yuv444p10le,{SET_COLOR}[v]"

    master = WORK / f"search-{lang}.mov"
    run([
        "ffmpeg", "-y", *inputs, "-filter_complex", chain, "-map", "[v]",
        "-t", f"{DURATION:.3f}", "-r", str(FPS),
        "-c:v", "prores_ks", "-profile:v", "4", "-pix_fmt", "yuv444p10le",
        *COLOR_TAGS, str(master),
    ])

    full = OUT / f"OSG-Search-{w}x{h}-{lang}.mp4"
    deliver(master, full, SEARCH_SIZE, "6.0")
    cw, ch = SEARCH_COMPAT
    compat = OUT / f"OSG-Search-{cw}x{ch}-{lang}.mp4"
    deliver(master, compat, SEARCH_COMPAT, "5.1")

    poster = OUT / f"OSG-Search-{w}x{h}-{lang}-poster.png"
    run(["ffmpeg", "-y", "-ss", "4.0", "-i", str(master), "-frames:v", "1",
         "-vf", "scale=out_color_matrix=bt709:in_range=tv:out_range=pc,format=rgb24", str(poster)])
    flatten_png(poster)
    print("  " + probe(full))
    print("  " + probe(compat))


# --------------------------------------------------------------------------


def main(argv: list[str]) -> int:
    langs = ["zh", "en"]
    if "--lang" in argv:
        i = argv.index("--lang")
        langs = argv[i + 1].split(",")
        del argv[i:i + 2]
    jobs = argv or ["header", "stills", "search"]
    if "redeliver-header" in jobs:
        # Re-encode the delivery mp4s from existing masters (no re-render).
        for lang in langs:
            w, h = HEADER_SIZE
            dest = OUT / f"OSG-Header-{w}x{h}-{lang}.mp4"
            deliver(WORK / f"header-{lang}.mov", dest, HEADER_SIZE, "5.1")
            print("  " + probe(dest))
    WORK.mkdir(parents=True, exist_ok=True)
    OUT.mkdir(parents=True, exist_ok=True)
    for lang in langs:
        if "header" in jobs:
            print(f"[header {lang}]", flush=True)
            build_header(lang)
        if "stills" in jobs:
            print(f"[universal {lang}]", flush=True)
            build_universal(lang)
        if "search" in jobs:
            print(f"[search {lang}]", flush=True)
            build_search(lang)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
