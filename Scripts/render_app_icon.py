#!/usr/bin/env python3
"""Render the Mixr app-icon layer.

Reproduces the canonical mark from tmp/imagegen/render_equal_spacing.swift —
same bar order, gradients and sheen — but sized and optically centred for an
Icon Composer layer rather than a full-bleed logo.

Two things the hand-built artwork got wrong and this fixes:

  * spacing and widths drifted (113-124px apart, 68-73px wide). The spec is
    exactly 137px centre-to-centre and 88px wide for every bar.
  * the group was centred by bounding box, but the mark's mass sits left —
    bar 3 is the 880px peak and bar 4 the 390px dip, so geometric centring
    reads left-heavy. The group is offset right by its own area centroid.

Bar order is deliberately unchanged; it matches the app logo.

    python3 Scripts/render_app_icon.py "Mixr/AppIcon.icon/Assets/mixr logo 4.png"

Geometry is exact and whole-pixel (see ICON_* below).
"""

import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

CANVAS = 1254
SS = 2  # supersample factor

BACKGROUND = "#14052B"

# Canonical geometry: 137px centre-to-centre, 88px wide, group midpoint on the
# canvas midpoint. Heights are the app-logo order — short, tall, peak, dip,
# tall, short.
BAR_CENTRES = np.array([284.5, 421.5, 558.5, 695.5, 832.5, 969.5])
BAR_WIDTH = 88.0
BAR_TOPS = np.array([510.0, 312.0, 195.0, 462.0, 310.0, 510.0])
BAR_HEIGHTS = np.array([250.0, 632.0, 880.0, 390.0, 634.0, 250.0])

# The mark fills 61.6% of the canvas at spec size; an icon layer wants it
# nearer 52%, which lands ~56% of the rendered tile at Icon Composer scale.
MARK_WIDTH_FRACTION = 0.524

# Put every bar on one horizontal axis.
#
# In the spec the bars' vertical centres are 635/628/635/657/627/635 — five of
# them inside an 8px band and bar 4 hanging 25px below the rest. That one bar
# is what tilts the mark: fit a line through the six centres and the slope is
# +0.0040, drop bar 4 and it is -0.0013, i.e. flat. A waveform reads off a
# shared centre line, so the drop is drift rather than intent, and correcting
# it removes the slant without touching any bar's height or order.
ALIGN_BAR_CENTRES = True

BAR_GRADIENT = (
    [(0xA4, 0x5C, 0xFF), (0x7E, 0x2B, 0xEA), (0x5C, 0x23, 0xBE), (0x46, 0x10, 0xAD)],
    [0.0, 0.12, 0.58, 1.0],
)
# The standalone logo carries an ambient wash down the field. The icon does
# not: iOS already lays its own specular sheen over the tile, and the two
# together read as a light purple gradient rather than a flat brand field.
AMBIENT = None
SHEEN = (
    [(0xFF, 0xFF, 0xFF, 0.34), (0xCF, 0xA9, 0xFF, 0.12), (0xFF, 0xFF, 0xFF, 0.0)],
    [0.0, 0.36, 1.0],
)
SHADOW_COLOUR = (0x7A, 0x24, 0xF0)
SHADOW_ALPHA = 0.30
SHADOW_BLUR = 18.0
SHADOW_DY = 3.0
STROKE_ALPHA = 0.075
STROKE_WIDTH = 1.5


def ramp(stops, locs, t):
    """Sample a multi-stop gradient at normalised positions `t`."""
    out = np.zeros(t.shape + (len(stops[0]),))
    for ch in range(len(stops[0])):
        out[..., ch] = np.interp(t, locs, [s[ch] for s in stops])
    return out


# Exact whole-pixel geometry (1254 canvas). Earlier passes placed bars at
# fractional positions and nudged the group toward its area centroid; at
# icon size that read as spacing that alternated 116/117 px and a mark sitting
# 9 px right of centre. Now:
#   * 72 px bars on a constant 120 px pitch (48 px gaps),
#   * the group geometrically centred: 291 px margins on both sides,
#   * every bar centred on the canvas mid-line (627 px), even heights so
#     tops and bottoms land on whole pixels,
#   * taller bars to match the waveform beside "Mixr" in the app: the peak
#     is 768 px, ~10.7× the bar width (was ~9.7×).
ICON_BAR_WIDTH = 72
ICON_PITCH = 120
ICON_PEAK = 768
ICON_RELATIVE_HEIGHTS = [0.29, 0.72, 1.0, 0.45, 0.72, 0.29]   # app-logo order


def solve_geometry():
    n = len(ICON_RELATIVE_HEIGHTS)
    span = n * ICON_BAR_WIDTH + (n - 1) * ICON_PITCH - (n - 1) * ICON_BAR_WIDTH
    left = (CANVAS - span) // 2
    assert CANVAS - span - 2 * left == 0, "group must centre on whole pixels"
    centres = np.array([left + ICON_BAR_WIDTH / 2 + i * ICON_PITCH for i in range(n)], dtype=float)
    heights = np.array([2 * round(h * ICON_PEAK / 2) for h in ICON_RELATIVE_HEIGHTS], dtype=float)
    tops = CANVAS / 2 - heights / 2
    width = float(ICON_BAR_WIDTH)
    scale = width / BAR_WIDTH          # sheen and shadow scale with the bars
    return centres, width, tops, heights, scale


def render(path):
    centres, width, tops, heights, scale = solve_geometry()
    n = CANVAS * SS
    bg = tuple(int(BACKGROUND[i : i + 2], 16) for i in (1, 3, 5))
    base = Image.new("RGB", (n, n), bg)

    if AMBIENT is not None:
        ys = np.clip((np.arange(n) / SS - 80.0) / (1170.0 - 80.0), 0, 1)
        cols = ramp(AMBIENT[0], AMBIENT[1], ys)
        layer = np.repeat(cols[:, None, :], n, axis=1)
        arr = np.asarray(base).astype(float)
        a = layer[..., 3:4]
        base = Image.fromarray((arr * (1 - a) + layer[..., :3] * a).astype(np.uint8))

    shadow = Image.new("L", (n, n), 0)
    sd = ImageDraw.Draw(shadow)
    for cx, top, h in zip(centres, tops, heights):
        x0, x1 = (cx - width / 2) * SS, (cx + width / 2) * SS
        y0 = (top + SHADOW_DY) * SS
        y1 = (top + h + SHADOW_DY) * SS
        sd.rounded_rectangle([x0, y0, x1, y1], (width / 2) * SS, fill=255)
    shadow = shadow.filter(ImageFilter.GaussianBlur(SHADOW_BLUR * SS / 2))
    tint = Image.new("RGB", (n, n), SHADOW_COLOUR)
    base = Image.composite(
        Image.blend(base, tint, SHADOW_ALPHA), base, shadow
    )

    for cx, top, h in zip(centres, tops, heights):
        x0, x1 = (cx - width / 2) * SS, (cx + width / 2) * SS
        y0, y1 = top * SS, (top + h) * SS
        mask = Image.new("L", (n, n), 0)
        ImageDraw.Draw(mask).rounded_rectangle(
            [x0, y0, x1, y1], (width / 2) * SS, fill=255
        )

        t = np.clip((np.arange(n) - y0) / max(y1 - y0, 1), 0, 1)
        fill = ramp(BAR_GRADIENT[0], BAR_GRADIENT[1], t)
        fill_img = Image.fromarray(
            np.repeat(fill[:, None, :], n, axis=1).astype(np.uint8)
        )
        base = Image.composite(fill_img, base, mask)

        # Top-leading sheen, as a radial falloff.
        scx, scy = (cx - 12 * scale) * SS, (top + 10 * scale) * SS
        yy, xx = np.mgrid[0:n, 0:n]
        r = np.sqrt((xx - scx) ** 2 + (yy - scy) ** 2) / (75 * scale * SS)
        s = ramp(SHEEN[0], SHEEN[1], np.clip(r, 0, 1))
        sa = s[..., 3] * (np.asarray(mask) / 255.0)
        arr = np.asarray(base).astype(float)
        base = Image.fromarray(
            (arr * (1 - sa[..., None]) + s[..., :3] * sa[..., None]).astype(np.uint8)
        )

        rim = Image.new("L", (n, n), 0)
        ImageDraw.Draw(rim).rounded_rectangle(
            [x0, y0, x1, y1],
            (width / 2) * SS,
            outline=255,
            width=max(1, int(STROKE_WIDTH * SS)),
        )
        white = Image.new("RGB", (n, n), (255, 255, 255))
        base = Image.composite(
            Image.blend(base, white, STROKE_ALPHA), base, rim
        )

    base.resize((CANVAS, CANVAS), Image.LANCZOS).save(path)
    print(f"wrote {path}")
    print(f"  bar spacing {np.diff(centres).round(1).tolist()} px (uniform)")
    print(f"  bar width   {width:.1f} px")
    print(f"  heights     {heights.round(0).astype(int).tolist()}")


if __name__ == "__main__":
    render(sys.argv[1] if len(sys.argv) > 1 else "icon-layer.png")
