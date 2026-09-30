#!/usr/bin/env python3
"""Draws the DMG window background (660x400 pt, 1x and 2x) and merges them into
background.tiff, which Finder picks at the right scale on Retina screens.

    python3 dmg/make-background.py
"""
import subprocess
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

HERE = Path(__file__).resolve().parent
FONT = "/System/Library/Fonts/SFNS.ttf"
W, H = 660, 400
PAPER = (251, 250, 247)
INK = (28, 26, 21)
MUTED = (110, 106, 96)
LINE = (226, 222, 212)
GREEN = (28, 115, 94)


def font(size, weight="Regular"):
    f = ImageFont.truetype(FONT, size)
    f.set_variation_by_name(weight)
    return f


def draw(scale):
    s = lambda v: int(v * scale)
    img = Image.new("RGB", (s(W), s(H)), PAPER)
    d = ImageDraw.Draw(img)
    d.line([(0, s(H - 64)), (s(W), s(H - 64))], fill=LINE, width=max(1, s(1)))

    # Arrow between the two icons (icons sit at x=170 and x=490, y=190).
    y = s(190)
    d.line([(s(262), y), (s(392), y)], fill=GREEN, width=s(3))
    d.polygon([(s(398), y), (s(384), y - s(9)), (s(384), y + s(9))], fill=GREEN)

    title = "Drag StockDock into Applications"
    f = font(s(17), "Semibold")
    tw = d.textlength(title, font=f)
    d.text(((s(W) - tw) / 2, s(58)), title, font=f, fill=INK)

    foot = "Free and open source · stockdockapp.com"
    f2 = font(s(12))
    fw = d.textlength(foot, font=f2)
    d.text(((s(W) - fw) / 2, s(H - 42)), foot, font=f2, fill=MUTED)
    return img


def main():
    one, two = HERE / "bg.png", HERE / "bg@2x.png"
    draw(1).save(one)
    draw(2).save(two)
    subprocess.run(["tiffutil", "-cathidpicheck", str(one), str(two), "-out", str(HERE / "background.tiff")],
                   check=True, capture_output=True)
    one.unlink()
    two.unlink()
    print("dmg/background.tiff")


if __name__ == "__main__":
    main()
