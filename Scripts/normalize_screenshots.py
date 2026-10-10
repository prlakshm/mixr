#!/usr/bin/env python3
"""Bakes EXIF orientation into simulator screenshots (XCUIScreen saves
landscape captures as portrait pixels + an orientation tag) and strips the
metadata, so each PNG is a plain 2868x1320-style landscape image.

    python3 Scripts/normalize_screenshots.py <dir>
"""
import pathlib
import sys

from PIL import Image, ImageOps

for path in sorted(pathlib.Path(sys.argv[1]).glob("*.png")):
    with Image.open(path) as im:
        upright = ImageOps.exif_transpose(im).convert("RGB")
    upright.save(path, format="PNG")
    print(f"{path.name}: {upright.size[0]}x{upright.size[1]}")
