#!/usr/bin/env python3
"""Raptua's own art for the Wii U bundle (raptua.wuhb), in assets/wiiu/,
from the same drawing as the Aurora art (tools/make_aurora_art.py: a
delta-wing jet over a night sky; no game art):

  icon.png        128 x 128   the HOME Menu icon
  tv_splash.png  1280 x 720   shown on the TV while it loads
  drc_splash.png  854 x 480   shown on the GamePad while it loads

    python3 tools/make_wiiu_art.py [--font PATH]
"""
import argparse
import os
import sys
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from make_aurora_art import make_background  # noqa: E402
from make_icon import draw  # noqa: E402

OUT = Path(__file__).resolve().parent.parent / "assets" / "wiiu"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--font", default="/usr/share/fonts/opentype/inter/Inter-ExtraBold.otf")
    args = ap.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    draw(128).save(OUT / "icon.png")
    tv = make_background(args.font)          # 1280 x 720
    tv.save(OUT / "tv_splash.png", optimize=True)
    tv.resize((854, 480)).save(OUT / "drc_splash.png", optimize=True)
    for n in ("icon", "tv_splash", "drc_splash"):
        print("wrote", OUT / f"{n}.png")


if __name__ == "__main__":
    main()
