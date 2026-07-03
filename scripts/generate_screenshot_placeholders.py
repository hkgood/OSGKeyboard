#!/usr/bin/env python3
"""
generate_screenshot_placeholders.py

Generates App Store screenshot placeholders for OSGKeyboard.
Apple App Store Connect accepts:
  - 6.7" (iPhone 17 Pro Max, 17, 16 Pro Max, 16 Plus, 15 Pro Max, 15 Plus) → 1290 × 2796
  - 6.1" (iPhone 17 Pro, 17, 16 Pro, 16, 15 Pro, 15, 14 Pro)                → 1179 × 2556

We produce 5 of each (Apple requires 3 minimum, accepts up to 10).

These are INTENTIONALLY bland placeholders — the marketing team should
screenshot the actual app running in the iOS 26 Simulator and replace
these before final upload. The script only verifies dimensions and
labels.

Run:
  python3 scripts/generate_screenshot_placeholders.py
"""
import os
import sys
from PIL import Image, ImageDraw, ImageFont

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(REPO_ROOT, "docs", "screenshots")

SCREENS = [
    {
        "id": "01-keyboard-default",
        "headline": "Hold to talk",
        "subtitle": "Push-to-talk from any app's text field.",
    },
    {
        "id": "02-flow-session",
        "headline": "Continuous flow",
        "subtitle": "One session, many utterances — no app switching.",
    },
    {
        "id": "03-on-device-asr",
        "headline": "On-device speech",
        "subtitle": "Audio never leaves your iPhone.",
    },
    {
        "id": "04-llm-polish",
        "headline": "AI-polished output",
        "subtitle": "Punctuation, structure, grammar — choose your LLM.",
    },
    {
        "id": "05-providers",
        "headline": "Bring your own key",
        "subtitle": "OpenAI, DeepSeek, Qwen, Moonshot, Zhipu, or self-hosted.",
    },
]

PALETTE = {
    "bg_top":    (15, 17, 26),
    "bg_bot":    (28, 32, 48),
    "accent":    (110, 168, 254),
    "text":      (245, 246, 250),
    "subtext":   (170, 178, 196),
    "card":      (38, 43, 60),
    "divider":   (62, 70, 92),
}

def get_font(size, bold=False):
    candidates = [
        "/System/Library/Fonts/Supplemental/Arial Bold.ttf" if bold else "/System/Library/Fonts/Supplemental/Arial.ttf",
        "/System/Library/Fonts/Helvetica.ttc",
        "/Library/Fonts/Arial.ttf",
    ]
    for path in candidates:
        if os.path.exists(path):
            try:
                return ImageFont.truetype(path, size)
            except Exception:
                continue
    return ImageFont.load_default()

def draw_dashed(draw, x1, y1, x2, y2, dash=14, gap=10, fill=PALETTE["divider"], width=2):
    if y1 == y2:
        x = x1
        while x < x2:
            draw.line([(x, y1), (min(x + dash, x2), y1)], fill=fill, width=width)
            x += dash + gap
    else:
        y = y1
        while y < y2:
            draw.line([(x1, y), (x1, y + min(dash, y2 - y))], fill=fill, width=width)
            y += dash + gap

def render(path, width, height, screen):
    img = Image.new("RGB", (width, height), PALETTE["bg_top"])
    draw = ImageDraw.Draw(img)
    # vertical gradient
    for y in range(height):
        t = y / height
        r = int(PALETTE["bg_top"][0] * (1 - t) + PALETTE["bg_bot"][0] * t)
        g = int(PALETTE["bg_top"][1] * (1 - t) + PALETTE["bg_bot"][1] * t)
        b = int(PALETTE["bg_top"][2] * (1 - t) + PALETTE["bg_bot"][2] * t)
        draw.line([(0, y), (width, y)], fill=(r, g, b))

    # status bar mock
    status_y = int(height * 0.02)
    draw.text((width * 0.06, status_y), "9:41",
              font=get_font(int(height * 0.022), bold=True), fill=PALETTE["text"])
    draw.text((width * 0.86, status_y), "5G  100%",
              font=get_font(int(height * 0.018)), fill=PALETTE["subtext"])

    # status bar divider
    draw_dashed(draw, width * 0.05, status_y + height * 0.045, width * 0.95, status_y + height * 0.045)

    # big rounded "phone" mock card
    card_pad = int(width * 0.07)
    card_top = int(height * 0.10)
    card_bot = int(height * 0.88)
    card = (card_pad, card_top, width - card_pad, card_bot)
    radius = int(width * 0.07)
    draw.rounded_rectangle(card, radius=radius, fill=PALETTE["card"], outline=PALETTE["divider"], width=2)

    # mock keyboard hint
    kbd_h = int((card_bot - card_top) * 0.22)
    kbd_y0 = card_bot - kbd_h - int(width * 0.04)
    kbd = (card[0] + int(width * 0.03), kbd_y0, card[2] - int(width * 0.03), kbd_y0 + kbd_h)
    draw.rounded_rectangle(kbd, radius=int(width * 0.02), fill=PALETTE["bg_top"], outline=PALETTE["divider"], width=2)
    # mic dot
    mic_cx = (kbd[0] + kbd[2]) // 2
    mic_cy = (kbd[1] + kbd[3]) // 2
    mic_r = int(kbd_h * 0.30)
    draw.ellipse((mic_cx - mic_r, mic_cy - mic_r, mic_cx + mic_r, mic_cy + mic_r),
                 fill=PALETTE["accent"])

    # headline + subtitle
    headline_y = int(height * 0.18)
    draw.text((width // 2, headline_y), screen["headline"],
              font=get_font(int(height * 0.055), bold=True), fill=PALETTE["text"], anchor="mm")
    sub_y = headline_y + int(height * 0.07)
    # wrap subtitle
    words = screen["subtitle"].split()
    line = ""
    sub_font = get_font(int(height * 0.028))
    max_sub_w = int(width * 0.78)
    lines = []
    for w in words:
        test = (line + " " + w).strip()
        if draw.textlength(test, font=sub_font) > max_sub_w:
            lines.append(line)
            line = w
        else:
            line = test
    if line:
        lines.append(line)
    for i, l in enumerate(lines):
        draw.text((width // 2, sub_y + i * int(height * 0.04)),
                  l, font=sub_font, fill=PALETTE["subtext"], anchor="mm")

    # watermark
    draw.text((width // 2, int(height * 0.965)),
              "OSGKeyboard · screenshot placeholder",
              font=get_font(int(height * 0.014)), fill=PALETTE["subtext"], anchor="mm")

    img.save(path, "PNG", optimize=True)
    return path

def main():
    sizes = {
        "6.7": (1290, 2796),
        "6.1": (1179, 2556),
    }
    total = 0
    for size_id, (w, h) in sizes.items():
        out_dir = os.path.join(OUT_DIR, size_id)
        os.makedirs(out_dir, exist_ok=True)
        for s in SCREENS:
            path = os.path.join(out_dir, f"{s['id']}.png")
            render(path, w, h, s)
            print(f"  wrote {path} ({w}×{h})")
            total += 1
    print(f"\nDone. {total} placeholders written under {OUT_DIR}")
    print("REPLACE these with real Simulator screenshots before App Store upload.")

if __name__ == "__main__":
    sys.exit(main())
