#!/usr/bin/env python3
"""Draws the app icon and the iOS 6 launch images into Resources/ (needs Pillow)."""
import os
from PIL import Image, ImageDraw, ImageFilter

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Resources")
PINK, CYAN = (254, 44, 85), (37, 244, 238)


def gradient(size, top, bottom):
    w, h = size
    img = Image.new("RGB", size)
    d = ImageDraw.Draw(img)
    for y in range(h):
        t = y / max(1, h - 1)
        d.line([(0, y), (w, y)], fill=tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)))
    return img


def note(draw, s, ox, oy, color):
    # a TikTok-like quaver: round head, stem, and a hooked flag
    r = 0.17 * s
    cx, cy = ox + 0.36 * s, oy + 0.66 * s
    draw.ellipse([cx - r, cy - r, cx + r, cy + r], outline=color, width=int(0.075 * s))
    stem_x = cx + r - 0.04 * s
    draw.rectangle([stem_x, oy + 0.18 * s, stem_x + 0.085 * s, cy], fill=color)
    draw.arc([stem_x - 0.02 * s, oy + 0.02 * s, stem_x + 0.36 * s, oy + 0.38 * s], 90, 180, fill=color, width=int(0.08 * s))


def icon(px):
    s = 512
    img = gradient((s, s), (50, 50, 56), (10, 10, 12))
    layer = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    note(d, s * 0.78, s * 0.13 - 12, s * 0.1 - 6, CYAN + (255,))
    note(d, s * 0.78, s * 0.13 + 12, s * 0.1 + 6, PINK + (255,))
    note(d, s * 0.78, s * 0.13, s * 0.1, (255, 255, 255, 255))
    img.paste(layer, (0, 0), layer)
    return img.resize((px, px), Image.LANCZOS)


def launch(w, h):
    img = gradient((w, h), (34, 34, 38), (12, 12, 14))
    bar = int(20 * w / 320)
    ImageDraw.Draw(img).rectangle([0, 0, w, bar], fill=(0, 0, 0))
    ic = icon(int(w * 0.3))
    img.paste(ic, ((w - ic.width) // 2, (h - ic.height) // 2))
    return img


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    for name, px in [("Icon.png", 57), ("Icon@2x.png", 114), ("Icon-72.png", 72), ("Icon-72@2x.png", 144)]:
        icon(px).save(os.path.join(OUT, name))
    for name, (w, h) in [("Default.png", (320, 480)), ("Default@2x.png", (640, 960)),
                         ("Default-568h@2x.png", (640, 1136)), ("Default-Portrait~ipad.png", (768, 1024)),
                         ("Default-Portrait@2x~ipad.png", (1536, 2048))]:
        launch(w, h).save(os.path.join(OUT, name))
    print("assets written to", os.path.normpath(OUT))
