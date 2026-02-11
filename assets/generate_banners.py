#!/usr/bin/env python3
"""Generate PNG banners from ASCII art text files."""

import os
from PIL import Image, ImageDraw, ImageFont

FONT_PATH = "/usr/share/fonts/liberation/LiberationMono-Bold.ttf"
FONT_SIZE = 20
PADDING = 20
TEXT_COLOR = (255, 255, 255, 255)
BG_COLOR = (0, 0, 0, 0)

ASSETS_DIR = os.path.dirname(os.path.abspath(__file__))

BANNERS = [
    ("banner.txt", "banner.png"),
    ("banner-cursor.txt", "banner-cursor.png"),
]


def render(src, dst):
    with open(os.path.join(ASSETS_DIR, src)) as f:
        lines = [l.rstrip() for l in f.readlines() if l.strip()]

    font = ImageFont.truetype(FONT_PATH, FONT_SIZE)

    dummy = Image.new("RGBA", (1, 1))
    draw = ImageDraw.Draw(dummy)
    max_width = 0
    line_height = 0
    for line in lines:
        bbox = draw.textbbox((0, 0), line, font=font)
        w = bbox[2] - bbox[0]
        h = bbox[3] - bbox[1]
        if w > max_width:
            max_width = w
        if h > line_height:
            line_height = h

    img_w = max_width + PADDING * 2
    img_h = line_height * len(lines) + PADDING * 2

    img = Image.new("RGBA", (img_w, img_h), BG_COLOR)
    draw = ImageDraw.Draw(img)

    y = PADDING
    for line in lines:
        draw.text((PADDING, y), line, font=font, fill=TEXT_COLOR)
        y += line_height

    out = os.path.join(ASSETS_DIR, dst)
    img.save(out)
    print(f"{dst} ({img_w}x{img_h})")


if __name__ == "__main__":
    for src, dst in BANNERS:
        render(src, dst)
